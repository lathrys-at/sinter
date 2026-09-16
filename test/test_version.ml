(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

open Sinter_core
module Gen = QCheck2.Gen

let base_is_semver () =
  let is_number s =
    s <> "" && String.for_all (fun c -> c >= '0' && c <= '9') s
  in
  let ok =
    match String.split_on_char '.' Version.base with
    | [ major; minor; patch ] ->
        is_number major && is_number minor && is_number patch
    | _ -> false
  in
  Alcotest.(check bool) "base is MAJOR.MINOR.PATCH" true ok

(* A checkout gives its own description; a release archive with no
   git gives "unknown". Either way the value names the build. *)
let describe_names_the_build () =
  Alcotest.(check bool)
    "the description is not empty" true
    (String.length Git_version.describe > 0)

(* The five roads of Version.render, and the corner where the package
   is the empty string. Each test states the whole answer, because a
   test that stated a prefix of it would leave three of the mutants of
   that function alive.

   The three tests of the package road pass a description that no road
   of the description turns into any of the answers below, so that a
   road which fell through to the description cannot give the right
   answer by accident. *)
let not_read = "not-read"
let renders = Alcotest.(check string)

let a_package_version_gains_the_letter_v () =
  renders "the package version 2.3.4 prints as v2.3.4" "v2.3.4"
    (Version.render ~package:(Some "2.3.4") ~describe:not_read)

let a_package_version_that_has_the_letter_v_keeps_it () =
  renders "the package version v2.3.4 prints as it stands" "v2.3.4"
    (Version.render ~package:(Some "v2.3.4") ~describe:not_read)

(* There is no first letter to read, so the value comes back as it
   stands. A reader of the first letter of this string would raise
   Invalid_argument. *)
let a_package_version_of_no_characters_prints_as_nothing () =
  renders "the empty package version prints as the empty string" ""
    (Version.render ~package:(Some "") ~describe:not_read)

(* A description that holds a full stop is the name of a tag. *)
let a_description_that_names_a_tag_prints_as_it_stands () =
  renders "the description v2.3.4 prints as v2.3.4" "v2.3.4"
    (Version.render ~package:None ~describe:"v2.3.4")

let a_build_that_read_no_checkout_prints_the_release_and_dev () =
  renders "the description unknown prints the release version and -dev"
    ("v" ^ Version.base ^ "-dev")
    (Version.render ~package:None ~describe:"unknown")

let a_description_that_is_a_bare_hash_goes_after_the_release () =
  renders "the description 44992d4 goes after the release version and -dev"
    ("v" ^ Version.base ^ "-dev+44992d4")
    (Version.render ~package:None ~describe:"44992d4")

(* The properties that lib/version.mli states about the answer. The
   generator draws the descriptions that mean something to the
   function beside descriptions that mean nothing to it, and any
   bytes as well. *)
let describe =
  Gen.oneof
    [
      Gen.return "";
      Gen.return "unknown";
      Gen.return "44992d4";
      Gen.return "v2.3.4";
      Gen.return "v2.3.4-5-g44992d4";
      Generators.ascii_string;
      Generators.utf_8_string;
      Gen.string;
    ]

let package =
  Gen.oneof
    [ Gen.return None; Gen.map Option.some describe; Gen.return (Some "") ]

let pair = Gen.pair package describe

let print_pair (package, describe) =
  Printf.sprintf "package=%s describe=%S"
    (match package with None -> "None" | Some s -> Printf.sprintf "Some %S" s)
    describe

let property ~name generator check =
  QCheck_alcotest.to_alcotest ~speed_level:`Quick
    (QCheck2.Test.make ~count:1000 ~name ~print:print_pair generator check)

(* "The function raises nothing." Anything that comes out of render
   other than a string reaches QCheck as an error of the test. *)
let render_answers_every_pair =
  property ~name:"render answers every pair and raises nothing" pair
    (fun (package, describe) ->
      match Version.render ~package ~describe with _ -> true)

(* "It returns the empty string for [Some ""] alone." *)
let the_empty_answer_belongs_to_the_empty_package =
  property ~name:"the empty string comes back for the empty package alone" pair
    (fun (package, describe) ->
      String.equal (Version.render ~package ~describe) "" = (package = Some ""))

let case name test = Alcotest.test_case name `Quick test

let tests =
  [
    case "base is semver" base_is_semver;
    case "the description names the build" describe_names_the_build;
    case "a package version gains the letter v"
      a_package_version_gains_the_letter_v;
    case "a package version that has the letter v keeps it"
      a_package_version_that_has_the_letter_v_keeps_it;
    case "a package version of no characters prints as nothing"
      a_package_version_of_no_characters_prints_as_nothing;
    case "a description that names a tag prints as it stands"
      a_description_that_names_a_tag_prints_as_it_stands;
    case "a build that read no checkout prints the release and -dev"
      a_build_that_read_no_checkout_prints_the_release_and_dev;
    case "a description that is a bare hash goes after the release"
      a_description_that_is_a_bare_hash_goes_after_the_release;
  ]
  @ [ render_answers_every_pair; the_empty_answer_belongs_to_the_empty_package ]
