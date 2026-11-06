(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(** Read a file of the repository with no symbolic link followed below the root.

    {!read} opens each part of the path in turn, each one through the folder
    that the part before it opened, and it reads through the handle of the last
    part. No other process can move the read to another file by a change to the
    path after a part opened. *)

(** Why a repository path gives no content. *)
type error =
  | Not_a_repository_path
      (** a part of the path is empty, [.], or [..], so the path does not name a
          file below the root. An absolute path has an empty first part. *)
  | Nothing_at_path
      (** no file is at the path, or a part before the last part is a file that
          is not a folder *)
  | Symbolic_link  (** a part of the path is a symbolic link *)
  | Not_regular
      (** the last part is a folder, a pipe, a device, a socket, or another file
          that is not regular *)
  | Cannot_open of string
      (** a part does not open for another reason. The string is the message of
          the system, which does not name the file. *)
  | Cannot_read of string
      (** reading the file fails. The string is the message of the system, which
          does not name the file. *)

val read : root:string -> string -> (string, error) result
(** [read ~root path] is the whole content, as bytes, of the regular file at the
    relative path [path] below the folder [root]. A symbolic link in [root]
    itself is followed. A symbolic link in [path] is an error, and the result
    never holds any text of its target.

    The function reads the file once, through one handle. It blocks on no pipe.
    It closes each handle before it returns or raises, and it closes the handle
    of each folder as soon as the next part is open. No handle stays open across
    a call that starts a child process. *)

val message : string -> error -> string
(** [message path error] says what is wrong with the file at [path], for the
    person who runs the tool. The message names [path], and it holds no text of
    the target of a symbolic link. *)

(** Where a path that the person gives leads. *)
type place =
  | Inside of string
      (** the path is below the repository root. The string is the path relative
          to the root, for {!read}. *)
  | Outside of string
      (** the path is not below the repository root. The string is the absolute
          path, with each [.] and [..] resolved in its text. *)

val place : root:string -> dir:string -> string -> (place, string) result
(** [place ~root ~dir path] says where [path] leads. A relative [path] is
    relative to the [realpath] of the folder [dir]. The function first resolves
    each [.] and [..] in the text of [path], and it follows no link for that. It
    then takes each folder that the result names, shortest first. The first one
    whose [realpath] is the [realpath] of [root], or is below it, gives
    [Inside]: the rest of that [realpath] below the root, then the rest of the
    path. So a symbolic link below the root never makes a path [Outside]. A path
    that no such folder holds is [Outside], and so is the root itself.

    A [path] that ends in [/], [/.], or [/..] names a folder. The string of the
    result then ends in [/], so {!read} gives [Not_a_repository_path] for it,
    and the system does not open a file by that path.

    [Unix.realpath] gives the case of the name on the disk, so a folder in
    another case on a disk that ignores case still leads inside.

    The error is the message of the system, when [root] or a [dir] that a
    relative path needs has no [realpath]. *)
