(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

type error =
  | Git_not_found of string
  | Not_a_repository of { dir : string; detail : string }
  | Bad_revision of string
  | Default_branch_not_found of string
  | No_merge_base of string * string
  | Command_failed of {
      args : string list;
      status : Unix.process_status;
      stderr : string;
    }
  | Malformed_output of { args : string list; detail : string }
  | File_error of string

type object_format = Sha1 | Sha256

type t = {
  root : string;
  git : string;
  env : string array;
  format : object_format;
  index : (string, error) result Lazy.t;
  objects : (string, error) result Lazy.t;
}

let root t = t.root
let object_format t = t.format
let ( let* ) = Result.bind

type hunk = {
  line : int;
  eline : int;
  ecol : int;
  old_line : int;
  added : int;
  removed : int;
}

type content = Text of hunk list | Binary
type change = Added of content | Deleted of content | Modified of content

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

  type ref_entry = {
    refname : string;
    kind : kind;
    id : string;
    upstream : string;
  }

  let ref_entry record =
    let entry =
      match String.split_on_char '\000' record with
      | [ refname; kind_field; id; upstream ]
        when refname <> "" && is_object_id id ->
          Option.map
            (fun kind -> { refname; kind; id; upstream })
            (kind kind_field)
      | _ -> None
    in
    Option.to_result entry
      ~none:(Printf.sprintf "%S is not a ref of git for-each-ref" record)

  let refs output =
    if output = "" then Ok []
    else
      let* records = line output in
      all ref_entry (String.split_on_char '\n' records)

  type header = {
    old_start : int;
    old_count : int;
    new_start : int;
    new_count : int;
  }

  let max_digits = 15

  let number text i =
    let n = String.length text in
    let rec stop j =
      if j < n && text.[j] >= '0' && text.[j] <= '9' then stop (j + 1) else j
    in
    let j = stop i in
    if j = i then Error (Printf.sprintf "%S has no number at offset %d" text i)
    else if j - i > max_digits then
      Error (Printf.sprintf "%S has a number too large at offset %d" text i)
    else Ok (int_of_string (String.sub text i (j - i)), j)

  let literal text i word =
    let n = String.length word in
    if i + n <= String.length text && String.sub text i n = word then Ok (i + n)
    else Error (Printf.sprintf "%S has no %S at offset %d" text word i)

  let range text i =
    let* start, i = number text i in
    if i < String.length text && text.[i] = ',' then
      let* count, i = number text (i + 1) in
      Ok (start, count, i)
    else Ok (start, 1, i)

  let hunk_header text =
    let* i = literal text 0 "@@ -" in
    let* old_start, old_count, i = range text i in
    let* i = literal text i " +" in
    let* new_start, new_count, i = range text i in
    let* i = literal text i " @@" in
    if i < String.length text && text.[i] <> ' ' then
      Error (Printf.sprintf "%S has no space after its closing @@" text)
    else if old_count > 0 && old_start = 0 then
      Error (Printf.sprintf "%S starts its old lines at line 0" text)
    else if new_count > 0 && new_start = 0 then
      Error (Printf.sprintf "%S starts its new lines at line 0" text)
    else Ok { old_start; old_count; new_start; new_count }

  let unquote text i =
    let n = String.length text in
    let octal_at k = k < n && text.[k] >= '0' && text.[k] <= '7' in
    let rec go bytes j =
      if j >= n then
        Error (Printf.sprintf "%S has a name with no closing quote" text)
      else
        match text.[j] with
        | '"' -> Ok (String.of_seq (List.to_seq (List.rev bytes)), j + 1)
        | '\\' -> escape bytes (j + 1)
        | c -> go (c :: bytes) (j + 1)
    and escape bytes j =
      let byte c = go (c :: bytes) (j + 1) in
      if j >= n then Error (Printf.sprintf "%S ends inside an escape" text)
      else
        match text.[j] with
        | 'a' -> byte '\007'
        | 'b' -> byte '\b'
        | 't' -> byte '\t'
        | 'n' -> byte '\n'
        | 'v' -> byte '\011'
        | 'f' -> byte '\012'
        | 'r' -> byte '\r'
        | ('"' | '\\') as c -> byte c
        | '0' .. '3' when octal_at (j + 1) && octal_at (j + 2) ->
            let digit k = Char.code text.[k] - Char.code '0' in
            let c =
              Char.chr ((digit j * 64) + (digit (j + 1) * 8) + digit (j + 2))
            in
            go (c :: bytes) (j + 3)
        | c -> Error (Printf.sprintf "%S holds the escape \\%c" text c)
    in
    go [] (i + 1)

  let without prefix name =
    if
      String.length name > String.length prefix
      && String.starts_with ~prefix name
    then
      Ok
        (String.sub name (String.length prefix)
           (String.length name - String.length prefix))
    else Error (Printf.sprintf "the name %S does not start with %S" name prefix)

  let path_of_git_line line =
    let* i = literal line 0 "diff --git " in
    let rest = String.sub line i (String.length line - i) in
    let n = String.length rest in
    if String.starts_with ~prefix:"\"" rest then
      let* a, j = unquote rest 0 in
      let* j = literal rest j " " in
      let* b, j =
        if j < n && rest.[j] = '"' then unquote rest j
        else Error (Printf.sprintf "%S quotes its first name only" line)
      in
      let* path = without "a/" a in
      let* other = without "b/" b in
      if j < n then
        Error (Printf.sprintf "%S holds bytes after its second name" line)
      else if path <> other then
        Error (Printf.sprintf "%S names two paths" line)
      else Ok path
    else
      let size = (n - 5) / 2 in
      let twice () =
        Error (Printf.sprintf "%S does not name one path twice" line)
      in
      if size < 1 then twice ()
      else
        let path = String.sub rest 2 size in
        if String.equal rest ("a/" ^ path ^ " b/" ^ path) then Ok path
        else twice ()

  type side = Created | Removed | Changed

  type run = {
    first : int;
    old_first : int;
    added : int;
    removed : int;
    last : string;
    ended : bool;
  }

  let is_continuation byte = Char.code byte land 0xC0 = 0x80

  let columns ~line text =
    let text =
      if line = 1 && String.starts_with ~prefix:"\xEF\xBB\xBF" text then
        String.sub text 3 (String.length text - 3)
      else text
    in
    String.fold_left
      (fun count byte -> if is_continuation byte then count else count + 1)
      0 text

  let add_run run runs =
    match run with
    | None -> runs
    | Some { first; old_first; added; removed; last; ended } ->
        let eline = if added = 0 then first else first + added - 1 in
        let ecol =
          if added = 0 then 1
          else
            let last =
              if ended && String.ends_with ~suffix:"\r" last then
                String.sub last 0 (String.length last - 1)
              else last
            in
            1 + columns ~line:eline last
        in
        { line = first; eline; ecol; old_line = old_first; added; removed }
        :: runs

  let starts prefix line = String.starts_with ~prefix line
  let without_mark line = String.sub line 1 (String.length line - 1)

  let hunk_lines header runs lines =
    let misfit line =
      Error
        (Printf.sprintf "the line %S does not fit the hunk -%d,%d +%d,%d" line
           header.old_start header.old_count header.new_start header.new_count)
    in
    let rec go ?(after_added = false) old_left new_left cursor old_cursor run
        runs = function
      | line :: rest when starts "\\" line ->
          let run =
            if after_added then
              Option.map (fun run -> { run with ended = false }) run
            else run
          in
          go old_left new_left cursor old_cursor run runs rest
      | lines when old_left = 0 && new_left = 0 -> Ok (add_run run runs, lines)
      | [] -> Error "the output ends inside a hunk"
      | line :: rest when line = "" || starts " " line ->
          if old_left > 0 && new_left > 0 then
            go (old_left - 1) (new_left - 1) (cursor + 1) (old_cursor + 1) None
              (add_run run runs) rest
          else misfit line
      | line :: rest when starts "-" line ->
          if old_left > 0 then
            let run =
              match run with
              | None ->
                  {
                    first = cursor;
                    old_first = old_cursor;
                    added = 0;
                    removed = 1;
                    last = "";
                    ended = true;
                  }
              | Some run -> { run with removed = run.removed + 1 }
            in
            go (old_left - 1) new_left cursor (old_cursor + 1) (Some run) runs
              rest
          else misfit line
      | line :: rest when starts "+" line ->
          if new_left > 0 then
            let last = without_mark line in
            let run =
              match run with
              | None ->
                  {
                    first = cursor;
                    old_first = old_cursor;
                    added = 1;
                    removed = 0;
                    last;
                    ended = true;
                  }
              | Some run -> { run with added = run.added + 1; last }
            in
            go ~after_added:true old_left (new_left - 1) (cursor + 1) old_cursor
              (Some run) runs rest
          else misfit line
      | line :: _ -> misfit line
    in
    let cursor =
      if header.new_count = 0 then header.new_start + 1 else header.new_start
    in
    let old_cursor =
      if header.old_count = 0 then header.old_start + 1 else header.old_start
    in
    go header.old_count header.new_count cursor old_cursor None runs lines

  type section = { side : side; binary : bool; runs : hunk list }

  let section lines =
    let rec headers side binary = function
      | line :: rest when starts "@@" line -> hunks side binary [] (line :: rest)
      | line :: rest when not (starts "diff --git " line) ->
          let side =
            if starts "new file mode " line then Created
            else if starts "deleted file mode " line then Removed
            else side
          in
          headers side (binary || starts "Binary files " line) rest
      | lines -> Ok ({ side; binary; runs = [] }, lines)
    and hunks side binary runs = function
      | line :: rest when starts "@@" line ->
          let* header = hunk_header line in
          let* runs, rest = hunk_lines header runs rest in
          hunks side binary runs rest
      | line :: _ when not (starts "diff --git " line) ->
          Error (Printf.sprintf "the line %S follows a hunk" line)
      | lines -> Ok ({ side; binary; runs }, lines)
    in
    headers Changed false lines

  let content_of_section { binary; runs; _ } =
    if binary then Binary else Text (List.rev runs)

  let diff output =
    let n = String.length output in
    let* lines =
      if n = 0 then Ok []
      else if output.[n - 1] <> '\n' then
        Error "the output does not end with a line feed"
      else Ok (String.split_on_char '\n' (String.sub output 0 (n - 1)))
    in
    let rec read found = function
      | [] -> Ok found
      | line :: rest ->
          let* path = path_of_git_line line in
          let* section, rest = section rest in
          read
            ((path, (section.side, content_of_section section)) :: found)
            rest
    in
    let* found = read [] lines in
    let rec group done_ = function
      | (path, section) :: rest -> (
          match done_ with
          | (other, sections) :: earlier when String.equal path other ->
              group ((path, section :: sections) :: earlier) rest
          | _ -> group ((path, [ section ]) :: done_) rest)
      | [] ->
          List.rev_map (fun (path, sections) -> (path, List.rev sections)) done_
    in
    Ok
      (group []
         (List.stable_sort
            (fun (a, _) (b, _) -> String.compare a b)
            (List.rev found)))
end

let file_error path error =
  File_error (Printf.sprintf "%s: %s" path (Unix.error_message error))

let remove_quietly path = try Sys.remove path with Sys_error _ -> ()

let with_temp_file suffix f =
  match Filename.temp_file "sinter-git" suffix with
  | exception Sys_error message -> Error (File_error message)
  | path ->
      Fun.protect ~finally:(fun () -> remove_quietly path) (fun () -> f path)

let with_fd path flags f =
  match
    Unix.openfile path (Unix.O_CLOEXEC :: flags)
      (0o600
      [@mutaml.skip
        "openfile reads the permission only when it creates the file; no \
         caller passes O_CREAT, and every file that it opens exists"])
  with
  | exception Unix.Unix_error (error, _, _) -> Error (file_error path error)
  | fd -> Fun.protect ~finally:(fun () -> Unix.close fd) (fun () -> f fd)

let write_file path text =
  match
    Out_channel.with_open_bin path (fun channel ->
        Out_channel.output_string channel text)
  with
  | () -> Ok ()
  | exception Sys_error message -> Error (File_error message)

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

let read_exactly channel size =
  let piece =
    Bytes.create
      (65536
      [@mutaml.skip
        "the size of a piece changes how many reads fill the content, and not \
         the content"])
  in
  let rec read left pieces =
    if left = 0 then String.concat "" (List.rev pieces)
    else
      match
        In_channel.input channel piece 0 (min left (Bytes.length piece))
      with
      | 0 -> raise End_of_file
      | count -> read (left - count) (Bytes.sub_string piece 0 count :: pieces)
  in
  read size []

let rec drain channel =
  match In_channel.input_char channel with
  | Some _ -> drain channel
  | None -> ()

let with_stdin input f =
  match input with
  | None -> with_fd "/dev/null" [ Unix.O_RDONLY ] f
  | Some text ->
      with_temp_file ".in" (fun path ->
          let* () = write_file path text in
          with_fd path [ Unix.O_RDONLY ] f)

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

let removed_variables =
  [
    "GIT_DIR";
    "GIT_WORK_TREE";
    "GIT_INDEX_FILE";
    "GIT_DIFF_OPTS";
    "GIT_EXTERNAL_DIFF";
    "GIT_OPTIONAL_LOCKS";
    "GIT_TERMINAL_PROMPT";
    "GIT_NO_REPLACE_OBJECTS";
    "GIT_NO_LAZY_FETCH";
    "GIT_LITERAL_PATHSPECS";
    "GIT_GLOB_PATHSPECS";
    "GIT_NOGLOB_PATHSPECS";
    "GIT_ICASE_PATHSPECS";
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
  Array.of_list
    (kept
    @ [
        "GIT_OPTIONAL_LOCKS=0";
        "GIT_TERMINAL_PROMPT=0";
        "GIT_NO_REPLACE_OBJECTS=1";
        "GIT_NO_LAZY_FETCH=1";
        "GIT_LITERAL_PATHSPECS=1";
      ])

let is_executable_file path =
  match Unix.stat path with
  | { Unix.st_kind = Unix.S_REG; _ } -> (
      match Unix.access path [ Unix.X_OK ] with
      | () -> true
      | exception Unix.Unix_error _ -> false)
  | _ -> false
  | exception Unix.Unix_error _ -> false

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

let run_in ~git ~env ~root ?input args decode =
  let args = "-C" :: root :: args in
  let* status, output, stderr = exec ~git ~env ?input args read_all in
  match status with
  | Unix.WEXITED 0 ->
      let* output = output in
      decoded args decode output
  | _ -> failed args status stderr

let run ?env ?input t args decode =
  run_in ~git:t.git
    ~env:(Option.value env ~default:t.env)
    ~root:t.root ?input args decode

let git_path ~git ~env ~root name =
  lazy
    (let* path =
       run_in ~git ~env ~root [ "rev-parse"; "--git-path"; name ] Decode.line
     in
     Ok (if Filename.is_relative path then Filename.concat root path else path))

let open_repo ~env dir =
  let* git = find_git env in
  let env = child_env env in
  if dir = "" then
    Error (Not_a_repository { dir; detail = "the directory name is empty" })
  else if String.contains dir '\000' then
    Error
      (Not_a_repository { dir; detail = "the directory name holds a NUL byte" })
  else
    let args =
      [ "-C"; dir; "rev-parse"; "--show-object-format"; "--show-toplevel" ]
    in
    let* status, output, stderr = exec ~git ~env args read_all in
    match status with
    | Unix.WEXITED 0 ->
        let* output = output in
        let* format, root = decoded args Decode.repository output in
        Ok
          {
            root;
            git;
            env;
            format;
            index = git_path ~git ~env ~root "index";
            objects = git_path ~git ~env ~root "objects";
          }
    | _ -> Error (Not_a_repository { dir; detail = stderr })

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

let commit_of t rev =
  if rev = "" || rev.[0] = '-' || String.contains rev '\000' then
    Error (Bad_revision rev)
  else
    let* commit =
      answer t
        [ "rev-parse"; "--verify"; "--quiet"; rev ^ "^{commit}" ]
        Decode.object_id
    in
    Option.to_result commit ~none:(Bad_revision rev)

module Paths = Set.Make (String)

type entry = { path : string; tracked : bool }

let symbolic_link_mode = 0o120000
let submodule_mode = 0o160000

let is_regular_file t path =
  let full = Filename.concat t.root path in
  match Unix.lstat full with
  | { Unix.st_kind = Unix.S_REG; _ } -> Ok true
  | _ -> Ok false
  | exception Unix.Unix_error ((Unix.ENOENT | Unix.ENOTDIR), _, _) -> Ok false
  | exception Unix.Unix_error (error, _, _) -> Error (file_error full error)

let view_options =
  [ "-c"; "core.fsmonitor=false"; "-c"; "core.splitIndex=false" ]

type file_set = { set_root : string; entries : entry list }

let read_entries t =
  let* staged =
    run t
      (view_options @ [ "ls-files"; "-z"; "--cached"; "-s" ])
      Decode.ls_files_stage
  in
  let* others =
    run t
      (view_options @ [ "ls-files"; "-z"; "--others"; "--exclude-standard" ])
      Decode.nul_list
  in
  let special =
    List.fold_left
      (fun special (entry : Decode.stage_entry) ->
        if entry.mode = symbolic_link_mode || entry.mode = submodule_mode then
          Paths.add entry.path special
        else special)
      Paths.empty staged
  in
  let candidates =
    List.filter_map
      (fun (entry : Decode.stage_entry) ->
        if Paths.mem entry.path special then None
        else Some { path = entry.path; tracked = true })
      staged
    @ List.map (fun path -> { path; tracked = false }) others
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

let files t =
  Result.map (fun entries -> { set_root = t.root; entries }) (read_entries t)

let paths set = List.map (fun entry -> entry.path) set.entries

type source = Upstream | Local_branch | Origin_branch
type default_branch = { source : source; refname : string; commit : string }

let ref_format =
  "--format=%(refname)%00%(objecttype)%00%(objectname)%00%(upstream)"

let refs t patterns =
  run t ("for-each-ref" :: ref_format :: patterns) Decode.refs

let find refname entries =
  List.find_opt
    (fun (entry : Decode.ref_entry) -> String.equal entry.refname refname)
    entries

let resolve_default_branch t name =
  let local = "refs/heads/" ^ name in
  let origin = "refs/remotes/origin/" ^ name in
  if String.contains name '\000' then Error (Default_branch_not_found name)
  else
    let* found = refs t [ local; origin ] in
    let upstream_of entries =
      match find local entries with
      | Some { upstream; _ } when upstream <> "" -> Some upstream
      | _ -> None
    in
    let* entries =
      match upstream_of found with
      | Some upstream when Option.is_none (find upstream found) ->
          Result.map (fun more -> more @ found) (refs t [ upstream ])
      | _ -> Ok found
    in
    [
      (Upstream, Option.bind (upstream_of entries) (fun up -> find up entries));
      (Local_branch, find local entries);
      (Origin_branch, find origin entries);
    ]
    |> List.find_map (fun (source, entry) ->
        match entry with
        | Some { Decode.refname; kind = Decode.Commit; id; _ } ->
            Some { source; refname; commit = id }
        | _ -> None)
    |> Option.to_result ~none:(Default_branch_not_found name)

let merge_base t a b =
  match
    answer t [ "merge-base"; "--end-of-options"; a; b ] Decode.object_id
  with
  | Ok (Some base) -> Ok base
  | Ok None -> Error (No_merge_base (a, b))
  | Error failure ->
      let* _ = commit_of t a in
      let* _ = commit_of t b in
      Error failure

let is_shallow t =
  run t [ "rev-parse"; "--is-shallow-repository" ] (fun output ->
      let* answer = Decode.line output in
      match answer with
      | "true" -> Ok true
      | "false" -> Ok false
      | other -> Error (Printf.sprintf "%S is neither true nor false" other))

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

type base = {
  base_root : string;
  object_id : string;
  tree : (string * string) list;
}

let id_length t = match t.format with Sha1 -> 40 | Sha256 -> 64
let is_id t text = Decode.is_object_id text && String.length text = id_length t

let read_base t rev =
  let resolved () =
    let* commit = commit_of t rev in
    let* tree = base_tree_of_commit t commit in
    Ok { base_root = t.root; object_id = commit; tree }
  in
  if is_id t rev then
    match base_tree_of_commit t (rev ^ "^{commit}") with
    | Ok tree -> Ok { base_root = t.root; object_id = rev; tree }
    | Error _ -> resolved ()
  else resolved ()

let base_files base = base.tree

let fold_blobs t ids ~init ~f =
  match List.find_opt (fun id -> not (is_id t id)) ids with
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
                    let content = read_exactly channel size in
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

let diff_options =
  [
    "-c";
    "core.quotePath=true";
    "-c";
    "core.bigFileThreshold=512m";
    "-c";
    "core.fsmonitor=false";
    "-c";
    "core.splitIndex=false";
    "diff";
    "--no-ext-diff";
    "--no-textconv";
    "--no-color";
    "--no-renames";
    "-U0";
    "--inter-hunk-context=0";
    "--diff-algorithm=myers";
    "--indent-heuristic";
    "--src-prefix=a/";
    "--dst-prefix=b/";
    "-O/dev/null";
    "--submodule=short";
    "--ignore-submodules=all";
  ]

module Path_map = Map.Make (String)

let copy_index ~index ~copy =
  if Sys.file_exists index then
    match In_channel.with_open_bin index In_channel.input_all with
    | content -> (
        let* () = write_file copy content in
        match Unix.stat index with
        | { Unix.st_mtime; _ } -> (
            let time = st_mtime -. 1. in
            match Unix.utimes copy time time with
            | () -> Ok ()
            | exception Unix.Unix_error (error, _, _) ->
                Error (File_error (copy ^ ": " ^ Unix.error_message error)))
        | exception Unix.Unix_error (error, _, _) ->
            Error (File_error (index ^ ": " ^ Unix.error_message error)))
    | exception Sys_error message -> Error (File_error message)
  else (
    remove_quietly copy;
    Ok ())

let with_variables env variables =
  let names = List.map fst variables in
  Array.append
    (Array.of_list
       (List.filter
          (fun entry -> not (List.mem (variable_name entry) names))
          (Array.to_list env)))
    (Array.of_list
       (List.map (fun (name, value) -> name ^ "=" ^ value) variables))

let variable env name =
  Array.to_list env
  |> List.find_map (fun entry ->
      if String.equal (variable_name entry) name then
        Some
          (String.sub entry
             (String.length name + 1)
             (String.length entry - String.length name - 1))
      else None)

let with_index_copy t f =
  let* index = Lazy.force t.index in
  with_temp_file ".index" (fun copy ->
      Fun.protect
        ~finally:(fun () -> remove_quietly (copy ^ ".lock"))
        (fun () ->
          let* () = copy_index ~index ~copy in
          f (with_variables t.env [ ("GIT_INDEX_FILE", copy) ])))

let rec remove_tree path =
  match Unix.lstat path with
  | { Unix.st_kind = Unix.S_DIR; _ } -> (
      Array.iter
        (fun name -> remove_tree (Filename.concat path name))
        (try Sys.readdir path with Sys_error _ -> [||]);
      try Unix.rmdir path with Unix.Unix_error _ -> ())
  | _ -> remove_quietly path
  | exception Unix.Unix_error _ -> ()

let with_temp_dir f =
  match Filename.temp_dir "sinter-git" ".objects" with
  | exception Sys_error message -> Error (File_error message)
  | dir -> Fun.protect ~finally:(fun () -> remove_tree dir) (fun () -> f dir)

let flagged output =
  let* records = Decode.nul_list output in
  Decode.all
    (fun record ->
      if String.length record > 2 && record.[1] = ' ' then
        let path = String.sub record 2 (String.length record - 2) in
        match record.[0] with
        | 'a' .. 'z' as tag -> Ok (Some (path, true, Char.equal tag 's'))
        | 'S' -> Ok (Some (path, false, true))
        | 'A' .. 'Z' -> Ok None
        | _ ->
            Error
              (Printf.sprintf "%S is not an entry of git ls-files -v" record)
      else Error (Printf.sprintf "%S is not an entry of git ls-files -v" record))
    records
  |> Result.map (List.filter_map Fun.id)

let nul_input paths =
  String.concat "" (List.map (fun path -> path ^ "\000") paths)

let clear_flag t ~env flag paths =
  match paths with
  | [] -> Ok ()
  | _ ->
      run ~env ~input:(nul_input paths) t
        (view_options @ [ "update-index"; flag; "-z"; "--stdin" ])
        Result.ok
      |> Result.map ignore

let with_store t f =
  let* objects = Lazy.force t.objects in
  with_temp_dir (fun dir ->
      let store = Filename.concat dir "objects" in
      match Unix.mkdir store 0o700 with
      | exception Unix.Unix_error (error, _, _) ->
          Error (file_error store error)
      | () ->
          let alternates =
            match variable t.env "GIT_ALTERNATE_OBJECT_DIRECTORIES" with
            | Some more when more <> "" -> objects ^ ":" ^ more
            | _ -> objects
          in
          f ~store ~alternates)

let in_store ~store ~alternates env =
  with_variables env
    [
      ("GIT_OBJECT_DIRECTORY", store);
      ("GIT_ALTERNATE_OBJECT_DIRECTORIES", alternates);
    ]

let with_view t ~untracked f =
  with_store t (fun ~store ~alternates ->
      let* _ =
        run
          ~env:(in_store ~store ~alternates:"" t.env)
          t
          [ "hash-object"; "-w"; "--stdin" ]
          Decode.object_id
      in
      with_index_copy t (fun env ->
          let env = in_store ~store ~alternates env in
          let* flags =
            run ~env t (view_options @ [ "ls-files"; "-z"; "-v" ]) flagged
          in
          let* () =
            clear_flag t ~env "--no-assume-unchanged"
              (List.filter_map
                 (fun (path, assumed, _) -> if assumed then Some path else None)
                 flags)
          in
          let* () =
            clear_flag t ~env "--no-skip-worktree"
              (List.filter_map
                 (fun (path, _, skipped) -> if skipped then Some path else None)
                 flags)
          in
          let* () =
            match untracked with
            | [] -> Ok ()
            | paths ->
                run ~env ~input:(nul_input paths) t
                  (view_options
                  @ [
                      "add";
                      "--intent-to-add";
                      "--pathspec-from-file=-";
                      "--pathspec-file-nul";
                    ])
                  Result.ok
                |> Result.map ignore
          in
          f env))

let content_of side sections =
  match List.assoc_opt side sections with
  | Some content -> content
  | None -> (
      match sections with (_, content) :: _ -> content | [] -> Text [])

let diff t ~files ~base =
  if not (String.equal files.set_root t.root) then
    invalid_arg "Git.diff: the file set is of another repository";
  if not (String.equal base.base_root t.root) then
    invalid_arg "Git.diff: the base is of another repository";
  let commit = base.object_id
  and old_files = base.tree
  and new_files = files.entries in
  let old_files =
    List.filter (fun (path, _) -> Sinter_bridge.Utf_8.is_valid path) old_files
  and new_files =
    List.filter (fun entry -> Sinter_bridge.Utf_8.is_valid entry.path) new_files
  in
  let untracked =
    List.filter_map
      (fun entry -> if entry.tracked then None else Some entry.path)
      new_files
  in
  let* sections =
    with_view t ~untracked (fun env ->
        run ~env t (diff_options @ [ commit; "--" ]) Decode.diff)
  in
  let sections = Path_map.of_list sections in
  let in_base = Path_map.of_list old_files in
  let in_tree =
    Path_map.of_list (List.map (fun entry -> (entry.path, ())) new_files)
  in
  let change path =
    let found = Path_map.find_opt path sections in
    match (Path_map.mem path in_base, Path_map.mem path in_tree, found) with
    | true, true, None -> None
    | true, true, Some sections ->
        Some (Modified (content_of Decode.Changed sections))
    | false, _, found ->
        Some
          (Added (content_of Decode.Created (Option.value found ~default:[])))
    | true, false, found ->
        Some
          (Deleted (content_of Decode.Removed (Option.value found ~default:[])))
  in
  let paths =
    List.sort_uniq String.compare
      (List.map fst old_files @ List.map (fun entry -> entry.path) new_files)
  in
  Ok
    (List.filter_map
       (fun path -> Option.map (fun change -> (path, change)) (change path))
       paths)

let whole =
  { line = 1; eline = 1; ecol = 1; old_line = 1; added = 0; removed = 0 }

let hunks = function
  | Added Binary | Deleted Binary | Modified Binary -> [ whole ]
  | Added (Text []) | Deleted (Text []) -> [ whole ]
  | Added (Text runs) | Deleted (Text runs) | Modified (Text runs) -> runs

let tree_key t =
  with_store t (fun ~store ~alternates ->
      with_index_copy t (fun env ->
          let env = in_store ~store ~alternates env in
          let* _ = run ~env t (view_options @ [ "add"; "-A" ]) Result.ok in
          run ~env t (view_options @ [ "write-tree" ]) Decode.object_id))
