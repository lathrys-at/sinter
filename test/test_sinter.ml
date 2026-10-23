(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(* Dune runs the suite in the build copy of test/, and the executable
   sits beside it in the build copy of bin/. *)
let binary = Filename.concat (Sys.getcwd ()) "../bin/main.exe"

(* Many shells of Rust developers set RUST_BACKTRACE, and a Rust
   backtrace inside the process stopped it on macOS until the bridge
   turned backtraces off. The suite always runs with it set, so that
   the adapter tests, whose errors come from wasmtime, keep that fixed. *)
let () = Unix.putenv "RUST_BACKTRACE" "full"

let () =
  let mode =
    match
      Fixture.mode_of_environment
        ~promote:(Sys.getenv_opt "SINTER_PROMOTE")
        ~source_root:(Sys.getenv_opt "DUNE_SOURCEROOT")
    with
    | Ok mode -> mode
    | Error reason ->
        prerr_endline reason;
        exit 2
  in
  let written = ref [] in
  (match mode with
  | Fixture.Compare -> ()
  | Fixture.Promote_into _ ->
      at_exit (fun () ->
          Format.print_flush ();
          match List.rev !written with
          | [] -> print_endline "SINTER_PROMOTE: no expected file changed."
          | paths ->
              List.iter (Printf.printf "SINTER_PROMOTE: wrote %s\n") paths));
  Alcotest.run "sinter"
    [
      ("version", Test_version.tests);
      ("jsonl", Test_jsonl.tests);
      ("utf-8", Test_utf_8.tests);
      ("text file", Test_text_file.tests);
      ("grammar name", Test_grammar_name.tests);
      ("parse record", Test_parse_record.tests);
      ("grammar", Test_grammar.tests);
      ("query file", Test_query_file.tests);
      ("spec examples", Test_spec_examples.tests);
      ("bridge decode", Test_bridge_decode.tests);
      ("bridge decode v2", Test_bridge_decode_v2.tests);
      ("parse", Test_parse.tests);
      ("bridge", Test_bridge.tests);
      ("adapter", Test_adapter.tests);
      ("sha256", Test_sha256.tests);
      ("markdown pack", Test_markdown_pack.tests);
      ("line index", Test_line_index.tests);
      ("tag line", Test_tag_line.tests);
      ("slug", Test_slug.tests);
      ("toml raw", Test_toml_raw.tests);
      ("toml", Test_toml.tests);
      ("toml conformance", Test_toml_conformance.tests);
      ("request", Test_request.tests);
      ("serve", Test_serve.tests);
      ("cli", Test_cli.tests);
      ("git", Test_git.tests);
      ("git diff", Test_git_diff.tests);
      ("fixture", Test_fixture.tests);
      ("edit distance", Test_edit_distance.tests);
      ("glob", Test_glob.tests);
      ("id pattern", Test_id_pattern.tests);
      ("branch name", Test_branch_name.tests);
      ("finding class", Test_finding_class.tests);
      ("major minor", Test_major_minor.tests);
      ("manifest", Test_manifest.tests);
      ( "cases",
        Fixture.tests ~binary mode
          ~on_write:(fun path -> written := path :: !written)
          "cases" );
    ]
