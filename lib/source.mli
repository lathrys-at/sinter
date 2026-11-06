(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(** The lines of the files that an output shows. Each file is read at most once,
    at the first request for one of its lines. *)

type t
(** The files of one output, by their paths. The value holds the text of each
    file that it read, until the caller drops the value. *)

val create : root:string -> manifest:string -> files:string list -> t
(** [create ~root ~manifest ~files] is a source that has read no file. It reads
    a file only at the relative path [manifest], or at a relative path of
    [files]. Such a path names a file under the folder [root], which
    {!Repo_file.read} reads, with no link followed below [root]. The source
    opens nothing for any other path, and for each absolute path. *)

val line : t -> string -> int -> string option
(** [line source path number] is the content of the line [number] of the file at
    [path], as {!Line_index.content} gives it, without its line ending. The
    first call for [path] reads the file; a later call for [path] reads nothing,
    and looks the file up by its path.

    It is [None] when the path names no file, when the file does not read, when
    its content is not UTF-8 text, or when the file has no line [number]. *)
