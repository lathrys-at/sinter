(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

open Cmdliner

(* An opam release build carries the package version; print it. A
   development build carries none, so use "git describe": on a tagged
   commit it is the tag; otherwise it is a bare hash (no dot), and the
   next planned release version is prefixed. *)
let version =
  match Build_info.V1.version () with
  | Some v ->
      let s = Build_info.V1.Version.to_string v in
      if s <> "" && s.[0] <> 'v' then "v" ^ s else s
  | None ->
      let d = Sinter_core.Git_version.describe in
      if String.contains d '.' then d
      else if d = "unknown" then "v" ^ Sinter_core.Version.base ^ "-dev"
      else "v" ^ Sinter_core.Version.base ^ "-dev+" ^ d

(* Section 9 of docs/design-notes.md fixes the exit codes of every
   command: 0 clean, 1 findings present, 2 usage error, 3 environment
   error, 4 refused. A grammar that does not load, a query that does
   not parse, and a file that is not text are environment errors. *)
let clean = 0
let usage_error = 2
let environment_error = 3

let parse_cmd =
  let doc = "Parse files with a tree-sitter grammar and print the captures" in
  let man =
    [
      `S Manpage.s_description;
      `P
        "Load the grammar in GRAMMAR, parse each FILE with it, and run the \
         query in QUERY over each parse tree. Print one capture per line, as \
         canonical JSONL. See spec/jsonl.md section 2 for the canonical form.";
      `P "Each line holds these fields:";
      `I ("$(b,path)", "the file, as it was named on the command line");
      `I ("$(b,pat)", "the index of the pattern in the query, from 0");
      `I ("$(b,cap)", "the capture name, without the at sign");
      `I ("$(b,node)", "the type of the node, for example string_content");
      `I
        ( "$(b,sb), $(b,eb)",
          "the start and the end of the node, as byte offsets from the start \
           of the file. The end is exclusive" );
      `I
        ( "$(b,line), $(b,col)",
          "the start of the node, from 1. The column counts bytes, not \
           characters" );
      `I
        ( "$(b,eline), $(b,ecol)",
          "the end of the node, from 1. The column is exclusive" );
      `I ("$(b,text)", "the source text of the node");
      `P
        "With $(b,--tree), print the parse tree of each file as an \
         S-expression instead, one tree per line, and read no query.";
    ]
  in
  let info = Cmd.info "parse" ~doc ~man in
  let grammar =
    let doc =
      "The grammar to parse with: a tree-sitter grammar as $(i,.wasm)."
    in
    Arg.(
      required & opt (some file) None & info [ "grammar" ] ~docv:"GRAMMAR" ~doc)
  in
  let query =
    let doc =
      "The query to run: tree-sitter query source as $(i,.scm). This option \
       and $(b,--tree) exclude each other; give one of the two."
    in
    Arg.(value & opt (some file) None & info [ "query" ] ~docv:"QUERY" ~doc)
  in
  let tree =
    let doc = "Print the parse tree as an S-expression instead of captures." in
    Arg.(value & flag & info [ "tree" ] ~doc)
  in
  let paths =
    let doc = "The files to parse." in
    Arg.(non_empty & pos_all file [] & info [] ~docv:"FILE" ~doc)
  in
  let run grammar query tree paths =
    match (query, tree) with
    | Some _, true ->
        `Error
          (false, "--query and --tree exclude each other; give one of the two")
    | None, false -> `Error (false, "give either --query or --tree")
    | query, _ -> (
        try
          Sinter_core.Parse.run ~grammar ~query ~paths stdout;
          `Ok clean
        with Sinter_core.Parse.Error message ->
          Printf.eprintf "sinter: %s\n" message;
          `Ok environment_error)
  in
  Cmd.v info Term.(ret (const run $ grammar $ query $ tree $ paths))

let cmd =
  let doc = "plans die into residue; residue is checked" in
  let info = Cmd.info "sinter" ~version ~doc in
  Cmd.group info
    ~default:Term.(ret (const (`Help (`Pager, None))))
    [ parse_cmd ]

(* Cmdliner reports a wrong command line with its own exit code, 124.
   Map that code to the one the design notes fix. *)
let () =
  let code = Cmd.eval' ~term_err:usage_error cmd in
  exit (if code = Cmd.Exit.cli_error then usage_error else code)
