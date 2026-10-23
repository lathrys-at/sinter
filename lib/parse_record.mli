(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(** The records that the command [sinter parse] writes, one for each capture. *)

(** A string of a capture. *)
type field = Capture_name | Node_type | Node_text

(** Why a capture gives no record. *)
type error =
  | Path_not_utf_8  (** the name of the file is not UTF-8 text *)
  | Not_utf_8 of field  (** a string of the capture is not UTF-8 text *)

val of_capture :
  path:string ->
  source:string ->
  Sinter_bridge.Query.capture ->
  (Jsonl.record, error) result
(** [of_capture ~path ~source capture] is the JSONL record for one capture in
    the file at [path]. [source] is the text of that file.

    The byte range of [capture] must lie inside [source]: the start is 0 or
    more, the end is the start or more, and the end is at most the length of
    [source]. The rows and the columns of [capture] must be the rows and the
    byte columns of that range in [source]; a row or a column that says
    otherwise gives a record with a span that does not name the range.

    The fields are:

    - [path]: the file, as it was named on the command line
    - [pat]: the index of the pattern in the query, from 0
    - [cap]: the capture name, without the [@]
    - [node]: the type of the node, for example ["string_content"]
    - [sb], [eb]: the start and the end of the node, as byte offsets from the
      start of the file. The end is exclusive
    - [line], [col]: the start of the node, from 1. The column counts bytes, not
      characters
    - [eline]: the line that holds the last byte of the node, from 1
    - [ecol]: one byte past the last byte of the node, in the line [eline], from
      1
    - [text]: the source text of the node

    Every string of the record is valid UTF-8. The error names the first string
    that is not, in the order [path], the capture name, the node type, and the
    text.

    @raise Invalid_argument
      if the byte range of [capture] is not inside [source]. *)

val message : path:string -> error -> string
(** [message ~path error] says what is wrong, for the person who runs the tool.
    The message names the file at [path], and gives its name as escaped bytes
    when the name is not UTF-8 text. *)
