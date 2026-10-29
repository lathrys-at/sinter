(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(** The lines of the files that an output shows. Each file is read at most once,
    at the first request for one of its lines. *)

type t
(** The files of one output, by their paths. The value holds the text of each
    file that it read, until the caller drops the value. *)

val create : root:string -> t
(** [create ~root] is a source that has read no file. A relative path names a
    file under the folder [root], and an absolute path names itself. *)

val line : t -> string -> int -> string option
(** [line source path number] is the content of the line [number] of the file at
    [path], as {!Line_index.content} gives it, without its line ending. The
    first call for [path] reads the file with {!Text_file.read_text}; a later
    call for [path] reads nothing, and looks the file up by its path.

    It is [None] when the file does not read, when its content is not UTF-8
    text, or when the file has no line [number]. *)
