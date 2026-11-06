(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(* @cites repository-file-reads *)

type error =
  | Not_a_repository_path
  | Nothing_at_path
  | Symbolic_link
  | Not_regular
  | Cannot_open of string
  | Cannot_read of string

external open_at : Unix.file_descr -> string -> bool -> Unix.file_descr
  = "sinter_repo_file_open_at"

let close_quietly handle = try Unix.close handle with Unix.Unix_error _ -> ()

let refusal ~root ~walked part code =
  let cannot_open = Cannot_open (Unix.error_message code) in
  match code with
  | Unix.ENOENT -> Nothing_at_path
  | _ -> (
      let full = String.concat "/" (root :: List.rev (part :: walked)) in
      match (Unix.lstat full).st_kind with
      | Unix.S_LNK -> Symbolic_link
      | _ when code = Unix.ENOTDIR -> Nothing_at_path
      | Unix.S_REG | Unix.S_DIR -> cannot_open
      | Unix.S_CHR | Unix.S_BLK | Unix.S_FIFO | Unix.S_SOCK -> Not_regular
      | exception Unix.Unix_error _ -> cannot_open)

let read_regular handle =
  let channel = Unix.in_channel_of_descr handle in
  Fun.protect
    ~finally:(fun () -> close_in_noerr channel)
    (fun () ->
      match In_channel.input_all channel with
      | text -> Ok text
      | exception Sys_error message -> Error (Cannot_read message))

let read_handle handle =
  let kind =
    match (Unix.fstat handle).st_kind with
    | Unix.S_REG -> Ok ()
    | _ -> Error Not_regular
    | exception Unix.Unix_error (code, _, _) ->
        Error (Cannot_read (Unix.error_message code))
  in
  match kind with
  | Ok () -> read_regular handle
  | Error _ as refused ->
      close_quietly handle;
      refused

let rec walk ~root ~walked folder part rest =
  let opened =
    Fun.protect
      ~finally:(fun () -> close_quietly folder)
      (fun () ->
        match open_at folder part (List.is_empty rest) with
        | next -> Ok next
        | exception Unix.Unix_error (code, _, _) ->
            Error (refusal ~root ~walked part code))
  in
  match (opened, rest) with
  | Error error, _ -> Error error
  | Ok handle, [] -> read_handle handle
  | Ok next, following :: others ->
      walk ~root ~walked:(part :: walked) next following others

let open_root root =
  match
    Unix.openfile root
      [ O_RDONLY; O_CLOEXEC; O_NONBLOCK ]
      (0
      [@mutaml.skip
        "openfile reads the permission only when it creates the file, and the \
         flags hold no O_CREAT"])
  with
  | handle -> Ok handle
  | exception Unix.Unix_error (Unix.ENOENT, _, _) -> Error Nothing_at_path
  | exception Unix.Unix_error (code, _, _) ->
      Error (Cannot_open (Unix.error_message code))

let is_name part = not (List.mem part [ ""; "."; ".." ])

let read ~root path =
  match String.split_on_char '/' path with
  | first :: rest when List.for_all is_name (first :: rest) ->
      Result.bind (open_root root) (fun folder ->
          walk ~root ~walked:[] folder first rest)
  | _ -> Error Not_a_repository_path

let message path = function
  | Not_a_repository_path -> path ^ ": the path names no file of the repository"
  | Nothing_at_path -> path ^ ": no file is at this path"
  | Symbolic_link ->
      path ^ " is a symbolic link, and Sinter does not follow links"
  | Not_regular ->
      path ^ " is not a regular file, and Sinter reads only regular files"
  | Cannot_open reason | Cannot_read reason -> path ^ ": " ^ reason
