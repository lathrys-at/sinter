(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

let () =
  Alcotest.run "sinter"
    [
      ("version", Test_version.tests);
      ("jsonl", Test_jsonl.tests);
      ("bridge decode", Test_bridge_decode.tests);
      ("parse", Test_parse.tests);
      ("bridge", Test_bridge.tests);
      ("request", Test_request.tests);
      ("serve", Test_serve.tests);
      ("cli", Test_cli.tests);
    ]
