(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

open Cmdliner
open Sinter_bench

exception Stop of string

let stop format = Printf.ksprintf (fun message -> raise (Stop message)) format

type platform = Linux | Macos
type counter = Perf of string | Time_l | No_count of string

type target = {
  name : string;
  root : string;
  manifest : string option;
  declarations : int option;
}

type result = {
  target : target;
  command : string;
  exit_code : int;
  samples : Measurement.sample list;
  phases : (string * int) list list;
}

let commands = [ "scan"; "check" ]
let time = "/usr/bin/time"
let read path = In_channel.with_open_bin path In_channel.input_all

let rec remove_tree path =
  match Unix.lstat path with
  | { Unix.st_kind = Unix.S_DIR; _ } ->
      Array.iter
        (fun name -> remove_tree (Filename.concat path name))
        (Sys.readdir path);
      Unix.rmdir path
  | _ -> Unix.unlink path
  | exception Unix.Unix_error (Unix.ENOENT, _, _) -> ()

let absolute path =
  if Filename.is_relative path then Filename.concat (Sys.getcwd ()) path
  else path

let spawn ?(cwd = ".") ?(env = Unix.environment ()) ~stdout ~stderr argv =
  let previous = Sys.getcwd () in
  let input = Unix.openfile "/dev/null" [ Unix.O_RDONLY ] 0 in
  let open_out path =
    Unix.openfile path [ Unix.O_WRONLY; Unix.O_CREAT; Unix.O_TRUNC ] 0o644
  in
  let output = open_out stdout in
  let errors = open_out stderr in
  Fun.protect
    ~finally:(fun () ->
      List.iter Unix.close [ input; output; errors ];
      Sys.chdir previous)
    (fun () ->
      Sys.chdir cwd;
      let pid = Unix.create_process_env argv.(0) argv env input output errors in
      match snd (Unix.waitpid [] pid) with
      | Unix.WEXITED code -> code
      | Unix.WSIGNALED signal | Unix.WSTOPPED signal -> 128 + abs signal)

let scratch =
  lazy
    (let dir = Filename.temp_dir "sinter-bench" "" in
     at_exit (fun () ->
         try remove_tree dir with Unix.Unix_error _ | Sys_error _ -> ());
     dir)

let scratch_file name = Filename.concat (Lazy.force scratch) name

let capture ?env argv =
  let output = scratch_file "capture.out"
  and errors = scratch_file "capture.err" in
  match spawn ?env ~stdout:output ~stderr:errors argv with
  | code -> (code, read output, read errors)
  | exception Unix.Unix_error (error, _, _) ->
      (127, "", Unix.error_message error)

let platform () =
  match capture [| "uname"; "-s" |] with
  | 0, "Linux\n", _ -> Linux
  | 0, "Darwin\n", _ -> Macos
  | _, output, _ ->
      stop "the benchmark measures on Linux and on macOS only, not on %s"
        (String.trim output)

let on_path program =
  List.find_map
    (fun dir ->
      let path = Filename.concat dir program in
      if dir <> "" && Sys.file_exists path then Some path else None)
    (String.split_on_char ':'
       (Option.value (Sys.getenv_opt "PATH") ~default:""))

let one_line text =
  let text =
    String.concat " "
      (List.filter
         (fun line -> not (String.equal line ""))
         (List.map String.trim (String.split_on_char '\n' text)))
  in
  if String.ends_with ~suffix:"." text then
    String.sub text 0 (String.length text - 1)
  else text

let counter = function
  | Macos -> (
      let result = scratch_file "time-probe" in
      let code, _, errors = capture [| time; "-l"; "-o"; result; "true" |] in
      if code <> 0 then No_count ("time -l failed: " ^ one_line errors)
      else
        match Measurement.bsd_time (read result) with
        | Ok { instructions = Some count; _ } when count > 0 -> Time_l
        | Ok _ -> No_count "time -l reports no instructions retired"
        | Error message -> No_count message)
  | Linux -> (
      match on_path "perf" with
      | None -> No_count "perf is not on the PATH"
      | Some perf -> (
          let result = scratch_file "perf-probe" in
          let code, _, errors =
            capture
              [|
                perf;
                "stat";
                "-x,";
                "-e";
                "instructions:u";
                "-o";
                result;
                "--";
                "true";
              |]
          in
          if code <> 0 then No_count ("perf stat failed: " ^ one_line errors)
          else
            match Measurement.perf_stat (read result) with
            | Ok (Some count) when count > 0 -> Perf perf
            | Ok (Some _ | None) -> No_count "perf counts no instructions"
            | Error message -> No_count message))

let sinter_env =
  lazy
    (Array.of_list
       (List.filter
          (fun entry -> not (String.starts_with ~prefix:"GIT_" entry))
          (Array.to_list (Unix.environment ()))
       @ [ "GIT_CONFIG_GLOBAL=/dev/null"; "GIT_CONFIG_NOSYSTEM=1" ]))

let measure ~platform ~counter ~sinter ~phases ~stdout target command =
  let times = scratch_file "time" and counts = scratch_file "perf" in
  let errors = scratch_file "errors" and words = scratch_file "words" in
  if Sys.file_exists words then Sys.remove words;
  let invocation =
    sinter :: command
    :: Option.fold ~none:[]
         ~some:(fun path -> [ "--manifest"; path ])
         target.manifest
  in
  let argv =
    match (platform, counter) with
    | Macos, _ -> time :: "-l" :: "-o" :: times :: invocation
    | Linux, Perf perf ->
        [ perf; "stat"; "-x,"; "-e"; "instructions:u"; "-o"; counts; "--" ]
        @ (time :: "-f" :: "%M" :: "-o" :: times :: "--" :: invocation)
    | Linux, (Time_l | No_count _) ->
        time :: "-f" :: "%M" :: "-o" :: times :: "--" :: invocation
  in
  let code =
    spawn ~cwd:target.root
      ~env:
        (Array.append (Lazy.force sinter_env)
           [| Sinter_core.Allocation.variable ^ "=" ^ words |])
      ~stdout ~stderr:errors (Array.of_list argv)
  in
  if code <> 0 && code <> 1 then
    stop "sinter %s on %s exited with %d:\n%s" command target.name code
      (read errors);
  let sample =
    match platform with
    | Macos -> (
        match (Measurement.bsd_time (read times), counter) with
        | Ok sample, No_count _ -> Ok { sample with instructions = None }
        | result, _ -> result)
    | Linux -> (
        match Measurement.gnu_time (read times) with
        | Error _ as error -> error
        | Ok peak_kib -> (
            let instructions =
              match counter with
              | Perf _ -> Measurement.perf_stat (read counts)
              | Time_l | No_count _ -> Ok None
            in
            match instructions with
            | Ok instructions ->
                Ok { Measurement.peak_kib; instructions; footprint_kib = None }
            | Error _ as error -> error))
  in
  match
    ( sample,
      if Sys.file_exists words then Measurement.phase_words (read words)
      else if phases then Error "it wrote no words of its phases"
      else Ok [] )
  with
  | Ok sample, Ok phases -> (code, sample, phases)
  | Error message, _ | _, Error message ->
      stop "sinter %s on %s: %s" command target.name message

let run_target ~platform ~counter ~sinter ~phases ~runs ~outputs target =
  List.map
    (fun command ->
      let first =
        match outputs with
        | Some dir ->
            Filename.concat dir (Printf.sprintf "%s-%s.out" target.name command)
        | None -> "/dev/null"
      in
      let exit_code, _, _ =
        measure ~platform ~counter ~sinter ~phases ~stdout:first target command
      in
      let measured =
        List.init runs (fun _ ->
            let code, sample, phases =
              measure ~platform ~counter ~sinter ~phases ~stdout:"/dev/null"
                target command
            in
            if code <> exit_code then
              stop "sinter %s on %s exited with %d and then with %d" command
                target.name exit_code code;
            (sample, phases))
      in
      Printf.eprintf "measured %s %s\n%!" target.name command;
      {
        target;
        command;
        exit_code;
        samples = List.map fst measured;
        phases = List.map snd measured;
      })
    commands

let tree ~generator ~trees ~seed declarations =
  let name = Printf.sprintf "n%d" declarations in
  let dir = Filename.concat trees (Printf.sprintf "%s-seed%d" name seed) in
  let root = Filename.concat dir "repo" in
  (if not (Sys.file_exists root) then
     let errors = scratch_file "generate.err" in
     let code =
       spawn ~stdout:"/dev/null" ~stderr:errors
         [|
           generator;
           "--seed";
           string_of_int seed;
           string_of_int declarations;
           dir;
         |]
     in
     if code <> 0 then
       stop "the generator exited with %d for %d declarations:\n%s" code
         declarations (read errors));
  { name; root; manifest = None; declarations = Some declarations }

let self_target ~manifest dir =
  match
    capture ~env:(Lazy.force sinter_env)
      [| "git"; "-C"; dir; "rev-parse"; "--show-toplevel" |]
  with
  | 0, output, _ ->
      {
        name = "self";
        root = String.trim output;
        manifest = Option.map absolute manifest;
        declarations = None;
      }
  | _, _, errors ->
      stop "%s is not in a git checkout: %s" dir (String.trim errors)

let summary_of values =
  match values with [] -> None | _ -> Some (Measurement.summary values)

let all_some values =
  if List.for_all Option.is_some values then List.filter_map Fun.id values
  else []

let row result =
  let samples = result.samples in
  let floats measure =
    summary_of
      (all_some
         (List.map
            (fun sample -> Option.map float_of_int (measure sample))
            samples))
  in
  {
    Report.tree = result.target.name;
    declarations = result.target.declarations;
    command = result.command;
    exit_code = result.exit_code;
    peak_kib =
      Measurement.summary
        (List.map
           (fun (sample : Measurement.sample) -> float_of_int sample.peak_kib)
           samples);
    instructions =
      floats (fun (sample : Measurement.sample) -> sample.instructions);
    footprint_kib =
      floats (fun (sample : Measurement.sample) -> sample.footprint_kib);
    phase_words =
      (match result.phases with
      | [] -> []
      | first :: _ as runs ->
          List.map
            (fun (phase, _) ->
              ( phase,
                (Measurement.summary
                   (List.map
                      (fun phases ->
                        match List.assoc_opt phase phases with
                        | Some words -> float_of_int words
                        | None ->
                            stop
                              "sinter %s on %s counted the phase %s in one run \
                               only"
                              result.command result.target.name phase)
                      runs))
                  .median ))
            first);
  }

let measure_trees ~phases ~sinter ~generator ~self ~self_manifest ~sizes ~seed
    ~runs ~trees ~outputs =
  let platform = platform () in
  if not (Sys.file_exists time) then stop "%s is missing" time;
  if not (Sys.file_exists sinter) then stop "%s is missing" sinter;
  if runs < 1 then stop "--runs is %d, and it must be 1 or more" runs;
  List.iter
    (fun size -> if size < 2 then stop "the size %d is below 2" size)
    sizes;
  let generator =
    match (generator, sizes) with
    | Some generator, _ -> Some (absolute generator)
    | None, [] -> None
    | None, _ :: _ -> stop "--generator is missing, and --sizes names trees"
  in
  let sinter = absolute sinter in
  let counter = counter platform in
  let trees =
    match trees with
    | Some dir ->
        if not (Sys.file_exists dir) then Unix.mkdir dir 0o755;
        absolute dir
    | None ->
        let dir = Filename.concat (Lazy.force scratch) "trees" in
        Unix.mkdir dir 0o755;
        dir
  in
  let outputs = Option.map absolute outputs in
  Option.iter
    (fun dir -> if not (Sys.file_exists dir) then Unix.mkdir dir 0o755)
    outputs;
  let targets =
    Option.fold ~none:[]
      ~some:(fun dir -> [ self_target ~manifest:self_manifest dir ])
      self
    @ List.concat_map
        (fun size ->
          Option.fold ~none:[]
            ~some:(fun generator -> [ tree ~generator ~trees ~seed size ])
            generator)
        sizes
  in
  let results =
    List.concat_map
      (run_target ~platform ~counter ~sinter ~phases ~runs ~outputs)
      targets
  in
  {
    Report.platform =
      (match platform with Linux -> "linux" | Macos -> "macos");
    instruction_counter =
      (match counter with
      | Perf _ -> Some "perf"
      | Time_l -> Some "time"
      | No_count _ -> None);
    no_count_reason =
      (match counter with No_count reason -> Some reason | _ -> None);
    runs;
    seed;
    rows = List.map row results;
  }

let main sinter generator self self_manifest sizes seed runs budgets trees
    outputs results json markdown =
  try
    let budgets =
      Option.map
        (fun path ->
          match Budgets.of_string (read path) with
          | Ok budgets -> budgets
          | Error message -> stop "%s: %s" path message)
        budgets
    in
    let report =
      match (results, sinter) with
      | Some path, None -> (
          match Report.of_string (read path) with
          | Ok report -> report
          | Error message -> stop "%s: %s" path message)
      | None, Some sinter ->
          measure_trees ~phases:(Option.is_some budgets) ~sinter ~generator
            ~self ~self_manifest ~sizes ~seed ~runs ~trees ~outputs
      | Some _, Some _ -> stop "--results and --sinter exclude each other"
      | None, None -> stop "either --sinter or --results is required"
    in
    let outcomes =
      Option.fold ~none:[]
        ~some:(fun budgets ->
          Budgets.check budgets
            ~linux:(String.equal report.platform "linux")
            ~peak:(Report.peak report) ~words:(Report.words report))
        budgets
    in
    let text =
      Yojson.Basic.pretty_to_string (Report.to_json report outcomes) ^ "\n"
    in
    (match json with
    | Some path ->
        Out_channel.with_open_bin path (fun channel ->
            Out_channel.output_string channel text)
    | None -> print_string text);
    let table = Report.to_markdown report outcomes in
    prerr_string table;
    Option.iter
      (fun path ->
        Out_channel.with_open_gen
          [ Open_wronly; Open_creat; Open_append; Open_binary ] 0o644 path
          (fun channel -> Out_channel.output_string channel table))
      markdown;
    if
      List.exists
        (fun (outcome : Budgets.outcome) ->
          match outcome.verdict with Fail _ -> true | _ -> false)
        outcomes
    then 1
    else 0
  with
  | Stop message ->
      Printf.eprintf "run: %s\n" message;
      2
  | Sys_error message ->
      Printf.eprintf "run: %s\n" message;
      2
  | Unix.Unix_error (error, call, path) ->
      Printf.eprintf "run: %s %s: %s\n" call path (Unix.error_message error);
      2

let () =
  let doc = "Measure the peak memory and the allocation of sinter" in
  let man =
    [
      `S Manpage.s_description;
      `P
        "Run $(i,sinter scan) and $(i,sinter check) on each tree: once to warm \
         up, and then $(b,--runs) times, each run measured. On Linux, GNU \
         $(i,time) gives the peak resident memory, and $(i,perf stat) counts \
         the instructions in user space when $(i,perf) is on the PATH and can \
         count them. On macOS, $(i,time -l) gives the peak resident memory, \
         the instructions, and the peak memory footprint.";
      `P
        "On Linux, the peak memory is the largest of the peaks of sinter and \
         of each process that it starts. The instruction count of $(i,perf \
         stat) is the sum over sinter and every process that it starts, such \
         as git. The instruction count of $(i,time -l) is that of sinter \
         alone. So a count on Linux is not comparable with a count on macOS.";
      `P
        "The trees are Sinter's own checkout, with $(b,--self), and one \
         generated tree for each size of $(b,--sizes). Each sinter process \
         runs in the root of its tree, with no git configuration of the \
         machine.";
      `P
        "Each sinter process also writes the words that the OCaml runtime \
         allocates in each phase of the command, through the environment \
         variable $(i,SINTER_PHASE_WORDS). This count is the same on every run \
         of one input at one path. A sinter that writes no such file counts no \
         phase; with $(b,--budgets), the run then stops.";
      `P
        "With $(b,--budgets), the run checks the budgets of that file. The \
         file is TOML, with the tables $(i,scan) and $(i,check). Each table \
         holds $(i,peak-memory-kib), the limit of the median peak memory on \
         the tree of 10,000 declarations on Linux, in KiB, and \
         $(i,allocation-growth), the limit, for each phase, of the words on \
         the tree of 10,000 declarations divided by the words on the tree of \
         1,000 declarations. A budget that the run cannot check is skipped: \
         the memory budget off Linux or without the tree of 10,000 \
         declarations, and the growth limit of a phase without the words of \
         the phase on both trees. The instruction counts are information only.";
      `S "OUTPUT";
      `P
        "A JSON object, on standard output or in the file of $(b,--json). Its \
         keys: $(i,platform), $(i,linux) or $(i,macos); \
         $(i,instruction_counter), $(i,perf), $(i,time), or null; \
         $(i,no_count_reason), why nothing counts the instructions, or null; \
         $(i,runs); $(i,seed); $(i,results), one object for each tree and \
         command; and $(i,budgets), one object for each budget.";
      `P
        "An object of $(i,results) holds $(i,tree) (self, or n and the number \
         of declarations), $(i,declarations) (null for self), $(i,command), \
         $(i,exit) (the exit status of sinter, 0 or 1), and $(i,peak_kib), \
         $(i,instructions), and $(i,footprint_kib), and $(i,phase_words). Each \
         of $(i,peak_kib), $(i,instructions), and $(i,footprint_kib) is null \
         when the run did not measure it, or an object with the $(i,median), \
         the $(i,min), the $(i,max), and the $(i,spread_percent), (max - min) \
         / median in percent. $(i,phase_words) is an array of objects, one for \
         each phase in its order, each with $(i,phase), the name, and \
         $(i,words), the median of the words.";
      `P
        "An object of $(i,budgets) holds $(i,command), $(i,budget) \
         ($(i,peak-memory-kib) or $(i,allocation-growth)), $(i,phase) (the \
         phase of a growth limit, or null), $(i,limit), and $(i,result): \
         $(i,pass) or $(i,fail), with the measure in $(i,value), or \
         $(i,skipped), with the cause in $(i,reason).";
      `P
        "A table in markdown goes to standard error, and is appended to the \
         file of $(b,--markdown).";
    ]
  in
  let exits =
    Cmd.Exit.info 1 ~doc:"when a budget fails."
    :: Cmd.Exit.info 2 ~doc:"when the run cannot measure."
    :: Cmd.Exit.defaults
  in
  let path_opt names docv doc =
    Arg.(value & opt (some string) None & info names ~docv ~doc)
  in
  let sinter =
    path_opt [ "sinter" ] "PATH"
      "The sinter executable to measure. Either this option or $(b,--results) \
       is required."
  in
  let results =
    path_opt [ "results" ] "PATH"
      "A JSON object that an earlier run wrote. The run reads its measures, \
       measures nothing, and checks the budgets of $(b,--budgets) against \
       them, as a run on the platform of the object would."
  in
  let generator =
    path_opt [ "generator" ] "PATH"
      "The executable that makes the generated trees. It is required when \
       $(b,--sizes) names a tree."
  in
  let self =
    path_opt [ "self" ] "DIR"
      "A folder inside Sinter's own git checkout. The run measures that \
       checkout as the tree $(i,self)."
  in
  let self_manifest =
    path_opt [ "self-manifest" ] "PATH"
      "The manifest of the tree $(i,self), instead of $(i,sinter.toml) at its \
       root."
  in
  let sizes =
    Arg.(
      value
      & opt (list int) [ 1000; 10000 ]
      & info [ "sizes" ] ~docv:"N,..."
          ~doc:
            "The numbers of declarations of the generated trees, each 2 or \
             more. An empty list measures no generated tree.")
  in
  let seed =
    Arg.(
      value & opt int 1
      & info [ "seed" ] ~docv:"SEED" ~doc:"The seed of the generated trees.")
  in
  let runs =
    Arg.(
      value & opt int 5
      & info [ "runs" ] ~docv:"COUNT"
          ~doc:"The number of measured runs of each command on each tree.")
  in
  let budgets =
    path_opt [ "budgets" ] "PATH"
      "The budgets file to check the medians against."
  in
  let trees =
    path_opt [ "trees" ] "DIR"
      "The folder of the generated trees. The run uses a tree that it finds \
       there, and makes a tree that is missing. Without this option, the trees \
       go to a new temporary folder that the run removes at its end."
  in
  let outputs =
    path_opt [ "outputs" ] "DIR"
      "A folder for the standard output of the first run of each command on \
       each tree, in the file <tree>-<command>.out."
  in
  let json = path_opt [ "json" ] "PATH" "The file for the JSON object." in
  let markdown =
    path_opt [ "markdown" ] "PATH" "A file to append the markdown table to."
  in
  exit
    (Cmd.eval'
       (Cmd.v
          (Cmd.info "run" ~doc ~man ~exits)
          Term.(
            const main $ sinter $ generator $ self $ self_manifest $ sizes
            $ seed $ runs $ budgets $ trees $ outputs $ results $ json
            $ markdown)))
