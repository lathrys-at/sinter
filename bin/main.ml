(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

open Cmdliner

let version =
  Sinter_core.Version.render
    ~package:
      (Option.map Build_info.V1.Version.to_string (Build_info.V1.version ()))
    ~describe:Sinter_core.Git_version.describe

let clean = Sinter_core.Exit_code.clean
let findings = Sinter_core.Exit_code.findings
let usage_error = Sinter_core.Exit_code.usage_error
let environment_error = Sinter_core.Exit_code.environment_error
let refused = Sinter_core.Exit_code.refused
let clean_exit = Cmd.Exit.info ~doc:"on success, when no finding blocks." clean

let findings_exit =
  Cmd.Exit.info
    ~doc:"when the command reports at least one finding that blocks." findings

let usage_exit =
  Cmd.Exit.info ~doc:"when the command line is wrong." usage_error

let environment_exit =
  Cmd.Exit.info ~doc:"when the command cannot run in this environment."
    environment_error

let refused_exit = Cmd.Exit.info ~doc:"when the command refuses to act." refused

let exits =
  [ clean_exit; findings_exit; usage_exit; environment_exit; refused_exit ]

let parse_exits = [ clean_exit; usage_exit; environment_exit ]

let with_phases run =
  match Sys.getenv_opt Sinter_core.Allocation.variable with
  | None | Some "" -> run None
  | Some path -> (
      let phases = Sinter_core.Allocation.create () in
      let code = run (Some phases) in
      try
        Out_channel.with_open_bin path (fun channel ->
            Out_channel.output_string channel
              (Sinter_core.Allocation.to_string phases));
        code
      with Sys_error message ->
        Printf.eprintf "sinter: cannot write the words of the phases: %s\n"
          message;
        environment_error)

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
        with Sinter_core.Parse.Error message | Sys_error message ->
          Printf.eprintf "sinter: %s\n" message;
          `Ok environment_error)
  in
  Cmd.v info Term.(ret (const run $ grammar $ query $ tree $ paths))

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
        ( "$(b,rid)",
          "the request id, which the caller chooses: a string or an integer. \
           Every line of the answer carries it back in the field $(b,rid)" );
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
         and no $(b,rid).";
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
    | exception Sys_error message ->
        report (Printf.sprintf "cannot read the input: %s" message)
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
            try answer state
            with Sys_error message ->
              report (Printf.sprintf "cannot write the output: %s" message))
  in
  Cmd.v info Term.(const run $ const ())

let scan_exits = [ clean_exit; usage_exit; environment_exit ]

let scan_cmd =
  let doc = "Print the facts of the repository as JSON lines" in
  let man =
    [
      `S Manpage.s_description;
      `P
        "Read the git repository that holds the current folder, and print one \
         fact per line, as canonical JSONL: an object with sorted keys, on one \
         line, with no insignificant whitespace.";
      `P
        "The first line is the index record. It names the tree key of the \
         working tree, the base commit, the target branch, the manifest, and \
         the version of the tool. The facts follow, sorted by kind, path, \
         line, column, and id; the facts with no path come last, sorted by id.";
      `P
        "The command reads the manifest, and each file of the repository that \
         the pack markdown reads. A file that git ignores, a symbolic link, a \
         file inside a submodule, and a file whose path is not UTF-8 are not \
         read. Each warning goes to standard error.";
    ]
  in
  let info = Cmd.info "scan" ~doc ~man ~exits:scan_exits in
  let manifest =
    let doc =
      "The manifest to read, instead of $(i,sinter.toml) at the root of the \
       repository. A relative path is relative to the current folder."
    in
    Arg.(value & opt (some string) None & info [ "manifest" ] ~docv:"PATH" ~doc)
  in
  let base =
    let doc =
      "The base commit, as a git revision. Without this option, the base is \
       the merge base of HEAD and the target branch of the manifest."
    in
    Arg.(value & opt (some string) None & info [ "base" ] ~docv:"REVISION" ~doc)
  in
  let report lines = List.iter (Printf.eprintf "sinter: %s\n") lines in
  let run manifest base =
    with_phases (fun phases ->
        match
          Sinter_core.Scan.run ?phases ~env:(Unix.environment ())
            ~dir:(Sys.getcwd ()) ~manifest ~base ~tool:version ()
        with
        | Error error ->
            report (Sinter_core.Scan.messages error);
            environment_error
        | Ok { warnings; records } -> (
            report warnings;
            try
              Sinter_core.Allocation.measure phases "output" (fun () ->
                  List.iter (Sinter_core.Jsonl.output stdout) records;
                  flush stdout);
              clean
            with Sys_error message ->
              report [ Printf.sprintf "cannot write the output: %s" message ];
              environment_error))
  in
  Cmd.v info Term.(const run $ manifest $ base)

let check_exits = [ clean_exit; findings_exit; usage_exit; environment_exit ]

let check_cmd =
  let doc = "Report the findings of the working tree" in
  let man =
    [
      `S Manpage.s_description;
      `P
        "Read the git repository that holds the current folder, as $(b,sinter \
         scan) reads it, and report each finding: a place where the files of \
         the repository break a rule of Sinter. Print one finding per line:";
      `Pre "  PATH:LINE:COLUMN: CLASS SUBJECT DETAIL";
      `P
        "CLASS is the finding class, SUBJECT the id of what the finding is \
         about, and DETAIL says more when the class has more to say. A line \
         that starts with $(b,fix:) follows a finding whose class names a \
         repair: the text to paste, or what to do. A finding with no place \
         prints $(b,-:-:-:) for its place. The findings are sorted by path, \
         line, column, and class.";
      `P
        "With $(b,--gate), each finding takes the tier of its class at that \
         gate, and the tier follows the place. A class whose tier is $(b,off), \
         or that takes no tier at the gate, reports nothing. Without \
         $(b,--gate), the command reports every finding, with no tier.";
      `P
        "In text form, the command names the base on standard error; with \
         $(b,--json), the index record names it. Each warning goes to standard \
         error.";
    ]
  in
  let exits_doc =
    [
      `S Manpage.s_exit_status;
      `P
        "With $(b,--gate), a finding blocks when its tier at the gate is \
         $(b,block). Without $(b,--gate), no finding blocks, unless \
         $(b,--strict) is given.";
    ]
  in
  let info = Cmd.info "check" ~doc ~man:(man @ exits_doc) ~exits:check_exits in
  let manifest =
    let doc =
      "The manifest to read, instead of $(i,sinter.toml) at the root of the \
       repository. A relative path is relative to the current folder."
    in
    Arg.(value & opt (some string) None & info [ "manifest" ] ~docv:"PATH" ~doc)
  in
  let base =
    let doc =
      "The base commit, as a git revision. Without this option, the base is \
       the merge base of HEAD and the target branch of the manifest."
    in
    Arg.(value & opt (some string) None & info [ "base" ] ~docv:"REVISION" ~doc)
  in
  let gate =
    let doc =
      "The gate to check at: $(b,turn), at the end of a turn of an agent; \
       $(b,merge), on a change before it merges into the target branch; or \
       $(b,target), on the target branch after a merge."
    in
    let gates =
      List.map
        (fun gate -> (Sinter_core.Finding_class.gate_name gate, gate))
        Sinter_core.Finding_class.gates
    in
    Arg.(
      value & opt (some (enum gates)) None & info [ "gate" ] ~docv:"GATE" ~doc)
  in
  let strict =
    let doc =
      "Count every finding that the command reports as one that blocks."
    in
    Arg.(value & flag & info [ "strict" ] ~doc)
  in
  let json =
    let doc =
      "Print canonical JSONL instead of text: the index record first, as \
       $(b,sinter scan) prints it, and then one record per finding."
    in
    Arg.(value & flag & info [ "json" ] ~doc)
  in
  let report lines = List.iter (Printf.eprintf "sinter: %s\n") lines in
  let run manifest base gate strict json =
    with_phases @@ fun phases ->
    match
      Sinter_core.Check.run ?phases ~env:(Unix.environment ())
        ~dir:(Sys.getcwd ()) ~manifest ~base ~gate ~strict
        ~format:
          (if json then Sinter_core.Check.Json else Sinter_core.Check.Text)
        ~tool:version ()
    with
    | Error error ->
        report (Sinter_core.Scan.messages error);
        environment_error
    | Ok { messages; lines; code } -> (
        report messages;
        try
          Sinter_core.Allocation.measure phases "output" (fun () ->
              List.iter
                (fun line ->
                  output_string stdout line;
                  output_char stdout '\n')
                lines;
              flush stdout);
          code
        with Sys_error message ->
          report [ Printf.sprintf "cannot write the output: %s" message ];
          environment_error)
  in
  Cmd.v info Term.(const run $ manifest $ base $ gate $ strict $ json)

let cmd =
  let doc = "plans die into residue; residue is checked" in
  let info = Cmd.info "sinter" ~version ~doc ~exits in
  Cmd.group info
    ~default:Term.(ret (const (`Help (`Pager, None))))
    [ check_cmd; parse_cmd; scan_cmd; serve_cmd ]

let reserve fd flags =
  match Unix.fstat fd with
  | _ -> false
  | exception Unix.Unix_error (Unix.EBADF, _, _) ->
      ignore
        (Unix.openfile "/dev/null" flags
           (0
           [@mutaml.skip
             "openfile reads the mode only when it creates the file; the flags \
              hold no O_CREAT, and /dev/null exists"]));
      true

let () =
  ignore (reserve Unix.stdin [ Unix.O_RDONLY ]);
  let output_closed = reserve Unix.stdout [ Unix.O_WRONLY ] in
  ignore (reserve Unix.stderr [ Unix.O_WRONLY ]);
  if output_closed then (
    prerr_endline "sinter: cannot write the output: standard output is closed";
    exit environment_error);
  let code = Cmd.eval' ~term_err:usage_error cmd in
  exit (if code = Cmd.Exit.cli_error then usage_error else code)
