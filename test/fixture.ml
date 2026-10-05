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
  | Did_not_end of float
  | Ended_by_signal of int
  | Git_failed of { arguments : string list; output : string }
  | System of string
  | Differs of difference list

type mode = Compare | Promote_into of string

let ( let* ) = Result.bind

(* The entries of a case folder. The harness does not read the two
   reserved entries yet. *)
let known = [ "args"; "tree"; "base"; "stdin"; "expected" ]
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
          "unknown entry %s. A case folder holds only args, tree, base, stdin, \
           and expected."
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

(* [Sys.is_directory] and [read_file] follow a symbolic link, so the
   copy holds the bytes of a link's target and never a link. In the
   build copy of a case, which the suite reads, dune has already
   replaced each link of the source tree with such a file. A file
   named .gitkeep only keeps an empty folder in git: the copy leaves
   the file out and keeps its folder. [target] exists and is empty. *)
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

(* Removes [path] and, for a folder, everything in it. A symbolic
   link is removed, not followed. *)
let rec remove path =
  match (Unix.lstat path).Unix.st_kind with
  | Unix.S_DIR ->
      List.iter (fun name -> remove (Filename.concat path name)) (entries path);
      Unix.rmdir path
  | _ -> Sys.remove path

let make_folder parent name =
  let path = Filename.concat parent name in
  Sys.mkdir path 0o755;
  path

(* Calls [f] with the real path of a new, empty folder under the
   temporary folder, and removes the folder when [f] returns or
   raises. *)
let with_temporary_folder f =
  let made = Filename.temp_dir "sinter-case" "" in
  Fun.protect
    ~finally:(fun () -> remove made)
    (fun () -> f (Unix.realpath made))

(* Turns a failure of the file system or of a process into an error
   value. *)
let guarded f =
  try f () with
  | Sys_error reason -> Error (System reason)
  | Unix.Unix_error (code, call, argument) ->
      Error
        (System
           (Printf.sprintf "%s %s: %s" call argument (Unix.error_message code)))
  | Fun.Finally_raised failure -> Error (System (Printexc.to_string failure))

(* Every git command, and the run itself, gets the environment of
   the suite with the variables below taken out and set anew. Git
   reads its configuration, its ignore rules, and its identity from
   them and from files under HOME and XDG_CONFIG_HOME, so the fixed
   values give the same commit id and the same output of git on every
   machine. Cmdliner colors its own errors when TERM names a terminal,
   and NO_COLOR stops that. PWD names [root], the folder where each
   of them starts. The other variables of the suite stay: the mutation
   runner switches a mutant on in the run through one of them. *)
let environment ~home ~root =
  let replaced binding =
    List.exists
      (fun prefix -> String.starts_with ~prefix binding)
      [ "GIT_"; "HOME="; "XDG_CONFIG_HOME="; "NO_COLOR="; "PWD=" ]
  in
  Array.append
    (Array.of_list
       (List.filter
          (fun binding -> not (replaced binding))
          (Array.to_list (Unix.environment ()))))
    [|
      "HOME=" ^ home;
      "PWD=" ^ root;
      "NO_COLOR=1";
      "GIT_CONFIG_GLOBAL=/dev/null";
      "GIT_CONFIG_NOSYSTEM=1";
      "GIT_AUTHOR_NAME=Sinter Fixture";
      "GIT_AUTHOR_EMAIL=fixture@sinter.invalid";
      "GIT_AUTHOR_DATE=1767225600 +0000";
      "GIT_COMMITTER_NAME=Sinter Fixture";
      "GIT_COMMITTER_EMAIL=fixture@sinter.invalid";
      "GIT_COMMITTER_DATE=1767225600 +0000";
    |]

(* Waits [bound] seconds at most for [pid] to end, and kills it after. *)
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

(* Starts [program] with [arguments] in the folder [folder], with
   standard input from the file [input], and standard output and
   standard error to the files [output] and [errors]. A new process
   starts in the working folder of this process, so the start changes
   into [folder] and back. No other thread or domain may run
   meanwhile. *)
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

(* The folders of one run, all in one temporary folder: the working
   folder where the run starts, a home folder, and room for the
   captured output. The home folder and the captured output sit beside
   the working folder, so that the working folder holds only the files
   of the case. *)
type workspace = { root : string; environment : string array; scratch : string }

let prepare temporary =
  let home = make_folder temporary "home" in
  let root = make_folder temporary "work" in
  { root; environment = environment ~home ~root; scratch = temporary }

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

(* The git program in the folder that git --exec-path names, or "git"
   when the lookup fails. The lookup runs in the suite's own
   environment. *)
let program workspace =
  let output = Filename.concat workspace.scratch "exec-path"
  and errors = Filename.concat workspace.scratch "exec-path-errors" in
  match
    execute ~environment:(Unix.environment ()) ~folder:workspace.scratch
      ~input:"/dev/null" ~output ~errors ~bound:10. "git" [ "--exec-path" ]
  with
  | Ok 0 ->
      let path = Filename.concat (String.trim (read_file output)) "git" in
      if Sys.file_exists path then path else "git"
  | Ok _ | Error _ -> "git"

(* [workspace.root] exists and is empty. *)
let build workspace ~base ~tree =
  let repository = { workspace; program = program workspace } in
  let* _ =
    git repository
      [ "init"; "--quiet"; "--template="; "--object-format=sha1"; "-b"; "main" ]
  in
  copy_folder base workspace.root;
  let* _ = git repository [ "add"; "--all" ] in
  let* _ =
    git repository [ "commit"; "--quiet"; "--allow-empty"; "--message=base" ]
  in
  List.iter
    (fun name ->
      if not (String.equal name ".git") then
        remove (Filename.concat workspace.root name))
    (entries workspace.root);
  copy_folder tree workspace.root;
  Ok repository

let with_repository ~base ~tree f =
  with_temporary_folder (fun temporary ->
      let* repository =
        guarded (fun () -> build (prepare temporary) ~base ~tree)
      in
      Ok (f repository))

type layout = {
  args : string;
  tree : string;
  base : string option;
  stdin : string option;
  expected : string;
}

(* The path of [entry] in [case] when it exists. *)
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
    let* tree = find case "tree" ~folder:true in
    let* tree = required "tree" tree in
    let* base = find case "base" ~folder:true in
    let* stdin = find case "stdin" ~folder:false in
    let* expected = find case "expected" ~folder:true in
    let* () =
      match expected with
      | None -> Ok ()
      | Some folder ->
          first_unknown ~prefix:"expected/" outputs (entries folder)
    in
    let* () =
      (* A promotion writes a missing expected file; a comparison needs
         all three. *)
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
    Ok { args; tree; base; stdin; expected = Filename.concat case "expected" }

(* Each line is one argument. The line feed that ends the file ends
   the last argument, so an empty file holds no argument and a file
   that holds one line feed holds one empty argument. *)
let arguments text =
  if String.equal text "" then []
  else
    let pieces = String.split_on_char '\n' text in
    match List.rev pieces with "" :: rest -> List.rev rest | _ -> pieces

(* The lines of [text], each with its line feed. The last line has no
   line feed when [text] does not end with one. The lines joined give
   [text] back. *)
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

(* Every occurrence of [pattern] in [text], replaced with [by]. *)
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

let run ?(bound = 10.) ~binary mode case =
  if Filename.is_relative binary then
    invalid_arg "Fixture.run: the binary is not an absolute path";
  guarded (fun () ->
      let* layout = read_layout mode case in
      let arguments = arguments (read_file layout.args) in
      with_temporary_folder (fun temporary ->
          let workspace = prepare temporary in
          let* () =
            match layout.base with
            | None -> Ok (copy_folder layout.tree workspace.root)
            | Some base ->
                let* _ = build workspace ~base ~tree:layout.tree in
                Ok ()
          in
          let output = Filename.concat temporary "stdout"
          and errors = Filename.concat temporary "stderr" in
          let* code =
            execute ~environment:workspace.environment ~folder:workspace.root
              ~input:(Option.value layout.stdin ~default:"/dev/null")
              ~output ~errors ~bound binary arguments
          in
          (* The run starts in the real path of its working folder, so
             an absolute path that the run prints holds that real path.
             The comparison replaces that path with <root>, and changes
             nothing else in the output. *)
          let rooted path =
            replace_all ~pattern:workspace.root ~by:"<root>" (read_file path)
          in
          settle mode ~name:(Filename.basename case) ~expected:layout.expected
            [
              ("stdout", rooted output);
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
