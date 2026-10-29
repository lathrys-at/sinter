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
let clean_exit = Cmd.Exit.info ~doc:"on success, when no finding blocks." clean
let success_exit = Cmd.Exit.info ~doc:"on success." clean

let findings_exit =
  Cmd.Exit.info
    ~doc:"when the command reports at least one finding that blocks." findings

let usage_exit =
  Cmd.Exit.info ~doc:"when the command line is wrong." usage_error

let environment_exit =
  Cmd.Exit.info ~doc:"when the command cannot run in this environment."
    environment_error

let exits = [ clean_exit; findings_exit; usage_exit; environment_exit ]
let parse_exits = [ success_exit; usage_exit; environment_exit ]

let colored setting descriptor =
  Sinter_core.Style.color setting ~getenv:Sys.getenv_opt
    ~terminal:(Unix.isatty descriptor)

let report setting errors =
  let ppf =
    Sinter_core.Style.formatter stderr ~color:(colored setting Unix.stderr)
  in
  Sinter_core.Render.errors ppf errors;
  Format.pp_print_flush ppf ()

let failure ~help fault = { Sinter_core.Error_text.fault; help; place = None }

let output_failure message =
  failure ~help:Sinter_core.Error_text.output_help
    ("cannot write the output: " ^ message)

let with_phases setting run =
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
        report setting
          [
            failure
              ~help:
                ("name a file that you can write in "
               ^ Sinter_core.Allocation.variable)
              ("cannot write the words of the phases: " ^ message);
          ];
        environment_error)

let plumbing = "PLUMBING COMMANDS"

let envs =
  let rule condition result =
    Printf.sprintf "When it is %s, the output gets %s." condition result
  in
  [
    Cmd.Env.info "NO_COLOR" ~doc:(rule "set and not empty" "no color");
    Cmd.Env.info "CLICOLOR_FORCE" ~doc:(rule "set and not $(b,0)" "color");
    Cmd.Env.info "FORCE_COLOR" ~doc:(rule "set and not empty" "color");
    Cmd.Env.info "CLICOLOR" ~doc:(rule "$(b,0)" "no color");
    Cmd.Env.info "TERM" ~doc:(rule "$(b,dumb)" "no color");
  ]

let environment =
  [
    `S Manpage.s_environment;
    `P
      "The value $(b,always) or $(b,never) of the option $(b,--color) wins \
       over each of these variables. The option $(b,--color) of each command \
       gives the order of the rules.";
  ]

let color =
  let doc =
    "When to color the output: $(b,auto), $(b,always), or $(b,never). Color \
     applies to the full and brief forms and to the messages on standard \
     error, and never to JSON. With $(b,auto), the first of these rules that \
     matches decides, for standard output and for standard error apart: \
     $(b,NO_COLOR) set and not empty gives no color; $(b,CLICOLOR_FORCE) set \
     and not $(b,0), or $(b,FORCE_COLOR) set and not empty, gives color; \
     $(b,TERM) set to $(b,dumb), or $(b,CLICOLOR) set to $(b,0), gives no \
     color; otherwise a stream gets color when it is a terminal. An error on \
     the command line comes before this option is read, so it takes its color \
     from these rules alone."
  in
  Arg.(
    value
    & opt
        (enum
           [
             ("auto", Sinter_core.Style.Auto);
             ("always", Sinter_core.Style.Always);
             ("never", Sinter_core.Style.Never);
           ])
        Sinter_core.Style.Auto
    & info [ "color" ] ~docv:"WHEN" ~doc)

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
  let info =
    Cmd.info "parse" ~docs:plumbing ~doc ~man:(man @ environment) ~envs
      ~exits:parse_exits
  in
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
  let run color grammar query tree paths =
    match (query, tree) with
    | Some _, true ->
        `Error
          (true, "--query and --tree exclude each other; give one of the two")
    | None, false -> `Error (true, "give either --query or --tree")
    | query, _ -> (
        try
          Sinter_core.Parse.run ~grammar ~query ~paths stdout;
          `Ok clean
        with
        | Sinter_core.Parse.Error error ->
            report color [ error ];
            `Ok environment_error
        | Sys_error message ->
            report color [ output_failure message ];
            `Ok environment_error)
  in
  Cmd.v info Term.(ret (const run $ color $ grammar $ query $ tree $ paths))

let serve_exits = [ success_exit; usage_exit; environment_exit ]

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
  let info =
    Cmd.info "serve" ~docs:plumbing ~doc ~man:(man @ environment) ~envs
      ~exits:serve_exits
  in
  let rec answer color state =
    match In_channel.input_line stdin with
    | exception Sys_error message ->
        report color
          [
            failure ~help:"give the command an input that it can read"
              ("cannot read the input: " ^ message);
          ];
        environment_error
    | None -> clean
    | Some line ->
        let response = Sinter_core.Serve.respond state line in
        List.iter
          (Sinter_core.Jsonl.output stdout)
          (Sinter_core.Serve.lines response);
        flush stdout;
        answer color state
  in
  let run color =
    match Sinter_core.Serve.create () with
    | exception Sinter_core.Serve.Error error ->
        report color [ error ];
        environment_error
    | state ->
        Fun.protect
          ~finally:(fun () -> Sinter_core.Serve.close state)
          (fun () ->
            try answer color state
            with Sys_error message ->
              report color [ output_failure message ];
              environment_error)
  in
  Cmd.v info Term.(const run $ color)

let scan_exits = [ success_exit; usage_exit; environment_exit ]

let scan_cmd =
  let doc = "Print the facts of the repository as JSON lines" in
  let man =
    [
      `S Manpage.s_description;
      `P
        "Read the current working tree, and print one fact per line, as \
         canonical JSONL: an object with sorted keys, on one line, with no \
         insignificant whitespace.";
      `P
        "The first line is the index record. It names the tree key of the \
         working tree, the base commit, the default branch, the manifest, and \
         the version of the tool. The facts follow, sorted by kind, path, \
         line, column, and id; the facts with no path come last, sorted by id.";
      `P
        "The command reads the manifest, and each file of the repository that \
         the markdown pack reads. A file that git ignores, a symbolic link, a \
         file inside a submodule, and a file whose path is not UTF-8 are not \
         read. Each warning goes to standard error.";
      `P
        "When the repository has no ledger ref, $(b,refs/sinter/ledger), and \
         the tree holds a plan, a warning says that every plan counts as open. \
         $(b,sinter check --help) says how to fetch the ledger.";
    ]
  in
  let info =
    Cmd.info "scan" ~docs:plumbing ~doc ~man:(man @ environment) ~envs
      ~exits:scan_exits
  in
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
       the merge base of HEAD and the default branch of the manifest."
    in
    Arg.(value & opt (some string) None & info [ "base" ] ~docv:"REVISION" ~doc)
  in
  let run color manifest base =
    with_phases color (fun phases ->
        match
          Sinter_core.Scan.run ?phases ~env:(Unix.environment ())
            ~dir:(Sys.getcwd ()) ~manifest ~base ~tool:version ()
        with
        | Error error ->
            report color (Sinter_core.Scan.explain error);
            environment_error
        | Ok { warnings; records } -> (
            let errors =
              Sinter_core.Style.formatter stderr
                ~color:(colored color Unix.stderr)
            in
            List.iter (Sinter_core.Render.warning errors) warnings;
            Format.pp_print_flush errors ();
            try
              Sinter_core.Allocation.measure phases "output" (fun () ->
                  List.iter (Sinter_core.Jsonl.output stdout) records;
                  flush stdout);
              clean
            with Sys_error message ->
              report color [ output_failure message ];
              environment_error))
  in
  Cmd.v info Term.(const run $ color $ manifest $ base)

let check_exits = [ clean_exit; findings_exit; usage_exit; environment_exit ]

let check_cmd =
  let doc = "Report the findings of the working tree" in
  let man =
    [
      `S Manpage.s_description;
      `P
        "Check the current working tree, and report each problem that Sinter \
         finds in it. Sinter calls such a problem a finding: for example, a \
         tag that names a spec that does not exist, or a test that checks an \
         old version of a spec.";
      `P
        "By default, each finding prints as a block: a headline that names the \
         class of the problem, for example $(b,dangling) or $(b,suspect), and \
         explains it; the path, the line, and the column; the source line with \
         a mark under the part at fault; the places that relate to the \
         finding; and, when Sinter knows how to repair the finding, the repair \
         as a change of the lines. An empty line stands between two blocks.";
      `P "With $(b,-o brief), each finding prints as one line:";
      `Pre "  PATH:LINE:COLUMN: CLASS DETAIL";
      `P
        "PATH, LINE, and COLUMN say where the problem is. CLASS names the kind \
         of problem. DETAIL explains the problem, when there is more to say. \
         When Sinter knows how to repair a finding, the next line starts with \
         $(b,fix:) and gives the text to paste. A finding that belongs to no \
         one file starts with $(b,-:-:-:) instead of a place.";
      `P
        "The findings are sorted by file, line, column, and class, in every \
         form.";
      `P
        "Each class of finding has a tier at each gate: $(b,off), $(b,warn), \
         or $(b,block). Sinter gives every class a default tier, and the \
         manifest can change it. With $(b,--gate), the command reports only \
         the findings whose tier at that gate is $(b,warn) or $(b,block), and \
         prints the tier before the class, as in $(b,warn[untraced]). Without \
         $(b,--gate), the command reports every finding, and prints no tier.";
      `P
        "After the findings, the full and brief forms print a summary on \
         standard error, for example $(b,8 findings in 2 files: 7 block, 1 \
         warn; 4 have a fix). Warnings also go to standard error. The JSON \
         form prints no summary.";
      `P
        "Some checks compare the working tree with a base commit. With \
         $(b,-v), the full and brief forms name the base on standard error. \
         The JSON form names it in the first record.";
      `P
        "In the full and brief forms, the findings of the classes \
         $(b,untraced), $(b,unmet-promise), and $(b,awaiting-approval) fold \
         into one line for each class and file, with a count, when a file has \
         two or more of them. A class that blocks at the gate does not fold, \
         and nothing folds with $(b,--strict) or $(b,-v). A note on standard \
         error says how many findings are folded. The JSON form gives every \
         finding.";
      `P
        "Sinter keeps the approvals and the completed plans in a ledger, on \
         the git ref $(b,refs/sinter/ledger). When the repository has no such \
         ref and the tree holds a plan, a warning says that every plan counts \
         as open. To fetch the ledger from the remote $(b,origin), run:";
      `Pre "  git fetch origin refs/sinter/ledger:refs/sinter/ledger";
      `P
        "With $(b,--diff), the command reports only the findings that the \
         changes since the base add. It checks the base with the same \
         manifest, and leaves out each finding that the base already has. A \
         finding whose lines moved, and whose text the changes did not touch, \
         counts as one that the base has.";
    ]
  in
  let exits_doc =
    [
      `S Manpage.s_exit_status;
      `P
        "A finding blocks when its tier at the gate is $(b,block). Without \
         $(b,--gate), no finding blocks. With $(b,--strict), every finding \
         that the command reports blocks, except a finding of \
         $(b,config-changed), which never blocks.";
    ]
  in
  let examples =
    [
      `S Manpage.s_examples;
      `Pre "  sinter check";
      `P "Report every finding of the working tree, with no tier.";
      `Pre "  sinter check --gate review";
      `P
        "Report the findings that matter before a merge, and exit with code 1 \
         when one of them blocks. Run this in CI on a pull request.";
      `Pre "  sinter check --diff --gate review";
      `P
        "Report only the findings that the changes since the base add, for \
         example on a pull request in a repository that has findings already.";
      `Pre "  sinter check -o brief";
      `P "Print one line for each finding.";
      `Pre "  sinter check -q -o brief";
      `P "Print one line for each finding, and no summary.";
      `Pre "  sinter check -o json";
      `P "Print the findings as JSON, for a program to read.";
    ]
  in
  let info =
    Cmd.info "check" ~doc
      ~man:(man @ exits_doc @ environment @ examples)
      ~envs ~exits:check_exits
  in
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
       the merge base of HEAD and the default branch of the manifest."
    in
    Arg.(value & opt (some string) None & info [ "base" ] ~docv:"REVISION" ~doc)
  in
  let gate =
    let doc =
      "The point at which the check runs: $(b,turn), when an agent finishes a \
       turn and hands back its work; $(b,review), on a change before it merges \
       into the default branch, for example on a pull request; or $(b,merged), \
       on the default branch after a merge."
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
      "Exit with code 1 when the command reports any finding, not only one \
       that blocks. A finding of $(b,config-changed) never counts."
    in
    Arg.(value & flag & info [ "strict" ] ~doc)
  in
  let output =
    let doc =
      "The form of the output: $(b,full), $(b,brief), or $(b,json). The full \
       form shows each finding with its source lines, the places that relate \
       to it, and its fix. The brief form gives one line for each finding, and \
       a second line for its fix. The JSON form gives one object per line, in \
       the form that $(b,sinter scan) uses: the first record describes the \
       run, as the first line of $(b,sinter scan) does, and each record after \
       it is one finding."
    in
    Arg.(
      value
      & opt
          (enum
             [
               ("full", Sinter_core.Check.Full);
               ("brief", Sinter_core.Check.Brief);
               ("json", Sinter_core.Check.Json);
             ])
          Sinter_core.Check.Full
      & info [ "o"; "output" ] ~docv:"FORM" ~doc)
  in
  let diff =
    let doc =
      "Report only the findings that the changes since the base add, and not \
       those that the base already has."
    in
    Arg.(value & flag & info [ "diff" ] ~doc)
  in
  let verbose =
    let doc =
      "List each finding, and fold none. In the full and brief forms, also \
       name the base on standard error."
    in
    Arg.(value & flag & info [ "v"; "verbose" ] ~doc)
  in
  let quiet =
    let doc =
      "Print no summary and no note on standard error. Warnings still print."
    in
    Arg.(value & flag & info [ "q"; "quiet" ] ~doc)
  in
  let run color manifest base diff gate strict form verbose quiet =
    with_phases color @@ fun phases ->
    match
      Sinter_core.Check.run ?phases ~env:(Unix.environment ())
        ~dir:(Sys.getcwd ()) ~manifest ~base
        ~mode:(if diff then Sinter_core.Mode.Diff else Sinter_core.Mode.Tree)
        ~gate ~strict ~form ~verbose ~quiet ~tool:version ()
    with
    | Error error ->
        report color (Sinter_core.Scan.explain error);
        environment_error
    | Ok outcome -> (
        match
          Sinter_core.Check.write ?phases
            (Sinter_core.Style.formatter stdout
               ~color:
                 (form <> Sinter_core.Check.Json && colored color Unix.stdout))
            outcome
        with
        | () -> (
            try
              Sinter_core.Check.notices
                (Sinter_core.Style.formatter stderr
                   ~color:(colored color Unix.stderr))
                outcome;
              Sinter_core.Check.code outcome
            with Sys_error _ -> environment_error)
        | exception Sys_error message ->
            report color [ output_failure message ];
            environment_error)
  in
  Cmd.v info
    Term.(
      const run $ color $ manifest $ base $ diff $ gate $ strict $ output
      $ verbose $ quiet)

let cmd =
  let doc = "a linter for keeping your specs, plans, and code in sync" in
  let man =
    [
      `S Manpage.s_description;
      `P
        "Sinter reads the tags in your repository's files: specs, plans, \
         decision records, and the code and tests that refer to them. It \
         reports where they have drifted apart, for example a test that checks \
         an old version of a spec, or a plan step whose promised work never \
         showed up.";
      `P
        "To start, run $(b,sinter check) in your repository. Sinter reads its \
         settings from $(i,sinter.toml) at the root.";
      `S Manpage.s_commands;
      `S plumbing;
      `P
        "These commands give other programs the facts and the parser that \
         $(b,sinter check) uses.";
      `S Manpage.s_examples;
      `Pre "  sinter check";
      `P "Report every finding of the working tree.";
      `Pre "  sinter check --gate review";
      `P
        "Report the findings that matter before a merge, and exit with code 1 \
         when one of them blocks.";
    ]
  in
  let info =
    Cmd.info "sinter" ~version ~doc ~man:(man @ environment) ~envs ~exits
  in
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
    report Sinter_core.Style.Auto
      [
        failure ~help:"run the command with its standard output open"
          "cannot write the output: standard output is closed";
      ];
    exit environment_error);
  let buffer = Buffer.create 256 in
  let err = Format.formatter_of_buffer buffer in
  Sinter_core.Style.prepare err `None;
  let code = Cmd.eval' ~err ~term_err:usage_error cmd in
  Format.pp_print_flush err ();
  if Buffer.length buffer > 0 then
    report Sinter_core.Style.Auto
      [ Sinter_core.Usage.error (Buffer.contents buffer) ];
  exit (if code = Cmd.Exit.cli_error then usage_error else code)
