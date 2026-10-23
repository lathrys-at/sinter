(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

type position = Line_index.position = { line : int; column : int }
type span = { start : position; stop : position }

type reader = {
  language : Sinter_bridge.Language.t;
  query : Sinter_bridge.Query.t;
}

type load_error =
  | Grammar of Sinter_bridge.Language.error
  | Query of Sinter_bridge.Query.error

let create engine =
  match
    Sinter_bridge.Language.load engine ~name:"markdown"
      ~wasm:Markdown_pack.grammar
  with
  | Error error -> Error (Grammar error)
  | Ok language -> (
      match Sinter_bridge.Query.compile language Markdown_pack.query with
      | Ok query -> Ok { language; query }
      | Error error ->
          Fun.protect
            ~finally:(fun () -> Sinter_bridge.Language.close language)
            (fun () -> Error (Query error)))

let close reader =
  Fun.protect
    ~finally:(fun () -> Sinter_bridge.Language.close reader.language)
    (fun () -> Sinter_bridge.Query.close reader.query)

type heading = { text : string; slug : string; name : string; span : span }

type section = {
  level : int;
  heading : heading option;
  parent : int option;
  first_paragraph : span option;
  extent : span option;
}

type node = Section_paragraph | Item_paragraph
type extent = { first : int; last : int; hash : string }

type tag = {
  span : span;
  word : string;
  rest : string;
  target : string option;
  rev : int option;
  desc : string;
  block : int;
  node : node;
  section : int;
  owner : int option;
  extent : extent option;
}

type block = { tags : int list; prose : string list; hash : string }

type t = {
  sections : section array;
  tags : tag array;
  blocks : block array;
  unread : span list;
  errors : span list;
}

type error = Not_utf_8 of int | No_tree of Sinter_bridge.Tree.error

(* {1 The tree of blocks} *)

type kind = Section | Heading | Paragraph | Item | Other

(* A captured node. [stop] is exclusive. [children] is built once, while
   the nodes nest, and not changed after. *)
type tree = {
  kind : kind;
  start : int;
  stop : int;
  mutable children : tree list;
}

let kind_of = function
  | "section" -> Section
  | "atx_heading" -> Heading
  | "paragraph" -> Paragraph
  | "list_item" -> Item
  | _ -> Other

(* The query gives the nodes in the order of a depth-first walk, so of
   two nodes with one range the holder comes first, and the stable sort
   keeps that order. *)
let order a b =
  match Int.compare a.start b.start with
  | 0 -> Int.compare b.stop a.stop
  | other -> other

let contains outer inner =
  outer.start <= inner.start && inner.stop <= outer.stop

(* The nodes as a forest: each node becomes a child of the smallest
   earlier node that contains it. *)
let nest nodes =
  let place (stack, roots) node =
    let rec pop = function
      | top :: rest when not (contains top node) -> pop rest
      | stack -> stack
    in
    match pop stack with
    | top :: _ as stack ->
        top.children <- node :: top.children;
        (node :: stack, roots)
    | [] -> ([ node ], node :: roots)
  in
  let _, roots = List.fold_left place ([], []) (List.stable_sort order nodes) in
  let rec finish node =
    node.children <- List.rev node.children;
    List.iter finish node.children
  in
  let roots = List.rev roots in
  List.iter finish roots;
  roots

(* The children of a list item, with each section inside it replaced by
   its children: a heading in a list item opens no section. *)
let rec flatten children =
  List.concat_map
    (fun child ->
      match child.kind with Section -> flatten child.children | _ -> [ child ])
    children

(* {1 Lines and spans} *)

let is_blank_byte = function ' ' | '\t' -> true | _ -> false
let is_space_byte = function ' ' | '\t' | '\r' | '\n' -> true | _ -> false

let is_blank_line lines line =
  String.for_all is_blank_byte (Line_index.content lines line)

let strip_end text =
  let rec stop offset =
    if offset > 0 && is_blank_byte text.[offset - 1] then stop (offset - 1)
    else offset
  in
  String.sub text 0 (stop (String.length text))

let strip text =
  let length = String.length text in
  let rec start offset =
    if offset < length && is_blank_byte text.[offset] then start (offset + 1)
    else offset
  in
  let first = start 0 in
  strip_end (String.sub text first (length - first))

(* The last offset from [start] to [stop - 1] whose byte [skip]
   refuses, or [None]. *)
let last_kept skip text start stop =
  let rec back offset =
    if offset < start then None
    else if skip text.[offset] then back (offset - 1)
    else Some offset
  in
  back (stop - 1)

(* The first offset from [start] whose byte [skip] refuses. A byte that
   [skip] refuses must come at or after [start]. *)
let rec first_kept skip text start =
  if skip text.[start] then first_kept skip text (start + 1) else start

(* The span of the bytes from [start] to [stop], without the spaces,
   tabs, and line endings at both ends. A range of such bytes alone gives
   a span of no character at [start]. *)
let trimmed_span lines start stop =
  let text = Line_index.text lines in
  match last_kept is_space_byte text start stop with
  | Some last ->
      {
        start = Line_index.position lines (first_kept is_space_byte text start);
        stop = Line_index.after lines (last + 1);
      }
  | None ->
      let place = Line_index.position lines start in
      { start = place; stop = place }

(* The last line that holds a byte of the node other than a space or a
   tab: the line of its last line feed when the node ends with the
   indentation of the next line. *)
let last_line lines node =
  match
    last_kept is_blank_byte (Line_index.text lines) node.start node.stop
  with
  | Some offset -> Line_index.line_of lines offset
  | None -> Line_index.line_of lines node.start

(* The last line of the node that holds a character other than a space
   or a tab. *)
let content_last_line lines node =
  match
    last_kept is_space_byte (Line_index.text lines) node.start node.stop
  with
  | Some offset -> Line_index.line_of lines offset
  | None -> Line_index.line_of lines node.start

(* {1 Headings} *)

(* The offset of the first [#] of the line [content] of an ATX heading,
   its level, and its heading text. In the line without its opening [#]
   and the spaces and tabs at both ends, a closing sequence is the run of
   [#] at the end: the whole text, or a run after a space or a tab. *)
let heading_text content =
  let length = String.length content in
  let rec skip keep offset =
    if offset < length && keep content.[offset] then skip keep (offset + 1)
    else offset
  in
  let marks = skip is_blank_byte 0 in
  let after = skip (fun byte -> byte = '#') marks in
  let text = strip (String.sub content after (length - after)) in
  let rec run offset =
    if offset > 0 && text.[offset - 1] = '#' then run (offset - 1) else offset
  in
  let run = run (String.length text) in
  (* The text starts with a byte that is not a space or a tab, so the
     search stops before offset 0. *)
  let rec blanks offset =
    if is_blank_byte text.[offset - 1] then blanks (offset - 1) else offset
  in
  let heading =
    if run = 0 then ""
    else
      let stop = blanks run in
      if stop < run then String.sub text 0 stop else text
  in
  (marks, after - marks, heading)

module Names = Map.Make (String)

(* The numbering of the anchors of GitHub: the first heading of a slug
   keeps it; a later one counts on from the last number that its slug
   took, past each name that an earlier heading took. [taken] maps each
   name to the last number of its slug; it holds [slug] whenever it
   holds [name], because the first [name] is [slug]. *)
let numberer () =
  let taken = ref Names.empty in
  fun slug ->
    let rec find name =
      if Names.mem name !taken then (
        let count = Names.find slug !taken + 1 in
        taken := Names.add slug count !taken;
        find (slug ^ "-" ^ string_of_int count))
      else name
    in
    let name = find slug in
    taken := Names.add name 0 !taken;
    name

(* {1 The walk} *)

(* A section or a list item: the nodes that hold a tag-bearing
   paragraph and that an extent covers. [parent] is the container that
   holds it. *)
type container = { first_line : int; last_line : int; parent : int option }

type paragraph = {
  container : int;
  in_section : int;
  bearer : node;
  paragraph : tree;
}

type walk = {
  lines : Line_index.t;
  containers : container Dynarray.t;
  sections : (section * int) Dynarray.t;
      (* each section, without its extent, and its container *)
  paragraphs : paragraph Dynarray.t;
  unread : span Dynarray.t;
  number : string -> string;
}

let add array value =
  Dynarray.add_last array value;
  Dynarray.length array - 1

let tag_span lines start line =
  {
    start = Line_index.position lines start;
    stop = Line_index.after lines (Line_index.content_end lines line);
  }

(* A paragraph gives an unread tag when its first character is [@]. The
   line feed of its first line stops the search. *)
let check_unread walk paragraph =
  let text = Line_index.text walk.lines in
  let at = first_kept is_blank_byte text paragraph.start in
  if text.[at] = '@' then
    Dynarray.add_last walk.unread
      (tag_span walk.lines at (Line_index.line_of walk.lines at))

(* The blocks of a section or a list item: the first paragraph is
   tag-bearing, and every other paragraph is checked for an unread tag.
*)
let rec walk_blocks walk ~container ~in_section ~bearer blocks =
  (match blocks with
  | ({ kind = Paragraph; _ } as paragraph) :: _ ->
      Dynarray.add_last walk.paragraphs
        { container; in_section; bearer; paragraph }
  | _ -> ());
  List.iteri
    (fun index block ->
      match block.kind with
      | Paragraph -> if index > 0 then check_unread walk block
      | Item -> walk_item walk ~parent:container ~in_section block
      | Section ->
          walk_section walk ~parent:(Some in_section) ~holder:(Some container)
            block
      | Heading | Other -> ())
    blocks

and walk_item walk ~parent ~in_section item =
  let container =
    add walk.containers
      {
        first_line = Line_index.line_of walk.lines item.start;
        last_line = last_line walk.lines item;
        parent = Some parent;
      }
  in
  walk_blocks walk ~container ~in_section ~bearer:Item_paragraph
    (flatten item.children)

and walk_section walk ~parent ~holder section =
  let lines = walk.lines in
  let level, heading, blocks =
    match section.children with
    | ({ kind = Heading; _ } as node) :: blocks ->
        let line = Line_index.line_of lines node.start in
        let content = Line_index.content lines line in
        let marks, level, text = heading_text content in
        let slug = Slug.of_heading text in
        let first = Line_index.first lines line in
        ( level,
          Some
            {
              text;
              slug;
              name = walk.number slug;
              span = tag_span lines (first + marks) line;
            },
          blocks )
    | blocks -> (0, None, blocks)
  in
  let container =
    add walk.containers
      {
        first_line =
          (if level = 0 then 1 else Line_index.line_of lines section.start);
        last_line = last_line lines section;
        parent = holder;
      }
  in
  let first_paragraph =
    match blocks with
    | { kind = Paragraph; start; stop; _ } :: _ ->
        Some (trimmed_span lines start stop)
    | _ -> None
  in
  let in_section =
    add walk.sections
      ({ level; heading; parent; first_paragraph; extent = None }, container)
  in
  walk_blocks walk ~container ~in_section ~bearer:Section_paragraph blocks

(* {1 Tag lines and blocks} *)

(* A tag line before the indices of the result are known. [rest_start]
   is the offset of [rest] in the text. *)
type pending = {
  line : int;
  at : int;
  tag_line : Tag_line.t;
  parts : Tag_line.parts;
  rest_start : int;
  of_paragraph : paragraph;
  in_block : int;
  declares : bool;
}

type pending_block = {
  members : int list;
  prose_lines : int list;
  first_block_line : int;
  last_block_line : int;
}

let declaration_words = [ "req"; "design"; "decision"; "rule" ]

let citation_words =
  [ "satisfies"; "verifies"; "refines"; "cites"; "supersedes" ]

let declares (tag_line : Tag_line.t) (parts : Tag_line.parts) =
  List.mem tag_line.word declaration_words
  &&
  match parts.target with
  | Some target -> Slug.is_valid target
  | None -> false

(* The tag lines and the blocks of one tag-bearing paragraph, added to
   [tags] and [blocks]. *)
let read_paragraph lines tags blocks paragraph =
  let node = paragraph.paragraph in
  let text = Line_index.text lines in
  let first = Line_index.line_of lines node.start in
  let last = content_last_line lines node in
  let current = ref None in
  let close () =
    match !current with
    | Some block ->
        ignore
          (add blocks
             {
               block with
               members = List.rev block.members;
               prose_lines = List.rev block.prose_lines;
             });
        current := None
    | None -> ()
  in
  for line = first to last do
    let start =
      if line = first then node.start else Line_index.first lines line
    in
    let stop = max start (Line_index.content_end lines line) in
    match Tag_line.read (String.sub text start (stop - start)) with
    | Some (at, tag_line) ->
        (* The lines of a paragraph follow each other, so a block with no
           prose yet ends at the line before. *)
        (match !current with
        | Some { prose_lines = []; _ } -> ()
        | Some _ | None ->
            close ();
            current :=
              Some
                {
                  members = [];
                  prose_lines = [];
                  first_block_line = line;
                  last_block_line = line;
                });
        let in_block = Dynarray.length blocks in
        let parts = Tag_line.parts tag_line.rest in
        let index =
          add tags
            {
              line;
              at = start + at;
              tag_line;
              parts;
              rest_start = start + at + 1 + String.length tag_line.word;
              of_paragraph = paragraph;
              in_block;
              declares = declares tag_line parts;
            }
        in
        current :=
          Option.map
            (fun block ->
              {
                block with
                members = index :: block.members;
                last_block_line = line;
              })
            !current
    | None ->
        current :=
          Option.map
            (fun block ->
              {
                block with
                prose_lines = line :: block.prose_lines;
                last_block_line = line;
              })
            !current
  done;
  close ()

(* {1 Extents} *)

(* The lines from [first] to [last], without the lines of the [holes],
   and without the blank lines at the end. *)
let extent_lines lines ~holes first last =
  let all =
    List.filter
      (fun line ->
        not (List.exists (fun (low, high) -> low <= line && line <= high) holes))
      (List.init (last - first + 1) (fun offset -> first + offset))
  in
  let rec drop_blank = function
    | line :: rest when is_blank_line lines line -> drop_blank rest
    | kept -> kept
  in
  List.rev (drop_blank (List.rev all))

(* The hash of the lines [included], normalized by the rule of the
   extent hash. [at line] is the tag line at [line] and its index, and
   [own index] says whether the tag line [index] is a declaration that
   the hash replaces with its inline description. *)
let hash_lines lines ~at ~own included =
  let normal line =
    match at line with
    | Some (_, pending) when pending.tag_line.word = "ack" -> None
    | Some (index, pending) when own index ->
        Some (strip pending.parts.description)
    | Some (_, pending) when List.mem pending.tag_line.word citation_words ->
        let start = Line_index.first lines line in
        let prefix =
          String.sub (Line_index.text lines) start (pending.rest_start - start)
        in
        Some
          (strip_end (prefix ^ Tag_line.without_revision pending.tag_line.rest))
    | _ -> Some (strip_end (Line_index.content lines line))
  in
  Sha256.hex (String.concat "\n" (List.filter_map normal included) ^ "\n")

(* {1 Reading} *)

let parse_errors lines (report : Sinter_bridge.Tree.report) =
  let span_of (node : Sinter_bridge.Tree.node) =
    trimmed_span lines node.range.start_byte node.range.end_byte
  in
  match (report.errors, report.lowest) with
  | [], Some node -> [ span_of node ]
  | errors, _ -> List.map (fun (_, node) -> span_of node) errors

let structure lines captures =
  let nodes =
    List.map
      (fun (capture : Sinter_bridge.Query.capture) ->
        {
          kind = kind_of capture.node_type;
          start = capture.range.start_byte;
          stop = capture.range.end_byte;
          children = [];
        })
      captures
  in
  let walk =
    {
      lines;
      containers = Dynarray.create ();
      sections = Dynarray.create ();
      paragraphs = Dynarray.create ();
      unread = Dynarray.create ();
      number = numberer ();
    }
  in
  List.iter
    (fun root ->
      match root.kind with
      | Section -> walk_section walk ~parent:None ~holder:None root
      | Heading | Paragraph | Item | Other -> ())
    (nest nodes);
  walk

let range_of = function
  | low :: _ as included ->
      Some (low, List.nth included (List.length included - 1))
  | [] -> None

(* The runs of consecutive declarations of one paragraph, in the order
   of the file. *)
let by_paragraph declarations =
  let rec group = function
    | [] -> []
    | ((_, first) as head) :: rest ->
        let same, others =
          let rec take same = function
            | ((_, tag) as next) :: rest
              when tag.of_paragraph.paragraph == first.of_paragraph.paragraph ->
                take (next :: same) rest
            | rest -> (List.rev same, rest)
          in
          take [ head ] rest
        in
        same :: group others
  in
  group declarations

let assemble lines walk errors =
  let pending = Dynarray.create () and pending_blocks = Dynarray.create () in
  Dynarray.iter (read_paragraph lines pending pending_blocks) walk.paragraphs;
  let pending = Dynarray.to_array pending in
  let containers = Dynarray.to_array walk.containers in
  let declared = Array.make (Array.length containers) false in
  Array.iter
    (fun tag ->
      if tag.declares then declared.(tag.of_paragraph.container) <- true)
    pending;
  (* The holes of a container: the lines of each declared container that
     it holds, at any depth. *)
  let holes = Array.make (Array.length containers) [] in
  Array.iteri
    (fun index (container : container) ->
      if declared.(index) then
        let rec up = function
          | Some parent ->
              holes.(parent) <-
                (container.first_line, container.last_line) :: holes.(parent);
              up containers.(parent).parent
          | None -> ()
        in
        up container.parent)
    containers;
  let count = Line_index.count lines in
  let at_line = Array.make (count + 1) None in
  Array.iteri (fun index tag -> at_line.(tag.line) <- Some (index, tag)) pending;
  let at line = at_line.(line) in
  let owners = Array.make (count + 1) None in
  let extents = Array.make (Array.length pending) None in
  (* The first declaration of a paragraph claims its container from its
     first line; each later one claims from its own tag line. Each claim
     ends at the line before the next declaration, and the last at the
     end of the container. *)
  let claim declarations =
    let rec split start = function
      | [] -> ()
      | (index, tag) :: later -> (
          let container = tag.of_paragraph.container in
          let stop =
            match later with
            | (_, next) :: _ -> next.line - 1
            | [] -> containers.(container).last_line
          in
          let included =
            extent_lines lines ~holes:holes.(container) start stop
          in
          List.iter (fun line -> owners.(line) <- Some index) included;
          (match range_of included with
          | Some (first, last) ->
              let hash =
                hash_lines lines ~at ~own:(fun other -> other = index) included
              in
              extents.(index) <- Some { first; last; hash }
          | None -> ());
          match later with (_, next) :: _ -> split next.line later | [] -> ())
    in
    match declarations with
    | (_, tag) :: _ ->
        split containers.(tag.of_paragraph.container).first_line declarations
    | [] -> ()
  in
  pending |> Array.to_list
  |> List.mapi (fun index tag -> (index, tag))
  |> List.filter (fun (_, tag) -> tag.declares)
  |> by_paragraph |> List.iter claim;
  let blocks =
    Array.map
      (fun block ->
        let own index = pending.(index).declares in
        {
          tags = block.members;
          prose = List.map (Line_index.content lines) block.prose_lines;
          hash =
            hash_lines lines ~at ~own
              (List.init
                 (block.last_block_line - block.first_block_line + 1)
                 (fun offset -> block.first_block_line + offset));
        })
      (Dynarray.to_array pending_blocks)
  in
  let tags =
    Array.mapi
      (fun index tag ->
        {
          span = tag_span lines tag.at tag.line;
          word = tag.tag_line.word;
          rest = tag.tag_line.rest;
          target = tag.parts.target;
          rev = tag.parts.revision;
          desc = tag.parts.description;
          block = tag.in_block;
          node = tag.of_paragraph.bearer;
          section = tag.of_paragraph.in_section;
          owner = owners.(tag.line);
          extent = extents.(index);
        })
      pending
  in
  let sections =
    Array.map
      (fun ((section : section), container_index) ->
        let container = containers.(container_index) in
        let extent =
          extent_lines lines ~holes:holes.(container_index) container.first_line
            container.last_line
          |> range_of
          |> Option.map (fun (first, last) ->
              {
                start = { line = first; column = 1 };
                stop =
                  Line_index.after lines (Line_index.content_end lines last);
              })
        in
        { section with extent })
      (Dynarray.to_array walk.sections)
  in
  { sections; tags; blocks; unread = Dynarray.to_list walk.unread; errors }

let read reader content =
  match Sinter_bridge.Utf_8.first_invalid content with
  | Some offset -> Error (Not_utf_8 offset)
  | None -> (
      let text = Text_file.with_final_line_feed content in
      match Sinter_bridge.Tree.parse reader.language text with
      | Error error -> Error (No_tree error)
      | Ok tree ->
          Fun.protect
            ~finally:(fun () -> Sinter_bridge.Tree.close tree)
            (fun () ->
              let lines = Line_index.make text in
              let captures =
                (* The query and the tree come from the one grammar of the
                   reader, so the run fails with no Language_mismatch. *)
                match Sinter_bridge.Query.run reader.query tree with
                | Ok captures -> captures
                | Error error ->
                    invalid_arg (Sinter_bridge.Query.run_message error)
              in
              let errors =
                parse_errors lines (Sinter_bridge.Tree.errors tree)
              in
              Ok (assemble lines (structure lines captures) errors)))
