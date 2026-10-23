(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

open Sinter_core

(* Dune runs the test in the build copy of test/, so the path below is
   relative to that directory. *)
let grammar = "fixtures/tree-sitter-json/tree-sitter-json.wasm"

let contains needle haystack =
  let n = String.length needle and h = String.length haystack in
  let rec search index =
    index + n <= h
    && (String.equal (String.sub haystack index n) needle || search (index + 1))
  in
  search 0

let property ?(count = 500) ~name ~print generator check =
  QCheck_alcotest.to_alcotest ~speed_level:`Quick
    (QCheck2.Test.make ~count ~name ~print generator check)

let reads_the_grammar_name_from_the_module () =
  let wasm = In_channel.with_open_bin grammar In_channel.input_all in
  Alcotest.(check (option string))
    "the module of the fixture names the grammar json" (Some "json")
    (Grammar_name.of_wasm wasm);
  Alcotest.(check (option string))
    "a file that is not wasm has no name" None
    (Grammar_name.of_wasm "not a wasm module");
  Alcotest.(check (option string))
    "a header without sections has no name" None
    (Grammar_name.of_wasm "\000asm\001\000\000\000")

(* A wasm module of a header and one export section. The section
   holds one export of the given name, of kind 0 and index 0. Every
   count and every length in the format is one byte here, because the
   test keeps them below 128. *)
let module_that_exports name =
  let section =
    Printf.sprintf "\001%c%s\000\000" (Char.chr (String.length name)) name
  in
  Printf.sprintf "\000asm\001\000\000\000\007%c%s"
    (Char.chr (String.length section))
    section

let gives_no_name_that_holds_a_nul_byte () =
  Alcotest.(check (option string))
    "a name without a NUL byte is a name" (Some "json")
    (Grammar_name.of_wasm (module_that_exports "tree_sitter_json"));
  Alcotest.(check (option string))
    "a name with a NUL byte is no name" None
    (Grammar_name.of_wasm (module_that_exports "tree_sitter_js\000n"))

(* A module of a header and one export section whose body is [body].
   The size of the section is one byte, so [body] stays below 128
   bytes. *)
let module_with_export_section body =
  Printf.sprintf "\000asm\001\000\000\000\007%c%s"
    (Char.chr (String.length body))
    body

(* Each module below fails the reader in one place. The reader gives
   no name for every one of them, and it raises on none of them. *)
let gives_no_name_for_a_module_the_reader_cannot_follow () =
  let check what body =
    Alcotest.(check (option string))
      what None
      (Grammar_name.of_wasm (module_with_export_section body))
  in
  check "a number that runs off the end of the module" "\128";
  check "a number that runs past 28 bits of shift" "\128\128\128\128\128\001";
  check "an export name that runs past the end of the module" "\001\010ab";
  check "an export list with no export at all" "\000";
  check "an export list whose one export is not a grammar" "\001\003foo\000\000";
  check "an export whose kind byte is missing" "\001\003foo"

(* The reader walks the section list of a module, and then the export
   list of its export section. Each module below takes it down a road
   that neither the fixture nor a module of one export goes: a section
   whose size needs two LEB128 bytes, a list of three exports with the
   one of the grammar last, and an export index written in five LEB128
   bytes. *)
let reads_the_name_of_a_module_of_any_shape () =
  let check what shape =
    Alcotest.(check (option string))
      what (Some "json")
      (Grammar_name.of_wasm (Generators.wasm_module shape ~name:"json"))
  in
  check "a section whose size needs two bytes" Generators.Long_custom_section;
  check "three exports, and the one of the grammar last"
    Generators.Three_exports;
  check "an export index of five bytes" Generators.Long_export_index

(* The export section states how many exports it holds, and its size
   states where it ends. The two can disagree, and the reader holds to
   both: it reads no export past the count, and none past the end of
   the section. In each module below the export of the grammar is
   there, and the reader must not reach it. *)
let gives_no_name_when_the_export_count_disagrees () =
  let check what shape =
    Alcotest.(check (option string))
      what None
      (Grammar_name.of_wasm (Generators.wasm_module shape ~name:"json"))
  in
  check "a section that declares two exports and holds three"
    Generators.Too_few_exports_declared;
  check
    "a section that declares three exports and holds two, and the export of \
     the grammar follows it"
    Generators.Too_many_exports_declared

(* A section whose body runs past the end of the module is no section.
   The reader gives no name for such a module, even though the bytes
   of the export are all there. *)
let gives_no_name_for_a_module_cut_in_a_section () =
  Alcotest.(check (option string))
    "a module cut in the middle of its export section" None
    (Grammar_name.of_wasm
       (Generators.wasm_module Generators.Cut_in_a_section ~name:"json"))

(* The reader needs one byte after an export name, for the kind of the
   export. The module below stops at the end of that name, so the byte
   is outside the export section, and the reader gives no name. A
   custom section of eight bytes follows, so that the name ends inside
   the module and not at the end of it. *)
let gives_no_name_for_an_export_name_that_ends_at_its_section () =
  let export_name = "tree_sitter_json" in
  let body =
    Printf.sprintf "\001%c%s" (Char.chr (String.length export_name)) export_name
  in
  let custom = "\000\008\004name\255\255\255" in
  Alcotest.(check (option string))
    "an export name that ends at the end of its section is no name" None
    (Grammar_name.of_wasm (module_with_export_section body ^ custom))

(* A reader that took bytes of eight or more for a module would walk
   the section list of the bytes below and find the export of a
   grammar in it. The first four bytes are not the magic number of a
   module, so the reader gives no name. *)
let gives_no_name_for_bytes_that_are_not_a_module () =
  let wasm = Generators.wasm_module Generators.One_export ~name:"json" in
  let bytes = Bytes.of_string wasm in
  Bytes.set bytes 3 'X';
  Alcotest.(check (option string))
    "the same bytes under the magic number of a module name the grammar"
    (Some "json")
    (Grammar_name.of_wasm wasm);
  Alcotest.(check (option string))
    "the bytes without that magic number name nothing" None
    (Grammar_name.of_wasm (Bytes.to_string bytes))

(* A file whose base name is the prefix and nothing else. The prefix
   comes off only when the name is longer than it, so here it stays
   and the grammar name is the whole base name. *)
let keeps_a_base_name_that_is_the_prefix_alone () =
  Alcotest.(check string)
    "the base name tree-sitter- gives the grammar name tree_sitter_"
    "tree_sitter_"
    (Grammar_name.of_path "packs/tree-sitter-.wasm")

let names_the_grammar () =
  let check expected path =
    Alcotest.(check string) path expected (Grammar_name.of_path path)
  in
  check "json" "test/fixtures/tree-sitter-json/tree-sitter-json.wasm";
  check "json" "tree-sitter-json.wasm";
  check "json" "json.wasm";
  check "type_script" "packs/tree-sitter-type-script.wasm"

(* The two properties below state that the function is total: it
   answers for every value of its argument type, and raises nothing.
   Each one adds the cheapest clause that can fail, so that neither
   passes because the call did nothing. *)
let the_reader_of_a_module_answers_for_any_bytes wasm =
  match Grammar_name.of_wasm wasm with
  | None -> true
  | Some found -> contains ("tree_sitter_" ^ found) wasm

(* The bridge refuses a grammar name that holds a NUL byte, so the
   reader gives no such name and the caller falls back to the file
   name. *)
let a_name_from_a_module_can_name_a_grammar wasm =
  match Grammar_name.of_wasm wasm with
  | None -> true
  | Some name -> not (String.contains name '\000')

let the_reader_of_a_module_finds_a_generated_export (name, wasm) =
  Option.equal String.equal (Grammar_name.of_wasm wasm) (Some name)

(* A grammar name is the base name of the path without its extension,
   so it is never longer than that base name. It can still hold a
   slash: the base name of "/" is "/". *)
let a_grammar_name_comes_back_for_any_file_name path =
  String.length (Grammar_name.of_path path)
  <= String.length (Filename.basename path)

let a_grammar_name_holds_no_hyphen path =
  not (String.contains (Grammar_name.of_path path) '-')

let a_grammar_name_drops_the_prefix_and_the_extension name =
  String.equal
    (Grammar_name.of_path ("packs/tree-sitter-" ^ name ^ ".wasm"))
    name

let tests =
  [
    Alcotest.test_case "reads the grammar name from the module" `Quick
      reads_the_grammar_name_from_the_module;
    Alcotest.test_case "gives no name that holds a NUL byte" `Quick
      gives_no_name_that_holds_a_nul_byte;
    Alcotest.test_case "gives no name for a module the reader cannot follow"
      `Quick gives_no_name_for_a_module_the_reader_cannot_follow;
    Alcotest.test_case "reads the name of a module of any shape" `Quick
      reads_the_name_of_a_module_of_any_shape;
    Alcotest.test_case "gives no name when the export count disagrees" `Quick
      gives_no_name_when_the_export_count_disagrees;
    Alcotest.test_case "gives no name for a module cut in a section" `Quick
      gives_no_name_for_a_module_cut_in_a_section;
    Alcotest.test_case
      "gives no name for an export name that ends at its section" `Quick
      gives_no_name_for_an_export_name_that_ends_at_its_section;
    Alcotest.test_case "gives no name for bytes that are not a module" `Quick
      gives_no_name_for_bytes_that_are_not_a_module;
    Alcotest.test_case "keeps a base name that is the prefix alone" `Quick
      keeps_a_base_name_that_is_the_prefix_alone;
    Alcotest.test_case "names the grammar" `Quick names_the_grammar;
    property ~name:"the reader of a wasm module answers for any bytes"
      ~print:String.escaped Generators.wasm_bytes
      the_reader_of_a_module_answers_for_any_bytes;
    property ~name:"the reader of a wasm module finds a generated export"
      ~print:(fun (name, wasm) -> name ^ " " ^ String.escaped wasm)
      Generators.wasm_module_with_a_name
      the_reader_of_a_module_finds_a_generated_export;
    property ~name:"a name from a wasm module can name a grammar"
      ~print:String.escaped Generators.wasm_bytes
      a_name_from_a_module_can_name_a_grammar;
    property ~name:"a module that names itself with a NUL byte has no name"
      ~print:String.escaped Generators.wasm_module_whose_name_holds_a_nul
      a_name_from_a_module_can_name_a_grammar;
    property ~name:"a grammar name comes back for any file name"
      ~print:String.escaped Generators.grammar_file_path
      a_grammar_name_comes_back_for_any_file_name;
    property ~name:"a grammar name holds no hyphen" ~print:String.escaped
      Generators.grammar_file_path a_grammar_name_holds_no_hyphen;
    property ~name:"a grammar name drops the prefix and the extension"
      ~print:Fun.id Generators.grammar_export_name
      a_grammar_name_drops_the_prefix_and_the_extension;
  ]
