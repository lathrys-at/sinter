(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

open Sinter_core
module Gen = QCheck2.Gen

let property ?(count = 500) ~name ~print generator check =
  QCheck_alcotest.to_alcotest ~speed_level:`Quick
    (QCheck2.Test.make ~count ~name ~print generator check)

let tag_line =
  Alcotest.testable
    (fun formatter (at, (line : Tag_line.t)) ->
      Format.fprintf formatter "%d %S %S" at line.word line.rest)
    ( = )

let parts =
  Alcotest.testable
    (fun formatter (parts : Tag_line.parts) ->
      Format.fprintf formatter "%s %s %S"
        (Option.fold ~none:"-" ~some:(Printf.sprintf "%S") parts.target)
        (Option.fold ~none:"-" ~some:string_of_int parts.revision)
        parts.description)
    ( = )

let read_gives cases () =
  List.iter
    (fun (text, expected) ->
      Alcotest.(check (option tag_line)) text expected (Tag_line.read text))
    cases

let reads_the_word_and_the_rest =
  read_gives
    [
      ("@req auth v2", Some (0, { Tag_line.word = "req"; rest = " auth v2" }));
      ("@foo-bar: text", Some (0, { word = "foo-bar"; rest = ": text" }));
      ("@", Some (0, { word = ""; rest = "" }));
      ("@ x", Some (0, { word = ""; rest = " x" }));
      ("@req_x", Some (0, { word = "req"; rest = "_x" }));
    ]

let skips_the_blanks_at_the_start =
  read_gives [ (" \t @cites x", Some (3, { word = "cites"; rest = " x" })) ]

let refuses_a_line_without_an_at_sign =
  read_gives [ ("", None); ("text @req x", None); ("- @req x", None) ]

let parts_give cases () =
  List.iter
    (fun (rest, expected) ->
      Alcotest.check parts rest expected (Tag_line.parts rest))
    cases

let reads_a_target_a_revision_and_a_description =
  parts_give
    [
      ( " auth v2 Lock it.",
        { target = Some "auth"; revision = Some 2; description = " Lock it." }
      );
      (" auth", { target = Some "auth"; revision = None; description = "" });
      (" auth  ", { target = Some "auth"; revision = None; description = "  " });
      ( "\tauth\tv10\t",
        { target = Some "auth"; revision = Some 10; description = "\t" } );
      ("", { target = None; revision = None; description = "" });
      ("   ", { target = None; revision = None; description = "" });
    ]

let takes_a_bad_revision_as_description =
  parts_give
    [
      (" a v0 x", { target = Some "a"; revision = None; description = " v0 x" });
      (" a v01", { target = Some "a"; revision = None; description = " v01" });
      (" a v", { target = Some "a"; revision = None; description = " v" });
      (" a V2", { target = Some "a"; revision = None; description = " V2" });
      (" a v2x", { target = Some "a"; revision = None; description = " v2x" });
      ( " a v9007199254740992",
        {
          target = Some "a";
          revision = None;
          description = " v9007199254740992";
        } );
      ( " a v12345678901234567",
        {
          target = Some "a";
          revision = None;
          description = " v12345678901234567";
        } );
    ]

let reads_the_largest_revision =
  parts_give
    [
      ( " a v9007199254740991",
        {
          target = Some "a";
          revision = Some 9007199254740991;
          description = "";
        } );
    ]

let without_revision_gives cases () =
  List.iter
    (fun (rest, expected) ->
      Alcotest.(check string) rest expected (Tag_line.without_revision rest))
    cases

let drops_the_revision_and_the_blanks_before_it =
  without_revision_gives
    [
      (" x v2", " x");
      (" x \t v2 because", " x because");
      (" x because", " x because");
      (" x", " x");
      ("", "");
      (" x v0", " x v0");
    ]

(* A text of tokens that collide often with the forms of a tag. *)
let rest =
  Gen.map (String.concat "")
    (Gen.list_size (Gen.int_range 0 8)
       (Gen.oneof_list
          [ " "; "\t"; "a"; "v"; "1"; "0"; "v2"; "-"; "@"; "\xC3\xA9" ]))

let parts_rebuild_the_rest =
  property
    ~name:"the target, the revision, and the description rebuild the rest"
    ~print:String.escaped rest (fun rest ->
      let parts = Tag_line.parts rest in
      let trimmed = String.trim rest in
      match parts.target with
      | None -> trimmed = "" && parts.description = ""
      | Some target -> (
          String.length target > 0
          && String.ends_with ~suffix:parts.description rest
          &&
          match parts.revision with
          | None -> String.ends_with ~suffix:(target ^ parts.description) rest
          | Some value ->
              String.ends_with
                ~suffix:("v" ^ string_of_int value ^ parts.description)
                rest
              && not (String.equal (Tag_line.without_revision rest) rest)))

(* Between the target and the description, only the revision token and
   the blanks before it go. *)
let without_revision_keeps_the_target_and_the_description =
  property ~name:"without_revision leaves the target and the description"
    ~print:String.escaped rest (fun rest ->
      let parts = Tag_line.parts rest in
      let changed = Tag_line.without_revision rest in
      match (parts.target, parts.revision) with
      | _, None -> String.equal changed rest
      | None, Some _ -> false
      | Some target, Some _ ->
          let length =
            String.length changed - String.length parts.description
          in
          length >= 0
          && String.ends_with ~suffix:parts.description changed
          && String.ends_with ~suffix:target (String.sub changed 0 length)
          && String.length changed < String.length rest)

let tests =
  [
    Alcotest.test_case "reads the word and the rest" `Quick
      reads_the_word_and_the_rest;
    Alcotest.test_case "skips the blanks at the start" `Quick
      skips_the_blanks_at_the_start;
    Alcotest.test_case "refuses a line without an at sign first" `Quick
      refuses_a_line_without_an_at_sign;
    Alcotest.test_case "reads a target, a revision, and a description" `Quick
      reads_a_target_a_revision_and_a_description;
    Alcotest.test_case "takes a bad revision as description" `Quick
      takes_a_bad_revision_as_description;
    Alcotest.test_case "reads the largest revision" `Quick
      reads_the_largest_revision;
    Alcotest.test_case "drops the revision and the blanks before it" `Quick
      drops_the_revision_and_the_blanks_before_it;
    parts_rebuild_the_rest;
    without_revision_keeps_the_target_and_the_description;
  ]
