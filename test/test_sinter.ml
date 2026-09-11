(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

let base_is_semver () =
  let is_number s =
    s <> "" && String.for_all (fun c -> c >= '0' && c <= '9') s
  in
  let ok =
    match String.split_on_char '.' Sinter_core.Version.base with
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
    (String.length Sinter_core.Git_version.describe > 0)

let () =
  Alcotest.run "sinter"
    [
      ( "version",
        [
          Alcotest.test_case "base is semver" `Quick base_is_semver;
          Alcotest.test_case "the description names the build" `Quick
            describe_names_the_build;
        ] );
      ("jsonl", Test_jsonl.tests);
      ("bridge decode", Test_bridge_decode.tests);
      ("parse", Test_parse.tests);
      ("bridge", Test_bridge.tests);
      ("request", Test_request.tests);
      ("serve", Test_serve.tests);
      ("cli", Test_cli.tests);
    ]
