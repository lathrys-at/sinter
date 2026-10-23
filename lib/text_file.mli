(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(** Read a file whole, as bytes or as UTF-8 text. *)

(** Why a file gives no content. *)
type error =
  | Is_a_directory
  | Cannot_open of string
      (** the file does not open. The string is the message of the system, which
          names the file. *)
  | Cannot_read of string
      (** reading the file fails. The string is the message of the system, which
          does not name the file. *)
  | Shorter_than_its_length
      (** the file ends before the length that the system gives for it *)
  | Not_utf_8 of int
      (** the content is not UTF-8 text. The integer is the byte offset of the
          first sequence that is not well-formed. *)

val read : string -> (string, error) result
(** [read path] is the whole content of the file at [path], as bytes. The error
    is never [Not_utf_8]. *)

val read_text : string -> (string, error) result
(** [read_text path] is the whole content of the file at [path] when it is UTF-8
    text. *)

val message : string -> error -> string
(** [message path error] says what is wrong with the file at [path], for the
    person who runs the tool. The message names [path]. *)

val with_final_line_feed : string -> string
(** [with_final_line_feed text] is [text] with a line feed added at its end when
    [text] does not end with one. The empty text gives one line feed. Every byte
    offset into [text] is a byte offset into the result, with the same meaning.
*)
