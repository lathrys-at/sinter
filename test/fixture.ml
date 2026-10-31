(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

type difference = {
  file : string;
  line : int;
  expected : string option;
  actual : string option;
}

type error =
  | Not_a_folder
  | Unknown_entry of string
  | Missing_entry of string
  | Wrong_kind of { entry : string; folder : bool }
  | Reserved_entry of string
  | Repository_with_base
  | Bad_variable of string
  | Did_not_end of float
  | Ended_by_signal of int
  | Git_failed of { arguments : string list; output : string }
  | System of string
  | Differs of difference list

type mode = Compare | Promote_into of string

let ( let* ) = Result.bind
let known = [ "args"; "env"; "tree"; "base"; "repository"; "stdin"; "expected" ]
let reserved = [ "ledger.jsonl"; "evidence" ]
let outputs = [ "stdout"; "stderr"; "exit" ]

let message ~case error =
  let show = function
    | None -> "(no such line)"
    | Some line -> Printf.sprintf "%S" line
  in
  let text =
    match error with
    | Not_a_folder ->
        "not a folder. Each entry of the folder of cases is a case folder."
    | Unknown_entry entry when String.starts_with ~prefix:"expected/" entry ->
        Printf.sprintf
          "unknown entry %s. The folder expected holds only stdout, stderr, \
           and exit."
          entry
    | Unknown_entry entry ->
        Printf.sprintf
          "unknown entry %s. A case folder holds only args, env, tree, base, \
           repository, stdin, and expected."
          entry
    | Missing_entry entry when String.starts_with ~prefix:"expected/" entry ->
        Printf.sprintf
          "the entry %s is missing. Write it, or run the suite with \
           SINTER_PROMOTE=1 to write it."
          entry
    | Missing_entry entry -> Printf.sprintf "the entry %s is missing." entry
    | Wrong_kind { entry; folder = true } ->
        Printf.sprintf "%s must be a folder." entry
    | Wrong_kind { entry; folder = false } ->
        Printf.sprintf "%s must be a file." entry
    | Reserved_entry entry ->
        Printf.sprintf
          "%s is a reserved name. The harness does not read it yet, so the \
           case cannot use it. Remove it."
          entry
    | Repository_with_base ->
        "the case holds both base and repository. A case with base already \
         runs in a repository; remove repository."
    | Bad_variable line ->
        Printf.sprintf
          "the line %S of env is not NAME=value, with a name that is not empty."
          line
    | Did_not_end bound ->
        Printf.sprintf "the run did not end within %g seconds, and was killed."
          bound
    | Ended_by_signal signal ->
        Printf.sprintf "a signal ended the run (OCaml signal number %d)." signal
    | Git_failed { arguments; output } ->
        Printf.sprintf "git %s failed:\n%s" (String.concat " " arguments) output
    | System reason -> reason
    | Differs differences ->
        "the output differs from the expected files."
        ^ String.concat ""
            (List.map
               (fun { file; line; expected; actual } ->
                 Printf.sprintf
                   "\nexpected/%s, line %d:\n  expected: %s\n  actual:   %s"
                   file line (show expected) (show actual))
               differences)
        ^ "\nTo accept the output, run the suite with SINTER_PROMOTE=1."
  in
  Printf.sprintf "case %s: %s" case text

let mode_of_environment ~promote ~source_root =
  match (promote, source_root) with
  | Some "1", Some root ->
      Ok (Promote_into (Filename.concat (Filename.concat root "test") "cases"))
  | Some "1", None ->
      Error
        "SINTER_PROMOTE is 1, but DUNE_SOURCEROOT is not set, so the suite \
         cannot find the cases in the source tree. Run the suite with dune \
         test."
  | _ -> Ok Compare

let entries folder =
  List.sort String.compare (Array.to_list (Sys.readdir folder))

let read_file path = In_channel.with_open_bin path In_channel.input_all

let write_file path text =
  Out_channel.with_open_bin path (fun channel ->
      Out_channel.output_string channel text)

let rec copy_folder source target =
  List.iter
    (fun name ->
      let from = Filename.concat source name
      and into = Filename.concat target name in
      if Sys.is_directory from then (
        Sys.mkdir into 0o755;
        copy_folder from into)
      else if not (String.equal name ".gitkeep") then
        write_file into (read_file from))
    (entries source)

let rec remove path =
  match (Unix.lstat path).Unix.st_kind with
  | Unix.S_DIR ->
      List.iter (fun name -> remove (Filename.concat path name)) (entries path);
      Unix.rmdir path
  | _ -> Sys.remove path
  | exception Unix.Unix_error (Unix.ENOENT, _, _) -> ()

let make_folder parent name =
  let path = Filename.concat parent name in
  Sys.mkdir path 0o755;
  path

let with_temporary_folder f =
  let made = Filename.temp_dir "sinter-case" "" in
  Fun.protect
    ~finally:(fun () -> remove made)
    (fun () -> f (Unix.realpath made))

let guarded f =
  try f () with
  | Sys_error reason -> Error (System reason)
  | Unix.Unix_error (code, call, argument) ->
      Error
        (System
           (Printf.sprintf "%s %s: %s" call argument (Unix.error_message code)))
  | Fun.Finally_raised failure -> Error (System (Printexc.to_string failure))

let coverage_prefix = Filename.concat (Sys.getcwd ()) "bisect"

let environment ~caller ~home ~root ~git =
  let replaced binding =
    List.exists
      (fun prefix -> String.starts_with ~prefix binding)
      [
        "GIT_";
        "HOME=";
        "XDG_CONFIG_HOME=";
        "PWD=";
        "PATH=";
        "NO_COLOR=";
        "CLICOLOR_FORCE=";
        "FORCE_COLOR=";
        "CLICOLOR=";
        "TERM=";
      ]
  in
  let suite = Array.to_list caller in
  let path =
    let folders =
      Option.to_list (Sys.getenv_opt "PATH")
      |> List.filter (fun folders -> not (String.equal folders ""))
    in
    if Filename.is_relative git then folders
    else Filename.dirname git :: folders
  in
  let coverage =
    if List.exists (String.starts_with ~prefix:"BISECT_FILE=") suite then []
    else [ "BISECT_FILE=" ^ coverage_prefix ]
  in
  Array.append
    (Array.of_list
       (List.filter (fun binding -> not (replaced binding)) suite @ coverage))
    [|
      "HOME=" ^ home;
      "PATH=" ^ String.concat ":" path;
      "PWD=" ^ root;
      "GIT_CEILING_DIRECTORIES=" ^ Filename.dirname root;
      "GIT_CONFIG_GLOBAL=/dev/null";
      "GIT_CONFIG_NOSYSTEM=1";
      "GIT_CONFIG_COUNT=1";
      "GIT_CONFIG_KEY_0=maintenance.auto";
      "GIT_CONFIG_VALUE_0=false";
      "GIT_AUTHOR_NAME=Sinter Fixture";
      "GIT_AUTHOR_EMAIL=fixture@sinter.invalid";
      "GIT_AUTHOR_DATE=1767225600 +0000";
      "GIT_COMMITTER_NAME=Sinter Fixture";
      "GIT_COMMITTER_EMAIL=fixture@sinter.invalid";
      "GIT_COMMITTER_DATE=1767225600 +0000";
    |]

let wait pid ~bound =
  let deadline = Unix.gettimeofday () +. bound in
  let rec loop () =
    match Unix.waitpid [ Unix.WNOHANG ] pid with
    | 0, _ when Unix.gettimeofday () >= deadline ->
        Unix.kill pid Sys.sigkill;
        ignore (Unix.waitpid [] pid);
        Error (Did_not_end bound)
    | 0, _ ->
        Unix.sleepf 0.001;
        loop ()
    | _, Unix.WEXITED code -> Ok code
    | _, (Unix.WSIGNALED signal | Unix.WSTOPPED signal) ->
        Error (Ended_by_signal signal)
  in
  loop ()

let execute ~environment ~folder ~input ~output ~errors ~bound program arguments
    =
  let command = Array.of_list (program :: arguments) in
  let opened = ref [] in
  let open_file path flags =
    let descriptor = Unix.openfile path (Unix.O_CLOEXEC :: flags) 0o600 in
    opened := descriptor :: !opened;
    descriptor
  in
  Fun.protect
    ~finally:(fun () -> List.iter Unix.close !opened)
    (fun () ->
      let from_input = open_file input [ Unix.O_RDONLY ] in
      let to_output =
        open_file output [ Unix.O_WRONLY; Unix.O_CREAT; Unix.O_TRUNC ]
      in
      let to_errors =
        open_file errors [ Unix.O_WRONLY; Unix.O_CREAT; Unix.O_TRUNC ]
      in
      let previous = Sys.getcwd () in
      Sys.chdir folder;
      let pid =
        Fun.protect
          ~finally:(fun () -> Sys.chdir previous)
          (fun () ->
            Unix.create_process_env program command environment from_input
              to_output to_errors)
      in
      wait pid ~bound)

type workspace = { root : string; environment : string array; scratch : string }

let wasmtime_cache =
  lazy
    (let folder = Unix.realpath (Filename.temp_dir "sinter-wasmtime" "") in
     at_exit (fun () ->
         try remove folder with Sys_error _ | Unix.Unix_error _ -> ());
     folder)

let toml_string text =
  let buffer = Buffer.create (String.length text + 2) in
  Buffer.add_char buffer '"';
  String.iter
    (fun character ->
      match character with
      | '"' | '\\' ->
          Buffer.add_char buffer '\\';
          Buffer.add_char buffer character
      | '\000' .. '\031' | '\127' ->
          Buffer.add_string buffer
            (Printf.sprintf "\\u%04X" (Char.code character))
      | _ -> Buffer.add_char buffer character)
    text;
  Buffer.add_char buffer '"';
  Buffer.contents buffer

let wasmtime_configurations =
  [
    [ "Library"; "Application Support"; "BytecodeAlliance.wasmtime" ];
    [ ".config"; "wasmtime" ];
  ]

let configure_wasmtime home =
  let text =
    Printf.sprintf "[cache]\ndirectory = %s\n"
      (toml_string (Lazy.force wasmtime_cache))
  in
  List.iter
    (fun names ->
      let folder = List.fold_left make_folder home names in
      write_file (Filename.concat folder "config.toml") text)
    wasmtime_configurations

let program =
  lazy
    (try
       with_temporary_folder (fun scratch ->
           let output = Filename.concat scratch "exec-path"
           and errors = Filename.concat scratch "exec-path-errors" in
           match
             execute ~environment:(Unix.environment ()) ~folder:scratch
               ~input:"/dev/null" ~output ~errors ~bound:10. "git"
               [ "--exec-path" ]
           with
           | Ok 0 ->
               let path =
                 Filename.concat (String.trim (read_file output)) "git"
               in
               if Sys.file_exists path then path else "git"
           | Ok _ | Error _ -> "git")
     with Sys_error _ | Unix.Unix_error _ | Fun.Finally_raised _ -> "git")

let prepare ?(caller = Unix.environment ()) temporary =
  let home = make_folder temporary "home" in
  configure_wasmtime home;
  let root = make_folder temporary "work" in
  {
    root;
    environment = environment ~caller ~home ~root ~git:(Lazy.force program);
    scratch = temporary;
  }

type repository = { workspace : workspace; program : string }

let root repository = repository.workspace.root

let git repository arguments =
  let { root; environment; scratch } = repository.workspace in
  let output = Filename.concat scratch "git-stdout"
  and errors = Filename.concat scratch "git-stderr" in
  let* code =
    execute ~environment ~folder:root ~input:"/dev/null" ~output ~errors
      ~bound:10. repository.program arguments
  in
  if code = 0 then Ok (read_file output)
  else
    Error
      (Git_failed { arguments; output = read_file output ^ read_file errors })

let initialize workspace =
  let repository = { workspace; program = Lazy.force program } in
  let* _ =
    git repository
      [ "init"; "--quiet"; "--template="; "--object-format=sha1"; "-b"; "main" ]
  in
  Ok repository

let commit_all repository ~message =
  let* _ = git repository [ "add"; "--all" ] in
  let* _ =
    git repository
      [ "commit"; "--quiet"; "--allow-empty"; "--message=" ^ message ]
  in
  Ok ()

let build workspace ~base ~tree =
  let* repository = initialize workspace in
  copy_folder base workspace.root;
  let* () = commit_all repository ~message:"base" in
  List.iter
    (fun name ->
      if not (String.equal name ".git") then
        remove (Filename.concat workspace.root name))
    (entries workspace.root);
  copy_folder tree workspace.root;
  Ok repository

let build_committed workspace ~tree =
  let* repository = initialize workspace in
  copy_folder tree workspace.root;
  let* () = commit_all repository ~message:"tree" in
  Ok repository

let with_repository ~base ~tree f =
  with_temporary_folder (fun temporary ->
      let* repository =
        guarded (fun () -> build (prepare temporary) ~base ~tree)
      in
      Ok (f repository))

type layout = {
  args : string;
  env : string option;
  tree : string;
  base : string option;
  repository : bool;
  stdin : string option;
  expected : string;
}

let find case entry ~folder =
  let path = Filename.concat case entry in
  if not (Sys.file_exists path) then Ok None
  else if Bool.equal (Sys.is_directory path) folder then Ok (Some path)
  else Error (Wrong_kind { entry; folder })

let required entry = function
  | Some path -> Ok path
  | None -> Error (Missing_entry entry)

let first_unknown ~prefix allowed names =
  match List.find_opt (fun name -> not (List.mem name allowed)) names with
  | Some name -> Error (Unknown_entry (prefix ^ name))
  | None -> Ok ()

let read_layout mode case =
  if not (Sys.file_exists case && Sys.is_directory case) then Error Not_a_folder
  else
    let names = entries case in
    let* () = first_unknown ~prefix:"" (known @ reserved) names in
    let* () =
      match List.find_opt (fun name -> List.mem name reserved) names with
      | Some name -> Error (Reserved_entry name)
      | None -> Ok ()
    in
    let* args = find case "args" ~folder:false in
    let* args = required "args" args in
    let* env = find case "env" ~folder:false in
    let* tree = find case "tree" ~folder:true in
    let* tree = required "tree" tree in
    let* base = find case "base" ~folder:true in
    let* repository = find case "repository" ~folder:false in
    let* () =
      match (base, repository) with
      | Some _, Some _ -> Error Repository_with_base
      | _ -> Ok ()
    in
    let* stdin = find case "stdin" ~folder:false in
    let* expected = find case "expected" ~folder:true in
    let* () =
      match expected with
      | None -> Ok ()
      | Some folder ->
          first_unknown ~prefix:"expected/" outputs (entries folder)
    in
    let* () =
      List.fold_left
        (fun checked file ->
          let* () = checked in
          let entry = "expected/" ^ file in
          let* path = find case entry ~folder:false in
          match (path, mode) with
          | None, Compare -> Error (Missing_entry entry)
          | _ -> Ok ())
        (Ok ()) outputs
    in
    Ok
      {
        args;
        env;
        tree;
        base;
        repository = Option.is_some repository;
        stdin;
        expected = Filename.concat case "expected";
      }

let arguments text =
  if String.equal text "" then []
  else
    let pieces = String.split_on_char '\n' text in
    match List.rev pieces with "" :: rest -> List.rev rest | _ -> pieces

let variables text =
  List.fold_right
    (fun line found ->
      let* found = found in
      match String.index_opt line '=' with
      | Some 0 | None -> Error (Bad_variable line)
      | Some _ -> Ok (line :: found))
    (arguments text) (Ok [])

let lines text =
  let length = String.length text in
  let rec split start found =
    if start >= length then List.rev found
    else
      match String.index_from_opt text start '\n' with
      | Some stop ->
          split (stop + 1) (String.sub text start (stop - start + 1) :: found)
      | None -> List.rev (String.sub text start (length - start) :: found)
  in
  split 0 []

let first_difference ~file expected actual =
  let head = function [] -> None | line :: _ -> Some line in
  let rec find line expected actual =
    match (expected, actual) with
    | e :: expected, a :: actual when String.equal e a ->
        find (line + 1) expected actual
    | [], [] -> None
    | expected, actual ->
        Some { file; line; expected = head expected; actual = head actual }
  in
  if String.equal expected actual then None
  else find 1 (lines expected) (lines actual)

let replace_all ~pattern ~by text =
  let length = String.length text and size = String.length pattern in
  let buffer = Buffer.create length in
  let rec matches_at index offset =
    offset >= size
    || Char.equal text.[index + offset] pattern.[offset]
       && matches_at index (offset + 1)
  in
  let rec scan index =
    if index > length - size then
      Buffer.add_substring buffer text index (length - index)
    else if matches_at index 0 then (
      Buffer.add_string buffer by;
      scan (index + size))
    else (
      Buffer.add_char buffer text.[index];
      scan (index + 1))
  in
  if size = 0 then text
  else (
    scan 0;
    Buffer.contents buffer)

let find_from text ~pattern start =
  let length = String.length text and size = String.length pattern in
  let rec scan index =
    if index > length - size then None
    else if String.equal (String.sub text index size) pattern then Some index
    else scan (index + 1)
  in
  scan start

let mask_line line =
  let key = "\"tool\":\"" in
  match
    ( find_from line ~pattern:"\"kind\":\"index\"" 0,
      find_from line ~pattern:key 0 )
  with
  | Some _, Some start ->
      let value = start + String.length key in
      let rec close index =
        if index >= String.length line then None
        else
          match line.[index] with
          | '\\' -> close (index + 2)
          | '"' -> Some index
          | _ -> close (index + 1)
      in
      Option.fold ~none:line
        ~some:(fun stop ->
          String.sub line 0 value ^ "<tool>"
          ^ String.sub line stop (String.length line - stop))
        (close value)
  | _ -> line

let tool_header = "# tool "

let mask_header text =
  let length = String.length text in
  let buffer = Buffer.create length in
  let rec item_end index =
    if index >= length || text.[index] = '\n' || text.[index] = '\000' then
      index
    else item_end (index + 1)
  in
  let rec scan index =
    if index < length then
      if
        (index = 0 || text.[index - 1] = '\n' || text.[index - 1] = '\000')
        && index + String.length tool_header <= length
        && String.equal
             (String.sub text index (String.length tool_header))
             tool_header
      then (
        Buffer.add_string buffer tool_header;
        Buffer.add_string buffer "<tool>";
        scan (item_end (index + String.length tool_header)))
      else (
        Buffer.add_char buffer text.[index];
        scan (index + 1))
  in
  scan 0;
  Buffer.contents buffer

let mask_tool text =
  mask_header (String.concat "" (List.map mask_line (lines text)))

let settle mode ~name ~expected actual =
  match mode with
  | Compare ->
      let differences =
        List.filter_map
          (fun (file, text) ->
            first_difference ~file
              (read_file (Filename.concat expected file))
              text)
          actual
      in
      if differences = [] then Ok [] else Error (Differs differences)
  | Promote_into source ->
      let folder = Filename.concat (Filename.concat source name) "expected" in
      Ok
        (List.filter_map
           (fun (file, text) ->
             let path = Filename.concat folder file in
             if Sys.file_exists path && String.equal (read_file path) text then
               None
             else (
               if not (Sys.file_exists folder) then Sys.mkdir folder 0o755;
               write_file path text;
               Some path))
           actual)

let run ?(bound = 10.) ?caller ~binary mode case =
  if Filename.is_relative binary then
    invalid_arg "Fixture.run: the binary is not an absolute path";
  guarded (fun () ->
      let* layout = read_layout mode case in
      let arguments = arguments (read_file layout.args) in
      let* variables =
        match layout.env with
        | None -> Ok []
        | Some path -> variables (read_file path)
      in
      with_temporary_folder (fun temporary ->
          let workspace = prepare ?caller temporary in
          let* () =
            match (layout.base, layout.repository) with
            | None, false -> Ok (copy_folder layout.tree workspace.root)
            | None, true ->
                let* _ = build_committed workspace ~tree:layout.tree in
                Ok ()
            | Some base, _ ->
                let* _ = build workspace ~base ~tree:layout.tree in
                Ok ()
          in
          let output = Filename.concat temporary "stdout"
          and errors = Filename.concat temporary "stderr" in
          let* code =
            execute
              ~environment:
                (Array.append workspace.environment (Array.of_list variables))
              ~folder:workspace.root
              ~input:(Option.value layout.stdin ~default:"/dev/null")
              ~output ~errors ~bound binary arguments
          in
          let rooted path =
            replace_all ~pattern:workspace.root ~by:"<root>" (read_file path)
          in
          settle mode ~name:(Filename.basename case) ~expected:layout.expected
            [
              ("stdout", mask_tool (rooted output));
              ("stderr", rooted errors);
              ("exit", Printf.sprintf "%d\n" code);
            ]))

let tests ~binary mode ~on_write folder =
  match entries folder with
  | exception Sys_error reason ->
      [ Alcotest.test_case "cases" `Quick (fun () -> Alcotest.fail reason) ]
  | names ->
      List.map
        (fun name ->
          Alcotest.test_case name `Quick (fun () ->
              match run ~binary mode (Filename.concat folder name) with
              | Ok written -> List.iter on_write written
              | Error error -> Alcotest.fail (message ~case:name error)))
        names
