(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

let version_is_set () =
  Alcotest.(check bool)
    "version is not empty" true
    (String.length Sinter_core.Version.current > 0)

let () =
  Alcotest.run "sinter"
    [
      ("version", [ Alcotest.test_case "version is set" `Quick version_is_set ]);
    ]
