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

let clean = Sinter_core.Exit_code.clean
let findings = Sinter_core.Exit_code.findings
let usage_error = Sinter_core.Exit_code.usage_error
let environment_error = Sinter_core.Exit_code.environment_error
let refused = Sinter_core.Exit_code.refused

let clean_exit =
  Cmd.Exit.info ~doc:"on success, with no finding to report." clean

let findings_exit =
  Cmd.Exit.info ~doc:"when the command reports at least one finding." findings

let usage_exit =
  Cmd.Exit.info ~doc:"when the command line is wrong." usage_error

let environment_exit =
  Cmd.Exit.info ~doc:"when the command cannot run in this environment."
    environment_error

let refused_exit = Cmd.Exit.info ~doc:"when the command refuses to act." refused

(* Every command of the tool uses these five codes. *)
let exits =
  [ clean_exit; findings_exit; usage_exit; environment_exit; refused_exit ]

(* parse reports captures, not findings, and it asks for no approval. *)
let parse_exits = [ clean_exit; usage_exit; environment_exit ]

let parse_cmd =
  let doc = "Parse files with a tree-sitter grammar and print the captures" in
  let man =
    [
      `S Manpage.s_description;
      `P
        "Load the grammar in GRAMMAR, parse each FILE with it, and run the \
         query in QUERY over each parse tree. Print one capture per line, as \
         canonical JSONL: an object with sorted keys, on one line, with no \
         insignificant whitespace.";
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
      `I ("$(b,eline)", "the line that holds the last byte of the node, from 1");
      `I
        ( "$(b,ecol)",
          "one byte past the last byte of the node, in the line $(b,eline), \
           from 1" );
      `I ("$(b,text)", "the source text of the node");
      `P
        "With $(b,--tree), print the parse tree of each file as an \
         S-expression instead, one tree per line, and read no query.";
    ]
  in
  let info = Cmd.info "parse" ~doc ~man ~exits:parse_exits in
  let grammar =
    let doc =
      "The grammar to parse with: a tree-sitter grammar as $(i,.wasm)."
    in
    Arg.(
      required
      & opt (some string) None
      & info [ "grammar" ] ~docv:"GRAMMAR" ~doc)
  in
  let query =
    let doc =
      "The query to run: tree-sitter query source as $(i,.scm). This option \
       and $(b,--tree) exclude each other; give one of the two."
    in
    Arg.(value & opt (some string) None & info [ "query" ] ~docv:"QUERY" ~doc)
  in
  let tree =
    let doc = "Print the parse tree as an S-expression instead of captures." in
    Arg.(value & flag & info [ "tree" ] ~doc)
  in
  let paths =
    let doc = "The files to parse." in
    Arg.(non_empty & pos_all string [] & info [] ~docv:"FILE" ~doc)
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
        with
        | Sinter_core.Parse.Error message
        | Sys_error message
        | Invalid_argument message
        ->
          Printf.eprintf "sinter: %s\n" message;
          `Ok environment_error)
  in
  Cmd.v info Term.(ret (const run $ grammar $ query $ tree $ paths))

(* serve prints its outcome in the answer, so it reports no finding of
   its own, and it asks for no approval. *)
let serve_exits = [ clean_exit; usage_exit; environment_exit ]

let serve_cmd =
  let doc = "Answer requests that arrive as JSON lines on standard input" in
  let man =
    [
      `S Manpage.s_description;
      `P
        "Read one request for each line of standard input, and answer each \
         request on standard output. Answer a request before reading the next \
         one. Exit when standard input ends.";
      `P
        "A request is a JSON object on one line. Every request holds these two \
         fields:";
      `I
        ( "$(b,id)",
          "the caller's tag for the request: a string or an integer. Every \
           line of the answer carries it in the field $(b,req)" );
      `I
        ( "$(b,op)",
          "the operation to run: the name of a command of this tool. \
           $(b,parse) is the only one" );
      `P
        "The other fields of a request are the options of that command. Each \
         field has the name of a long option. A $(b,parse) request therefore \
         holds $(b,grammar), $(b,query) or $(b,tree), and $(b,files). A field \
         that the command does not name is an error.";
      `P
        "The answer holds every line that the command prints, and one control \
         line after them. The control line holds $(b,event) of $(b,done) when \
         the operation ran. It holds $(b,event) of $(b,error), and a \
         $(b,message), when the operation did not run. The $(b,code) of the \
         control line is the exit code that the command returns. A line that \
         this command cannot read as a request gets an error line with code 2 \
         and no $(b,req).";
      `P
        "The process holds one parser for its whole life. It loads each \
         grammar once, so a caller that sends many requests pays for the load \
         once. It reads a grammar file again when the file changes.";
    ]
  in
  let info = Cmd.info "serve" ~doc ~man ~exits:serve_exits in
  let report message =
    Printf.eprintf "sinter: %s\n" message;
    environment_error
  in
  let rec answer state =
    match In_channel.input_line stdin with
    | None -> clean
    | Some line ->
        let response = Sinter_core.Serve.respond state line in
        List.iter
          (Sinter_core.Jsonl.output stdout)
          (Sinter_core.Serve.lines response);
        flush stdout;
        answer state
  in
  let run () =
    match Sinter_core.Serve.create () with
    | exception Sinter_core.Serve.Error message -> report message
    | state ->
        Fun.protect
          ~finally:(fun () -> Sinter_core.Serve.close state)
          (fun () ->
            (* An exception that is a fault of the tool leaves the
               loop and reaches the argument parser, which reports its
               own code. A write that fails is a fault of the
               environment. *)
            try answer state
            with Sys_error message ->
              report (Printf.sprintf "cannot write the output: %s" message))
  in
  Cmd.v info Term.(const run $ const ())

let cmd =
  let doc = "plans die into residue; residue is checked" in
  let info = Cmd.info "sinter" ~version ~doc ~exits in
  Cmd.group info
    ~default:Term.(ret (const (`Help (`Pager, None))))
    [ parse_cmd; serve_cmd ]

let () =
  let code = Cmd.eval' ~term_err:usage_error cmd in
  exit (if code = Cmd.Exit.cli_error then usage_error else code)
