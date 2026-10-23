(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

open Sinter_core
module Gen = QCheck2.Gen

let property ?(count = 500) ~name ~print generator check =
  QCheck_alcotest.to_alcotest ~speed_level:`Quick
    (QCheck2.Test.make ~count ~name ~print generator check)

(* One reader for the whole group: loading the grammar is the slow
   part. *)
let reader =
  lazy
    (match Markdown.create (Sinter_bridge.create ()) with
    | Ok reader -> reader
    | Error _ -> failwith "the reader does not start")

let read text = Markdown.read (Lazy.force reader) text

let span (span : Markdown.span) =
  Printf.sprintf "%d:%d-%d:%d" span.start.line span.start.column span.stop.line
    span.stop.column

let option show = function None -> "-" | Some value -> show value

(* The structure as lines of text, one line for each section, tag line,
   block, unread paragraph, and parse failure. A hash shows its first
   eight digits. *)
let describe (file : Markdown.t) =
  let sections =
    Array.to_list
      (Array.mapi
         (fun index (section : Markdown.section) ->
           Printf.sprintf "section %d level %d%s parent %s first %s extent %s"
             index section.level
             ( option
                 (fun (heading : Markdown.heading) ->
                   Printf.sprintf " %S slug %s name %s at %s" heading.text
                     heading.slug heading.name (span heading.span))
                 section.heading
             |> fun text -> if text = "-" then "" else text )
             (option string_of_int section.parent)
             (option span section.first_paragraph)
             (option span section.extent))
         file.sections)
  in
  let tags =
    Array.to_list
      (Array.mapi
         (fun index (tag : Markdown.tag) ->
           Printf.sprintf
             "tag %d @%s target %s rev %s desc %S at %s block %d %s section %d \
              owner %s extent %s"
             index tag.word (option Fun.id tag.target)
             (option string_of_int tag.rev)
             tag.desc (span tag.span) tag.block
             (match tag.node with
             | Section_paragraph -> "section-paragraph"
             | Item_paragraph -> "item-paragraph")
             tag.section
             (option string_of_int tag.owner)
             (option
                (fun (extent : Markdown.extent) ->
                  Printf.sprintf "%d-%d %s" extent.first extent.last
                    (String.sub extent.hash 0 8))
                tag.extent))
         file.tags)
  in
  let blocks =
    Array.to_list
      (Array.mapi
         (fun index (block : Markdown.block) ->
           Printf.sprintf "block %d tags %s prose %s hash %s" index
             (String.concat "," (List.map string_of_int block.tags))
             (String.concat "|" (List.map (Printf.sprintf "%S") block.prose))
             (String.sub block.hash 0 8))
         file.blocks)
  in
  String.concat "\n"
    (sections @ tags @ blocks
    @ List.map (fun place -> "unread " ^ span place) file.unread
    @ List.map (fun place -> "error " ^ span place) file.errors)

let structure text =
  match read text with
  | Ok file -> describe file
  | Error (Markdown.Not_utf_8 offset) -> Printf.sprintf "not UTF-8 at %d" offset
  | Error (Markdown.No_tree error) -> Sinter_bridge.Tree.message error

let check_structure text expected () =
  Alcotest.(check string)
    "the structure"
    (String.concat "\n" expected)
    (structure text)

let file text =
  match read text with
  | Ok file -> file
  | Error _ -> Alcotest.fail "the text gave no structure"

let hex text = Sha256.hex text

(* {1 The reader} *)

let read_after_close_is_refused () =
  match Markdown.create (Sinter_bridge.create ()) with
  | Error _ -> Alcotest.fail "the reader does not start"
  | Ok reader ->
      Markdown.close reader;
      Markdown.close reader;
      Alcotest.(check bool)
        "a read after close raises Invalid_argument" true
        (match Markdown.read reader "# A\n" with
        | exception Invalid_argument _ -> true
        | _ -> false)

let create_on_a_closed_engine_is_refused () =
  let engine = Sinter_bridge.create () in
  Sinter_bridge.close engine;
  Alcotest.(check bool)
    "create raises Invalid_argument" true
    (match Markdown.create engine with
    | exception Invalid_argument _ -> true
    | _ -> false)

let text_that_is_not_utf_8_gives_its_offset =
  check_structure "# A\n@req a v1 caf\xe9\n" [ "not UTF-8 at 17" ]

(* {1 Sections} *)

let headings_give_text_slug_and_name =
  check_structure
    "# A ##\n## B#\n### C \\#\n#### #\n#\n#\t Tabbed \t#\t\n# a\n# a\n# a-1\n"
    [
      "section 0 level 1 \"A\" slug a name a at 1:1-1:7 parent - first - \
       extent 1:1-4:7";
      "section 1 level 2 \"B#\" slug b name b at 2:1-2:6 parent 0 first - \
       extent 2:1-4:7";
      "section 2 level 3 \"C \\\\#\" slug c name c at 3:1-3:9 parent 1 first - \
       extent 3:1-4:7";
      "section 3 level 4 \"\" slug  name  at 4:1-4:7 parent 2 first - extent \
       4:1-4:7";
      "section 4 level 1 \"\" slug  name -1 at 5:1-5:2 parent - first - extent \
       5:1-5:2";
      "section 5 level 1 \"Tabbed\" slug tabbed name tabbed at 6:1-6:14 parent \
       - first - extent 6:1-6:14";
      "section 6 level 1 \"a\" slug a name a-1 at 7:1-7:4 parent - first - \
       extent 7:1-7:4";
      "section 7 level 1 \"a\" slug a name a-2 at 8:1-8:4 parent - first - \
       extent 8:1-8:4";
      "section 8 level 1 \"a-1\" slug a-1 name a-1-1 at 9:1-9:6 parent - first \
       - extent 9:1-9:6";
    ]

(* A heading in a block quote or a list item opens no section. Nothing
   in a block quote is read, and a paragraph after a heading in a list
   item is not the first paragraph of the item. *)
let containers_open_no_section =
  check_structure
    "# Title\n\n\
     > # Quoted\n\
     > @req q v1\n\n\
     - # In item\n\
    \  @req i v1\n\n\
     > - @req qi v1\n\
     >   @cites y v1\n"
    [
      "section 0 level 1 \"Title\" slug title name title at 1:1-1:8 parent - \
       first - extent 1:1-10:16";
      "unread 7:3-7:12";
    ]

let first_block_must_be_a_paragraph =
  check_structure
    "# Comment first\n\
     <!-- note -->\n\
     @req a v1\n\n\
     # Code first\n\
     ```\n\
     x\n\
     ```\n\
     @req b v1\n\n\
     # Table first\n\
     | a |\n\
     |---|\n\n\
     @req c v1\n\n\
     # Break first\n\
     ---\n\
     @req d v1\n\n\
     # Quote first\n\
     > q\n\n\
     @req e v1\n\n\
     # Setext first\n\
     Title\n\
     =====\n\
     @req f v1\n"
    [
      "section 0 level 1 \"Comment first\" slug comment-first name \
       comment-first at 1:1-1:16 parent - first - extent 1:1-3:10";
      "section 1 level 1 \"Code first\" slug code-first name code-first at \
       5:1-5:13 parent - first - extent 5:1-9:10";
      "section 2 level 1 \"Table first\" slug table-first name table-first at \
       11:1-11:14 parent - first - extent 11:1-15:10";
      "section 3 level 1 \"Break first\" slug break-first name break-first at \
       17:1-17:14 parent - first - extent 17:1-19:10";
      "section 4 level 1 \"Quote first\" slug quote-first name quote-first at \
       21:1-21:14 parent - first - extent 21:1-24:10";
      "section 5 level 1 \"Setext first\" slug setext-first name setext-first \
       at 26:1-26:15 parent - first - extent 26:1-29:10";
      "unread 3:1-3:10";
      "unread 9:1-9:10";
      "unread 15:1-15:10";
      "unread 19:1-19:10";
      "unread 24:1-24:10";
      "unread 29:1-29:10";
    ]

let front_matter_is_no_block =
  check_structure "+++\ntitle = \"x\"\n+++\n@req fm v1\nText.\n\n# H\n"
    [
      "section 0 level 0 parent - first 4:1-5:6 extent 1:1-5:6";
      "section 1 level 1 \"H\" slug h name h at 7:1-7:4 parent - first - \
       extent 7:1-7:4";
      "tag 0 @req target fm rev 1 desc \"\" at 4:1-4:11 block 0 \
       section-paragraph section 0 owner 0 extent 1-5 839897f1";
      "block 0 tags 0 prose \"Text.\" hash 1fb3b971";
    ]

let yaml_front_matter_is_no_block =
  check_structure "---\na: 1\n---\n@req yaml v1\n"
    [
      "section 0 level 0 parent - first 4:1-4:13 extent 1:1-4:13";
      "tag 0 @req target yaml rev 1 desc \"\" at 4:1-4:13 block 0 \
       section-paragraph section 0 owner 0 extent 1-4 8a4e7411";
      "block 0 tags 0 prose  hash 01ba4719";
    ]

let section_of_declared_items_alone_has_no_extent =
  check_structure "- @req a v1\n- @req b v1\n"
    [
      "section 0 level 0 parent - first - extent -";
      "tag 0 @req target a rev 1 desc \"\" at 1:3-1:12 block 0 item-paragraph \
       section 0 owner 0 extent 1-1 01ba4719";
      "tag 1 @req target b rev 1 desc \"\" at 2:3-2:12 block 1 item-paragraph \
       section 0 owner 1 extent 2-2 01ba4719";
      "block 0 tags 0 prose  hash 01ba4719";
      "block 1 tags 1 prose  hash 01ba4719";
    ]

(* {1 Tag lines} *)

let list_items_drop_their_markers =
  check_structure
    "- @req a v1\n\
     * @req b v1\n\
     + @req c v1\n\
     1. @req d v1\n\
     2) @req e v1\n\
     - [ ] @req f v1\n\
     - [x] @req g v1\n\
     - [X] @req h v1\n\
     -\n\
    \  @req i v1\n\
     - item\n\
     @req j v1\n"
    [
      "section 0 level 0 parent - first - extent -";
      "tag 0 @req target a rev 1 desc \"\" at 1:3-1:12 block 0 item-paragraph \
       section 0 owner 0 extent 1-1 01ba4719";
      "tag 1 @req target b rev 1 desc \"\" at 2:3-2:12 block 1 item-paragraph \
       section 0 owner 1 extent 2-2 01ba4719";
      "tag 2 @req target c rev 1 desc \"\" at 3:3-3:12 block 2 item-paragraph \
       section 0 owner 2 extent 3-3 01ba4719";
      "tag 3 @req target d rev 1 desc \"\" at 4:4-4:13 block 3 item-paragraph \
       section 0 owner 3 extent 4-4 01ba4719";
      "tag 4 @req target e rev 1 desc \"\" at 5:4-5:13 block 4 item-paragraph \
       section 0 owner 4 extent 5-5 01ba4719";
      "tag 5 @req target f rev 1 desc \"\" at 6:7-6:16 block 5 item-paragraph \
       section 0 owner 5 extent 6-6 01ba4719";
      "tag 6 @req target g rev 1 desc \"\" at 7:7-7:16 block 6 item-paragraph \
       section 0 owner 6 extent 7-7 01ba4719";
      "tag 7 @req target h rev 1 desc \"\" at 8:7-8:16 block 7 item-paragraph \
       section 0 owner 7 extent 8-8 01ba4719";
      "tag 8 @req target i rev 1 desc \"\" at 10:3-10:12 block 8 \
       item-paragraph section 0 owner 8 extent 9-10 37ae5433";
      "tag 9 @req target j rev 1 desc \"\" at 12:1-12:10 block 9 \
       item-paragraph section 0 owner 9 extent 11-12 ca5f0357";
      "block 0 tags 0 prose  hash 01ba4719";
      "block 1 tags 1 prose  hash 01ba4719";
      "block 2 tags 2 prose  hash 01ba4719";
      "block 3 tags 3 prose  hash 01ba4719";
      "block 4 tags 4 prose  hash 01ba4719";
      "block 5 tags 5 prose  hash 01ba4719";
      "block 6 tags 6 prose  hash 01ba4719";
      "block 7 tags 7 prose  hash 01ba4719";
      "block 8 tags 8 prose  hash 01ba4719";
      "block 9 tags 9 prose  hash 01ba4719";
    ]

(* A byte order mark, CRLF line endings, and characters of two and
   four bytes. *)
let places_count_characters =
  check_structure
    "\xef\xbb\xbf# H\xc3\xa9 \r\n\
     @cites \xc3\xa9 v1 caf\xc3\xa9  \r\n\
    \  Prose \xf0\x9f\x98\x80.  \r\n"
    [
      "section 0 level 1 \"H\\195\\169\" slug h name h at 1:1-1:6 parent - \
       first 2:1-3:11 extent 1:1-3:13";
      "tag 0 @cites target \xc3\xa9 rev 1 desc \" caf\\195\\169  \" at \
       2:1-2:19 block 0 section-paragraph section 0 owner - extent -";
      "block 0 tags 0 prose \"  Prose \\240\\159\\152\\128.  \" hash e527adfd";
    ]

let tag_line_after_prose_starts_a_block =
  check_structure
    "# S\n@req a v1\n@cites x v1\nProse one.\nProse two.\n@cites y\nMore.\n"
    [
      "section 0 level 1 \"S\" slug s name s at 1:1-1:4 parent - first 2:1-7:6 \
       extent 1:1-7:6";
      "tag 0 @req target a rev 1 desc \"\" at 2:1-2:10 block 0 \
       section-paragraph section 0 owner 0 extent 1-7 5c342cff";
      "tag 1 @cites target x rev 1 desc \"\" at 3:1-3:12 block 0 \
       section-paragraph section 0 owner 0 extent -";
      "tag 2 @cites target y rev - desc \"\" at 6:1-6:9 block 1 \
       section-paragraph section 0 owner 0 extent -";
      "block 0 tags 0,1 prose \"Prose one.\"|\"Prose two.\" hash f4f985ed";
      "block 1 tags 2 prose \"More.\" hash fcd61be0";
    ]

(* {1 Extents} *)

let two_declarations_split_one_node =
  check_structure
    "# Two\n\
     @req a v1 First.\n\
     Prose a.\n\
     @req b v2 Second.\n\
     Prose b.\n\n\
     - @req c v1\n\
    \  @cites a v1\n\n\
     ## Inner\n\
     @cites b v2\n\n\n\
     # Next\n"
    [
      "section 0 level 1 \"Two\" slug two name two at 1:1-1:6 parent - first \
       2:1-5:9 extent 1:1-11:12";
      "section 1 level 2 \"Inner\" slug inner name inner at 10:1-10:9 parent 0 \
       first 11:1-11:12 extent 10:1-11:12";
      "section 2 level 1 \"Next\" slug next name next at 14:1-14:7 parent - \
       first - extent 14:1-14:7";
      "tag 0 @req target a rev 1 desc \" First.\" at 2:1-2:17 block 0 \
       section-paragraph section 0 owner 0 extent 1-3 fdc4871b";
      "tag 1 @req target b rev 2 desc \" Second.\" at 4:1-4:18 block 1 \
       section-paragraph section 0 owner 1 extent 4-11 f0cb8f98";
      "tag 2 @req target c rev 1 desc \"\" at 7:3-7:12 block 2 item-paragraph \
       section 0 owner 2 extent 7-8 edaa6358";
      "tag 3 @cites target a rev 1 desc \"\" at 8:3-8:14 block 2 \
       item-paragraph section 0 owner 2 extent -";
      "tag 4 @cites target b rev 2 desc \"\" at 11:1-11:12 block 3 \
       section-paragraph section 1 owner 1 extent -";
      "block 0 tags 0 prose \"Prose a.\" hash d132ffe9";
      "block 1 tags 1 prose \"Prose b.\" hash 3e316c6d";
      "block 2 tags 2,3 prose  hash edaa6358";
      "block 3 tags 4 prose  hash f1029213";
    ]

let extent_hashes_follow_the_rules () =
  let file =
    file
      "# Two\n\
       @req a v1 First.\n\
       Prose a.\n\
       @req b v2 Second.\n\
       Prose b.\n\n\
       - @req c v1\n\
      \  @cites a v1\n\n\
       ## Inner\n\
       @cites b v2\n\n\n\
       # Next\n"
  in
  let hash index =
    match file.tags.(index).extent with
    | Some extent -> extent.hash
    | None -> Alcotest.fail "the tag has no extent"
  in
  Alcotest.(check string)
    "a: from the heading to the line before b"
    (hex "# Two\nFirst.\nProse a.\n")
    (hash 0);
  Alcotest.(check string)
    "b: from its tag line to the end, without the item c"
    (hex "Second.\nProse b.\n\n## Inner\n@cites b\n")
    (hash 1);
  Alcotest.(check string)
    "c: the item, its marker gone with its tag" (hex "\n  @cites a\n") (hash 2);
  Alcotest.(check string)
    "the block of a" (hex "First.\nProse a.\n") file.blocks.(0).hash;
  Alcotest.(check string)
    "the block of the citation in Inner" (hex "@cites b\n") file.blocks.(3).hash

(* An ack line goes, the own tag line becomes its trimmed description,
   and a citation loses its revision and the blanks before it. A token
   that is not a revision stays. *)
let hash_normalizes_each_line () =
  let file =
    file
      "# A\n\
       @req a v3 Text.  \n\
       @ack disendorsed x 01ba4719\n\
       @cites x v2 because\n\
       @satisfies y\t v1\n\
       @cites gh/4 v0\n"
  in
  let expected =
    hex "# A\nText.\n@cites x because\n@satisfies y\n@cites gh/4 v0\n"
  in
  Alcotest.(check (option string))
    "the extent hash" (Some expected)
    (Option.map
       (fun (extent : Markdown.extent) -> extent.hash)
       file.tags.(0).extent);
  Alcotest.(check string)
    "the block hash"
    (hex "Text.\n@cites x because\n@satisfies y\n@cites gh/4 v0\n")
    file.blocks.(0).hash

let block_of_an_ack_alone_hashes_an_empty_text () =
  let file = file "# A\n@ack rule-x 01ba4719\n" in
  Alcotest.(check string) "the block hash" (hex "\n") file.blocks.(0).hash

let nested_declarations_leave_the_extent =
  check_structure
    "# A\n\
     @req a v1\n\n\
     ## B\n\
     @req b v1\n\
     @cites a v1\n\n\
     ### C\n\
     @cites x v1\n\n\
     ## D\n\
     @cites y v1\n\n\
     - plain\n\
    \  @cites z v1\n\n\n"
    [
      "section 0 level 1 \"A\" slug a name a at 1:1-1:4 parent - first \
       2:1-2:10 extent 1:1-15:14";
      "section 1 level 2 \"B\" slug b name b at 4:1-4:5 parent 0 first \
       5:1-6:12 extent 4:1-9:12";
      "section 2 level 3 \"C\" slug c name c at 8:1-8:6 parent 1 first \
       9:1-9:12 extent 8:1-9:12";
      "section 3 level 2 \"D\" slug d name d at 11:1-11:5 parent 0 first \
       12:1-12:12 extent 11:1-15:14";
      "tag 0 @req target a rev 1 desc \"\" at 2:1-2:10 block 0 \
       section-paragraph section 0 owner 0 extent 1-15 075fbca7";
      "tag 1 @req target b rev 1 desc \"\" at 5:1-5:10 block 1 \
       section-paragraph section 1 owner 1 extent 4-9 66e0fb96";
      "tag 2 @cites target a rev 1 desc \"\" at 6:1-6:12 block 1 \
       section-paragraph section 1 owner 1 extent -";
      "tag 3 @cites target x rev 1 desc \"\" at 9:1-9:12 block 2 \
       section-paragraph section 2 owner 1 extent -";
      "tag 4 @cites target y rev 1 desc \"\" at 12:1-12:12 block 3 \
       section-paragraph section 3 owner 0 extent -";
      "tag 5 @cites target z rev 1 desc \"\" at 15:3-15:14 block 4 \
       item-paragraph section 3 owner 0 extent -";
      "block 0 tags 0 prose  hash 01ba4719";
      "block 1 tags 1,2 prose  hash b8a69041";
      "block 2 tags 3 prose  hash 2b7cb630";
      "block 3 tags 4 prose  hash 45348e13";
      "block 4 tags 5 prose  hash eea8fa53";
    ]

let nested_extent_hashes_skip_the_holes () =
  let file =
    file
      "# A\n\
       @req a v1\n\n\
       ## B\n\
       @req b v1\n\
       @cites a v1\n\n\
       ### C\n\
       @cites x v1\n\n\
       ## D\n\
       @cites y v1\n\n\
       - plain\n\
      \  @cites z v1\n\n\n"
  in
  Alcotest.(check (option string))
    "a: without B and C, and without the blank lines at the end"
    (Some (hex "# A\n\n\n## D\n@cites y\n\n- plain\n  @cites z\n"))
    (Option.map
       (fun (extent : Markdown.extent) -> extent.hash)
       file.tags.(0).extent)

(* A tag of a declaration word with no target, or with a target that is
   not a slug, declares nothing: it claims no extent and splits none. *)
let declaration_needs_a_slug =
  check_structure "# A\n@req\n@req a/b v1\n@design ok v1\n@req -bad\n"
    [
      "section 0 level 1 \"A\" slug a name a at 1:1-1:4 parent - first \
       2:1-5:10 extent 1:1-5:10";
      "tag 0 @req target - rev - desc \"\" at 2:1-2:5 block 0 \
       section-paragraph section 0 owner 2 extent -";
      "tag 1 @req target a/b rev 1 desc \"\" at 3:1-3:12 block 0 \
       section-paragraph section 0 owner 2 extent -";
      "tag 2 @design target ok rev 1 desc \"\" at 4:1-4:14 block 0 \
       section-paragraph section 0 owner 2 extent 1-5 9df78faf";
      "tag 3 @req target -bad rev - desc \"\" at 5:1-5:10 block 0 \
       section-paragraph section 0 owner 2 extent -";
      "block 0 tags 0,1,2,3 prose  hash 3a664064";
    ]

(* {1 Parse failures} *)

let error_node_gives_its_span =
  check_structure
    "# T\n\n| Name | D |\n| ---- | - |\n| `x`  | y |\n|      |   |\n"
    [
      "section 0 level 1 \"T\" slug t name t at 1:1-1:4 parent - first - \
       extent 1:1-4:13";
      "error 5:1-6:13";
    ]

let missing_node_gives_an_empty_span =
  check_structure "| a |\n|---|\n| x\xe2\x80\x94 |\n|  |\n"
    [ "section 0 level 0 parent - first - extent 1:1-4:5"; "error 4:4-4:4" ]

(* {1 Properties} *)

(* Lines that collide often with the forms of markdown and of tags. *)
let markdown_line =
  Gen.oneof_list
    [
      "# H";
      "## Sub";
      "### x ##";
      "#";
      "@req a v1";
      "@cites b v2";
      "@ack x 1234abcd";
      "@design c";
      "@decision d v2 Why.";
      "@req";
      "- @req e v1";
      "  @cites f v1";
      "* [ ] @req g";
      "- [x] @cites h";
      "1. item";
      "  - @req i v1";
      "> @req q v1";
      "> - x";
      "```";
      "---";
      "+++";
      "";
      "   ";
      "text";
      "| a | b |";
      "|---|---|";
      "|  |  |";
      "    code";
      "<!-- c -->";
      "Title";
      "=====";
      "- # In item";
      "\t@req t";
      "@";
      "@req \xc3\xa9 v1";
      "x\r";
      "\xf0\x9f\x98\x80 @cites z";
      "@supersedes a v1";
    ]

let markdown_text =
  Gen.map3
    (fun mark ending lines ->
      (if mark then "\xEF\xBB\xBF" else "") ^ String.concat ending lines)
    (Gen.oneof_weighted [ (1, Gen.return true); (5, Gen.return false) ])
    (Gen.oneof_list [ "\n"; "\r\n" ])
    (Gen.list_size (Gen.int_range 0 14) markdown_line)

let any_bytes =
  Gen.oneof
    [
      Gen.string_size ~gen:Gen.char (Gen.int_range 0 40);
      Gen.map (fun (_, text) -> text) Generators.not_utf_8_string_at;
      markdown_text;
    ]

let read_answers_any_bytes =
  property ~name:"read gives a structure or the first byte that is not UTF-8"
    ~print:String.escaped any_bytes (fun text ->
      match (read text, Sinter_bridge.Utf_8.first_invalid text) with
      | Ok _, None -> true
      | Error (Markdown.Not_utf_8 offset), Some first -> offset = first
      | _ -> false)

(* The characters of a line, as strings, in the order of the line. *)
let characters_of line =
  let length = String.length line in
  let rec go offset acc =
    if offset >= length then List.rev acc
    else
      let rec stop next =
        if next < length && Char.code line.[next] land 0xC0 = 0x80 then
          stop (next + 1)
        else next
      in
      let next = stop (offset + 1) in
      go next (String.sub line offset (next - offset) :: acc)
  in
  go 0 []

(* Every span of a structure, each with the character that must stand
   at its start, when one must. *)
let spans (file : Markdown.t) =
  List.concat
    [
      List.concat_map
        (fun (section : Markdown.section) ->
          Option.fold ~none:[]
            ~some:(fun (heading : Markdown.heading) ->
              [ (heading.span, Some "#") ])
            section.heading
          @ Option.fold ~none:[]
              ~some:(fun span -> [ (span, None) ])
              section.first_paragraph
          @ Option.fold ~none:[]
              ~some:(fun span -> [ (span, None) ])
              section.extent)
        (Array.to_list file.sections);
      List.map
        (fun (tag : Markdown.tag) -> (tag.span, Some "@"))
        (Array.to_list file.tags);
      List.map (fun span -> (span, Some "@")) file.unread;
      List.map (fun span -> (span, None)) file.errors;
    ]

let spans_stay_inside_the_text =
  property ~name:"every span lies inside the text, on characters"
    ~print:String.escaped markdown_text (fun text ->
      let lines = Line_index.make (Text_file.with_final_line_feed text) in
      let width line =
        List.length (characters_of (Line_index.content lines line))
      in
      let inside (place : Markdown.position) =
        place.line >= 1
        && place.line <= Line_index.count lines
        && place.column >= 1
        && place.column <= width place.line + 1
      in
      List.for_all
        (fun ((span : Markdown.span), first) ->
          inside span.start && inside span.stop
          && (span.start.line < span.stop.line
             || span.start.line = span.stop.line
                && span.start.column <= span.stop.column)
          &&
          match first with
          | None -> true
          | Some expected ->
              List.nth_opt
                (characters_of (Line_index.content lines span.start.line))
                (span.start.column - 1)
              = Some expected)
        (spans (file text)))

let is_declaration (tag : Markdown.tag) =
  List.mem tag.word [ "req"; "design"; "decision"; "rule" ]
  && match tag.target with Some target -> Slug.is_valid target | None -> false

let structure_holds_together =
  property ~name:"sections, tags, blocks, and extents agree with each other"
    ~print:String.escaped markdown_text (fun text ->
      let file = file text in
      let lines = Line_index.make (Text_file.with_final_line_feed text) in
      let tags = file.tags
      and blocks = file.blocks
      and sections = file.sections in
      let sections_agree =
        Array.for_all Fun.id
          (Array.mapi
             (fun index (section : Markdown.section) ->
               match section.parent with
               | None -> true
               | Some parent ->
                   parent < index && sections.(parent).level < section.level)
             sections)
      in
      let tags_agree =
        Array.for_all Fun.id
          (Array.mapi
             (fun index (tag : Markdown.tag) ->
               let line = tag.span.start.line in
               Option.is_some tag.extent = is_declaration tag
               && tag.section >= 0
               && tag.section < Array.length sections
               && List.mem index blocks.(tag.block).tags
               && (match tag.extent with
                 | Some extent ->
                     tag.owner = Some index && extent.first <= line
                     && line <= extent.last
                     && String.trim (Line_index.content lines extent.last) <> ""
                 | None -> true)
               &&
               match tag.owner with
               | Some owner -> (
                   match tags.(owner).extent with
                   | Some extent -> extent.first <= line && line <= extent.last
                   | None -> false)
               | None -> true)
             tags)
      in
      let blocks_agree =
        Array.for_all
          (fun (block : Markdown.block) ->
            block.tags <> []
            && List.sort_uniq Int.compare block.tags = block.tags)
          blocks
        && List.concat_map
             (fun (block : Markdown.block) -> block.tags)
             (Array.to_list blocks)
           = List.init (Array.length tags) Fun.id
      in
      sections_agree && tags_agree && blocks_agree)

(* A markdown file built from parts, so that a test can make an edit
   that the extent hash must not see. *)
type part =
  | Declaration of {
      word : string;
      slug : string;
      rev : int option;
      desc : string;
    }
  | Citation of {
      word : string;
      target : string;
      rev : int option;
      desc : string;
    }
  | Prose of string

type item = { item_lines : part list; sub_items : item list }

type section = {
  level : int;
  title : string;
  first : part list;
  items : item list;
  later : string list;
}

(* The edits that keep every extent hash and every block hash: a bump
   of each declaration, a re-pin of each citation, a rename of each
   declaration, spaces and tabs at the end of each line, CRLF line
   endings, an ack line after each declaration, and blank lines at the
   end of the file. *)
type edit = {
  bump : int;
  repin : int;
  suffix : string;
  trailing : string;
  ending : string;
  acks : bool;
  blank_end : int;
}

let no_edit =
  {
    bump = 0;
    repin = 0;
    suffix = "";
    trailing = "";
    ending = "\n";
    acks = false;
    blank_end = 0;
  }

let edits =
  [
    ("a bump", { no_edit with bump = 3 });
    ("a re-pin", { no_edit with repin = 2 });
    ("a rename", { no_edit with suffix = "-renamed" });
    ("spaces and tabs at the ends of lines", { no_edit with trailing = " \t " });
    ("CRLF line endings", { no_edit with ending = "\r\n" });
    ("ack lines", { no_edit with acks = true });
    ("blank lines at the end", { no_edit with blank_end = 3 });
  ]

let render_part edit = function
  | Declaration { word; slug; rev; desc } ->
      [
        Printf.sprintf "@%s %s%s%s%s" word slug edit.suffix
          (Option.fold ~none:""
             ~some:(fun rev -> Printf.sprintf " v%d" (rev + edit.bump))
             rev)
          (if desc = "" then "" else " " ^ desc);
      ]
      @ if edit.acks then [ "@ack disendorsed t 0123abcd" ] else []
  | Citation { word; target; rev; desc } ->
      [
        Printf.sprintf "@%s %s%s%s" word target
          (Option.fold ~none:""
             ~some:(fun rev -> Printf.sprintf " v%d" (rev + edit.repin))
             rev)
          (if desc = "" then "" else " " ^ desc);
      ]
  | Prose text -> [ text ]

let rec render_item edit indent item =
  let lines = List.concat_map (render_part edit) item.item_lines in
  (match lines with
    | first :: rest ->
        (indent ^ "- " ^ first)
        :: List.map (fun line -> indent ^ "  " ^ line) rest
    | [] -> [ indent ^ "- plain" ])
  @ List.concat_map (render_item edit (indent ^ "  ")) item.sub_items

let render edit sections =
  let section_lines section =
    (if section.level = 0 then []
     else [ String.make section.level '#' ^ " " ^ section.title ])
    @ List.concat_map (render_part edit) section.first
    @ [ "" ]
    @ (if section.items = [] then []
       else List.concat_map (render_item edit "") section.items @ [ "" ])
    @ List.concat_map (fun text -> [ text; "" ]) section.later
  in
  let lines =
    List.concat_map section_lines sections
    @ List.init edit.blank_end (fun _ -> "")
  in
  String.concat ""
    (List.map (fun line -> line ^ edit.trailing ^ edit.ending) lines)

let part =
  let rev = Gen.option (Gen.int_range 1 4) in
  let desc = Gen.oneof_list [ ""; "Why."; "Two words" ] in
  Gen.oneof_weighted
    [
      ( 2,
        Gen.map3
          (fun (word, slug) rev desc -> Declaration { word; slug; rev; desc })
          (Gen.pair
             (Gen.oneof_list [ "req"; "design"; "decision" ])
             (Gen.oneof_list [ "a"; "b-c"; "d.e" ]))
          rev desc );
      ( 3,
        Gen.map3
          (fun (word, target) rev desc -> Citation { word; target; rev; desc })
          (Gen.pair
             (Gen.oneof_list
                [ "cites"; "satisfies"; "refines"; "supersedes"; "verifies" ])
             (Gen.oneof_list [ "t"; "gh/1"; "u-v" ]))
          rev desc );
      ( 2,
        Gen.map
          (fun text -> Prose text)
          (Gen.oneof_list [ "Text."; "More words here"; "a *b* c" ]) );
    ]

let parts = Gen.list_size (Gen.int_range 0 3) part

let item =
  Gen.map2
    (fun item_lines sub_items -> { item_lines; sub_items })
    parts
    (Gen.list_size (Gen.int_range 0 1)
       (Gen.map (fun item_lines -> { item_lines; sub_items = [] }) parts))

let sections =
  let section level =
    Gen.map3
      (fun title (first, items) later -> { level; title; first; items; later })
      (Gen.oneof_list [ "Alpha"; "Beta gamma"; "x" ])
      (Gen.pair parts (Gen.list_size (Gen.int_range 0 2) item))
      (Gen.list_size (Gen.int_range 0 1)
         (Gen.oneof_list [ "Later text."; "End." ]))
  in
  Gen.bind (Gen.int_range 0 3) (fun count ->
      Gen.map2
        (fun first rest -> first :: rest)
        (Gen.bind (Gen.int_range 0 2) section)
        (Gen.list_size (Gen.return count)
           (Gen.bind (Gen.int_range 1 3) section)))

let hashes text =
  let file = file text in
  ( List.filter_map
      (fun (tag : Markdown.tag) ->
        Option.map (fun (extent : Markdown.extent) -> extent.hash) tag.extent)
      (Array.to_list file.tags),
    List.map
      (fun (block : Markdown.block) -> block.hash)
      (Array.to_list file.blocks) )

let edits_keep_the_hashes =
  property ~count:100
    ~name:"the edits that the extent hash ignores keep every hash"
    ~print:(fun (sections, (name, _)) ->
      name ^ " on:\n" ^ render no_edit sections)
    (Gen.pair sections (Gen.oneof_list edits))
    (fun (sections, (_, edit)) ->
      hashes (render no_edit sections) = hashes (render edit sections))

let prose_change_changes_the_extent_hash () =
  let before = file "# A\n@req a v1\nOne.\n"
  and after = file "# A\n@req a v1\nTwo.\n" in
  Alcotest.(check bool)
    "the hashes differ" false
    (before.tags.(0).extent = after.tags.(0).extent)

let tests =
  [
    Alcotest.test_case "a read after close is refused" `Quick
      read_after_close_is_refused;
    Alcotest.test_case "create on a closed engine is refused" `Quick
      create_on_a_closed_engine_is_refused;
    Alcotest.test_case "a text that is not UTF-8 gives its offset" `Quick
      text_that_is_not_utf_8_gives_its_offset;
    Alcotest.test_case "headings give text, slug, and name" `Quick
      headings_give_text_slug_and_name;
    Alcotest.test_case "block quotes and list items open no section" `Quick
      containers_open_no_section;
    Alcotest.test_case "the first block must be a paragraph" `Quick
      first_block_must_be_a_paragraph;
    Alcotest.test_case "front matter is no block" `Quick
      front_matter_is_no_block;
    Alcotest.test_case "YAML front matter is no block" `Quick
      yaml_front_matter_is_no_block;
    Alcotest.test_case "a section of declared items alone has no extent" `Quick
      section_of_declared_items_alone_has_no_extent;
    Alcotest.test_case "list items drop their markers" `Quick
      list_items_drop_their_markers;
    Alcotest.test_case "places count characters" `Quick places_count_characters;
    Alcotest.test_case "a tag line after prose starts a block" `Quick
      tag_line_after_prose_starts_a_block;
    Alcotest.test_case "two declarations split one node" `Quick
      two_declarations_split_one_node;
    Alcotest.test_case "extent hashes follow the rules" `Quick
      extent_hashes_follow_the_rules;
    Alcotest.test_case "the hash normalizes each line" `Quick
      hash_normalizes_each_line;
    Alcotest.test_case "the block of an ack alone hashes an empty text" `Quick
      block_of_an_ack_alone_hashes_an_empty_text;
    Alcotest.test_case "nested declarations leave the extent" `Quick
      nested_declarations_leave_the_extent;
    Alcotest.test_case "nested extent hashes skip the holes" `Quick
      nested_extent_hashes_skip_the_holes;
    Alcotest.test_case "a declaration needs a slug" `Quick
      declaration_needs_a_slug;
    Alcotest.test_case "an ERROR node gives its span" `Quick
      error_node_gives_its_span;
    Alcotest.test_case "a MISSING node gives an empty span" `Quick
      missing_node_gives_an_empty_span;
    Alcotest.test_case "a change of prose changes the extent hash" `Quick
      prose_change_changes_the_extent_hash;
    read_answers_any_bytes;
    spans_stay_inside_the_text;
    structure_holds_together;
    edits_keep_the_hashes;
  ]
