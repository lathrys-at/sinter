(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

type error =
  | Is_a_directory
  | Cannot_open of string
  | Cannot_read of string
  | Shorter_than_its_length
  | Not_utf_8 of int

let read path =
  if try Sys.is_directory path with Sys_error _ -> false then
    Error Is_a_directory
  else
    match open_in_bin path with
    | exception Sys_error message -> Error (Cannot_open message)
    | channel ->
        Fun.protect
          ~finally:(fun () -> close_in_noerr channel)
          (fun () ->
            match really_input_string channel (in_channel_length channel) with
            | content -> Ok content
            | exception Sys_error message -> Error (Cannot_read message)
            | exception End_of_file -> Error Shorter_than_its_length)

let read_text path =
  Result.bind (read path) (fun content ->
      match Sinter_bridge.Utf_8.first_invalid content with
      | None -> Ok content
      | Some offset -> Error (Not_utf_8 offset))

let message path = function
  | Is_a_directory -> path ^ ": is a directory"
  | Cannot_open message -> message
  | Cannot_read message -> path ^ ": " ^ message
  | Shorter_than_its_length ->
      path ^ ": the file ended sooner than its length says"
  | Not_utf_8 offset ->
      Printf.sprintf "%s: the file is not UTF-8 text, at byte %d" path offset

let with_final_line_feed text =
  if String.ends_with ~suffix:"\n" text then text else text ^ "\n"
