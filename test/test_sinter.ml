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

let () =
  Alcotest.run "sinter"
    [
      ("version", [ Alcotest.test_case "base is semver" `Quick base_is_semver ]);
      ("jsonl", Test_jsonl.tests);
      ("parse", Test_parse.tests);
      ("request", Test_request.tests);
      ("cli", Test_cli.tests);
    ]
