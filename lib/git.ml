(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

type error =
  | Git_not_found of string
  | Not_a_repository of { dir : string; detail : string }
  | Bad_revision of string
  | Target_not_found of string
  | No_merge_base of string * string
  | Command_failed of {
      args : string list;
      status : Unix.process_status;
      stderr : string;
    }
  | Malformed_output of { args : string list; detail : string }
  | File_error of string

type object_format = Sha1 | Sha256

(* [env] is the environment of every child, with the changes that
   [open_repo] makes already in it. [git] is the absolute path of the
   executable. *)
type t = {
  root : string;
  git : string;
  env : string array;
  format : object_format;
}

let root t = t.root
let object_format t = t.format
let ( let* ) = Result.bind

module Decode = struct
  type kind = Blob | Tree | Commit | Tag

  let is_hex_digit = function '0' .. '9' | 'a' .. 'f' -> true | _ -> false

  let is_object_id s =
    let length = String.length s in
    (length = 40 || length = 64) && String.for_all is_hex_digit s

  let ends_with byte s =
    let length = String.length s in
    length > 0 && s.[length - 1] = byte

  let without_last s = String.sub s 0 (String.length s - 1)

  let nul_list output =
    if output = "" then Ok []
    else if ends_with '\000' output then
      Ok (String.split_on_char '\000' (without_last output))
    else Error "the output does not end with a NUL byte"

  let line output =
    if ends_with '\n' output then Ok (without_last output)
    else Error "the output does not end with a line feed"

  let object_id output =
    let* id = line output in
    if is_object_id id then Ok id
    else Error (Printf.sprintf "%S is not an object id" id)

  let repository output =
    match String.index_opt output '\n' with
    | None -> Error "the output holds no line feed"
    | Some newline ->
        let format = String.sub output 0 newline in
        let rest =
          String.sub output (newline + 1) (String.length output - newline - 1)
        in
        let* root = line rest in
        let* format =
          match format with
          | "sha1" -> Ok Sha1
          | "sha256" -> Ok Sha256
          | _ -> Error (Printf.sprintf "%S is not an object format" format)
        in
        if Filename.is_relative root then
          Error (Printf.sprintf "the root %S is not an absolute path" root)
        else Ok (format, root)

  let mode field =
    if
      String.length field = 6
      && String.for_all (function '0' .. '7' -> true | _ -> false) field
    then int_of_string_opt ("0o" ^ field)
    else None

  let kind = function
    | "blob" -> Some Blob
    | "tree" -> Some Tree
    | "commit" -> Some Commit
    | "tag" -> Some Tag
    | _ -> None

  (* [split_record record] is the part of [record] in front of its first
     tab, split at each space, and the part after that tab. *)
  let split_record record =
    match String.index_opt record '\t' with
    | None -> None
    | Some tab ->
        let fields = String.split_on_char ' ' (String.sub record 0 tab) in
        let path =
          String.sub record (tab + 1) (String.length record - tab - 1)
        in
        Some (fields, path)

  let all decode records =
    List.fold_right
      (fun record rest ->
        let* rest = rest in
        let* value = decode record in
        Ok (value :: rest))
      records (Ok [])

  type stage_entry = { mode : int; id : string; stage : int; path : string }

  let stage_entry record =
    let entry =
      match split_record record with
      | Some ([ mode_field; id; stage_field ], path)
        when is_object_id id && path <> "" -> (
          match (mode mode_field, stage_field) with
          | Some mode, ("0" | "1" | "2" | "3") ->
              Some { mode; id; stage = int_of_string stage_field; path }
          | _ -> None)
      | _ -> None
    in
    Option.to_result entry
      ~none:(Printf.sprintf "%S is not an entry of git ls-files -s" record)

  let ls_files_stage output =
    let* records = nul_list output in
    all stage_entry records

  type tree_entry = { mode : int; kind : kind; id : string; path : string }

  let tree_entry record =
    let entry =
      match split_record record with
      | Some ([ mode_field; kind_field; id ], path)
        when is_object_id id && path <> "" -> (
          match (mode mode_field, kind kind_field) with
          | Some mode, Some kind -> Some { mode; kind; id; path }
          | _ -> None)
      | _ -> None
    in
    Option.to_result entry
      ~none:(Printf.sprintf "%S is not an entry of git ls-tree" record)

  let ls_tree output =
    let* records = nul_list output in
    all tree_entry records

  type batch_header =
    | Object of { id : string; kind : kind; size : int }
    | Missing of string

  let size field =
    if
      field <> ""
      && String.for_all (function '0' .. '9' -> true | _ -> false) field
    then int_of_string_opt field
    else None

  let batch_header header =
    let decoded =
      match String.split_on_char ' ' header with
      | [ id; kind_field; size_field ] when is_object_id id -> (
          match (kind kind_field, size size_field) with
          | Some kind, Some size -> Some (Object { id; kind; size })
          | _ -> None)
      | [ name; ("missing" | "ambiguous") ] when name <> "" ->
          Some (Missing name)
      | _ -> None
    in
    Option.to_result decoded
      ~none:(Printf.sprintf "%S is not a header of git cat-file --batch" header)
end

(* Processes. *)

let file_error path error =
  File_error (Printf.sprintf "%s: %s" path (Unix.error_message error))

let remove_quietly path = try Sys.remove path with Sys_error _ -> ()

(* [with_temp_file suffix f] calls [f] with the path of a new empty file,
   and removes the file when [f] returns or raises. *)
let with_temp_file suffix f =
  match Filename.temp_file "sinter-git" suffix with
  | exception Sys_error message -> Error (File_error message)
  | path ->
      Fun.protect ~finally:(fun () -> remove_quietly path) (fun () -> f path)

(* [with_fd path flags f] calls [f] with a descriptor of the file at
   [path], and closes it when [f] returns or raises. *)
let with_fd path flags f =
  match Unix.openfile path (Unix.O_CLOEXEC :: flags) 0o600 with
  | exception Unix.Unix_error (error, _, _) -> Error (file_error path error)
  | fd -> Fun.protect ~finally:(fun () -> Unix.close fd) (fun () -> f fd)

let write_file path text =
  match
    Out_channel.with_open_bin path (fun channel ->
        Out_channel.output_string channel text)
  with
  | () -> Ok ()
  | exception Sys_error message -> Error (File_error message)

(* The first bytes of the file at [path]: as many as an error carries of
   what git wrote to its standard error. *)
let head path =
  match
    In_channel.with_open_bin path (fun channel ->
        let length = min 4096 (Int64.to_int (In_channel.length channel)) in
        really_input_string channel length)
  with
  | text -> Ok text
  | exception (Sys_error _ | End_of_file) ->
      Error (File_error (path ^ ": the file did not read"))

let rec wait pid =
  match Unix.waitpid [] pid with
  | _, status -> status
  | exception Unix.Unix_error (Unix.EINTR, _, _) -> wait pid

let rec drain channel =
  match In_channel.input_char channel with
  | Some _ -> drain channel
  | None -> ()

(* [with_stdin input f] calls [f] with the descriptor for the standard
   input of a child: the text [input] when there is one, and the empty
   input when there is none. *)
let with_stdin input f =
  match input with
  | None -> with_fd "/dev/null" [ Unix.O_RDONLY ] f
  | Some text ->
      with_temp_file ".in" (fun path ->
          let* () = write_file path text in
          with_fd path [ Unix.O_RDONLY ] f)

(* [exec ~git ~env ?input args consume] runs [git] with the arguments
   [args] and the environment [env], and gives its standard output to
   [consume]. The result is the exit status, what [consume] gave, and the
   first part of the standard error. The output that [consume] leaves is
   read and dropped, so the child never waits on a full pipe.
   [End_of_file] from [consume] gives [Malformed_output]. Any other
   exception from [consume] passes through, after the child ends. *)
let exec ~git ~env ?input args consume =
  with_temp_file ".err" (fun err_path ->
      with_stdin input (fun stdin ->
          with_fd err_path [ Unix.O_WRONLY ] (fun stderr ->
              let out, out_writer = Unix.pipe ~cloexec:true () in
              let started =
                match
                  Fun.protect
                    ~finally:(fun () -> Unix.close out_writer)
                    (fun () ->
                      Unix.create_process_env git
                        (Array.of_list ("git" :: args))
                        env stdin out_writer stderr)
                with
                | pid -> Ok pid
                | exception Unix.Unix_error (error, _, _) ->
                    Unix.close out;
                    Error (Git_not_found (Unix.error_message error))
              in
              let* pid = started in
              let channel = Unix.in_channel_of_descr out in
              let value =
                match consume channel with
                | value ->
                    drain channel;
                    value
                | exception End_of_file ->
                    Error
                      (Malformed_output
                         { args; detail = "the output ends too early" })
                | exception raised ->
                    close_in_noerr channel;
                    ignore (wait pid);
                    raise raised
              in
              close_in_noerr channel;
              let status = wait pid in
              let* stderr = head err_path in
              Ok (status, value, stderr))))

let read_all channel = Ok (In_channel.input_all channel)

(* The variables of the caller's environment that a child does not get,
   and the two that [open_repo] sets for every child. *)
let removed_variables =
  [
    "GIT_DIR";
    "GIT_WORK_TREE";
    "GIT_INDEX_FILE";
    "GIT_DIFF_OPTS";
    "GIT_EXTERNAL_DIFF";
    "GIT_OPTIONAL_LOCKS";
    "GIT_TERMINAL_PROMPT";
  ]

let variable_name entry =
  match String.index_opt entry '=' with
  | Some equals -> String.sub entry 0 equals
  | None -> entry

let child_env env =
  let kept =
    List.filter
      (fun entry -> not (List.mem (variable_name entry) removed_variables))
      (Array.to_list env)
  in
  Array.of_list (kept @ [ "GIT_OPTIONAL_LOCKS=0"; "GIT_TERMINAL_PROMPT=0" ])

let is_executable_file path =
  match Unix.stat path with
  | { Unix.st_kind = Unix.S_REG; _ } -> (
      match Unix.access path [ Unix.X_OK ] with
      | () -> true
      | exception Unix.Unix_error _ -> false)
  | _ -> false
  | exception Unix.Unix_error _ -> false

(* The first [git] of the directories of [PATH] in [env]. An empty entry
   of [PATH] names no directory here. *)
let find_git env =
  let path =
    Array.to_list env
    |> List.find_map (fun entry ->
        if String.starts_with ~prefix:"PATH=" entry then
          Some (String.sub entry 5 (String.length entry - 5))
        else None)
  in
  let directories =
    match path with
    | None -> []
    | Some path ->
        List.filter (fun dir -> dir <> "") (String.split_on_char ':' path)
  in
  match
    List.find_opt is_executable_file
      (List.map (fun dir -> Filename.concat dir "git") directories)
  with
  | Some git -> Ok git
  | None -> Error (Git_not_found "no directory of PATH holds an executable git")

let failed args status stderr = Error (Command_failed { args; status; stderr })

let decoded args decode output =
  Result.map_error
    (fun detail -> Malformed_output { args; detail })
    (decode output)

(* [run ?env repo args decode] runs git in the root of [repo] and
   decodes its whole standard output with [decode]. An exit status other
   than 0 gives [Command_failed]. *)
let run ?env t args decode =
  let args = "-C" :: t.root :: args in
  let env = Option.value env ~default:t.env in
  let* status, output, stderr = exec ~git:t.git ~env args read_all in
  match status with
  | Unix.WEXITED 0 ->
      let* output = output in
      decoded args decode output
  | _ -> failed args status stderr

let open_repo ~env dir =
  let* git = find_git env in
  let env = child_env env in
  if dir = "" then
    Error (Not_a_repository { dir; detail = "the directory name is empty" })
  else
    let args =
      [ "-C"; dir; "rev-parse"; "--show-object-format"; "--show-toplevel" ]
    in
    let* status, output, stderr = exec ~git ~env args read_all in
    match status with
    | Unix.WEXITED 0 ->
        let* output = output in
        let* format, root = decoded args Decode.repository output in
        Ok { root; git; env; format }
    | _ -> Error (Not_a_repository { dir; detail = stderr })

(* [answer repo args decode] runs git in the root of [repo], for a command
   whose exit status 1 says "no". It is [Some] of the decoded output for
   the status 0, and [None] for the status 1. *)
let answer t args decode =
  let args = "-C" :: t.root :: args in
  let* status, output, stderr = exec ~git:t.git ~env:t.env args read_all in
  match status with
  | Unix.WEXITED 0 ->
      let* output = output in
      let* value = decoded args decode output in
      Ok (Some value)
  | Unix.WEXITED 1 -> Ok None
  | _ -> failed args status stderr

(* [commit_of repo rev] is the object id of the commit that [rev] names. A
   revision that starts with a hyphen names no commit here, so that git
   never reads [rev] as an option. *)
let commit_of t rev =
  if rev = "" || rev.[0] = '-' then Error (Bad_revision rev)
  else
    let* commit =
      answer t
        [ "rev-parse"; "--verify"; "--quiet"; rev ^ "^{commit}" ]
        Decode.object_id
    in
    Option.to_result commit ~none:(Bad_revision rev)

(* The working tree's file set. *)

module Paths = Set.Make (String)

type entry = { path : string }

let symbolic_link_mode = 0o120000
let submodule_mode = 0o160000

(* [is_regular_file repo path] is [true] when [path] names a regular
   file under the root, and [false] when it names something else or
   nothing. *)
let is_regular_file t path =
  let full = Filename.concat t.root path in
  match Unix.lstat full with
  | { Unix.st_kind = Unix.S_REG; _ } -> Ok true
  | _ -> Ok false
  | exception Unix.Unix_error ((Unix.ENOENT | Unix.ENOTDIR), _, _) -> Ok false
  | exception Unix.Unix_error (error, _, _) -> Error (file_error full error)

let file_set t =
  let* staged =
    run t [ "ls-files"; "-z"; "--cached"; "-s" ] Decode.ls_files_stage
  in
  let* others =
    run t [ "ls-files"; "-z"; "--others"; "--exclude-standard" ] Decode.nul_list
  in
  let special =
    List.fold_left
      (fun special (entry : Decode.stage_entry) ->
        if entry.mode = symbolic_link_mode || entry.mode = submodule_mode then
          Paths.add entry.path special
        else special)
      Paths.empty staged
  in
  (* [others] names a directory that holds a repository of its own as
     [dir/], and [is_regular_file] leaves that name out. *)
  let candidates =
    List.filter_map
      (fun (entry : Decode.stage_entry) ->
        if Paths.mem entry.path special then None
        else Some { path = entry.path })
      staged
    @ List.map (fun path -> { path }) others
  in
  let* kept =
    List.fold_left
      (fun kept entry ->
        let* kept = kept in
        let* regular = is_regular_file t entry.path in
        Ok (if regular then entry :: kept else kept))
      (Ok []) candidates
  in
  Ok (List.sort_uniq (fun a b -> String.compare a.path b.path) kept)

let files t = Result.map (List.map (fun entry -> entry.path)) (file_set t)

(* The base tree. *)

(* [base_tree_of_commit repo commit] is [base_tree] for the object id
   [commit] of a commit. *)
let base_tree_of_commit t commit =
  let* entries =
    run t [ "ls-tree"; "-r"; "-z"; "--full-tree"; commit ] Decode.ls_tree
  in
  let files =
    List.filter_map
      (fun (entry : Decode.tree_entry) ->
        match entry.kind with
        | Decode.Blob when entry.mode <> symbolic_link_mode ->
            Some (entry.path, entry.id)
        | _ -> None)
      entries
  in
  Ok (List.sort_uniq (fun (a, _) (b, _) -> String.compare a b) files)

let base_tree t rev =
  let* commit = commit_of t rev in
  base_tree_of_commit t commit

let id_length t = match t.format with Sha1 -> 40 | Sha256 -> 64

let fold_blobs t ids ~init ~f =
  match
    List.find_opt
      (fun id -> not (Decode.is_object_id id && String.length id = id_length t))
      ids
  with
  | Some id -> Error (Bad_revision id)
  | None -> (
      let args = [ "-C"; t.root; "cat-file"; "--batch" ] in
      let input = String.concat "" (List.map (fun id -> id ^ "\n") ids) in
      let malformed detail = Error (Malformed_output { args; detail }) in
      let rec read channel acc = function
        | [] -> Ok acc
        | id :: rest -> (
            match In_channel.input_line channel with
            | None -> malformed "the output ends too early"
            | Some header -> (
                let* header = decoded args Decode.batch_header header in
                match header with
                | Decode.Missing _ -> Error (Bad_revision id)
                | Decode.Object { id = read_id; kind; size } ->
                    let content = really_input_string channel size in
                    if input_char channel <> '\n' then
                      malformed "an object does not end with a line feed"
                    else if read_id <> id then
                      malformed (Printf.sprintf "git read %s for %s" read_id id)
                    else if kind <> Decode.Blob then Error (Bad_revision id)
                    else read channel (f acc id content) rest))
      in
      let* status, value, stderr =
        exec ~git:t.git ~env:t.env ~input args (fun channel ->
            read channel init ids)
      in
      match status with
      | Unix.WEXITED 0 -> value
      | _ -> failed args status stderr)

(* The tree key. *)

(* [copy_index ~index ~copy] writes the content of the file at [index] to
   the file at [copy]. When no file is at [index], it removes [copy], so
   that git reads no index there and starts from an empty one. *)
let copy_index ~index ~copy =
  if Sys.file_exists index then
    match In_channel.with_open_bin index In_channel.input_all with
    | content -> write_file copy content
    | exception Sys_error message -> Error (File_error message)
  else (
    remove_quietly copy;
    Ok ())

let tree_key t =
  let* index = run t [ "rev-parse"; "--git-path"; "index" ] Decode.line in
  let index =
    if Filename.is_relative index then Filename.concat t.root index else index
  in
  with_temp_file ".index" (fun copy ->
      Fun.protect
        ~finally:(fun () -> remove_quietly (copy ^ ".lock"))
        (fun () ->
          let* () = copy_index ~index ~copy in
          let env = Array.append t.env [| "GIT_INDEX_FILE=" ^ copy |] in
          let* _ = run ~env t [ "add"; "-A" ] Result.ok in
          run ~env t [ "write-tree" ] Decode.object_id))
