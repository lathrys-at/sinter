(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(** A file or a folder that the process cannot read. *)

val with_unreadable : string -> (unit -> 'a) -> 'a option
(** [with_unreadable path f] takes every permission from the file or folder at
    [path], and then opens [path] for reading. When the system refuses the open,
    with [EACCES] or [EPERM], the result is [Some (f ())]. When the system opens
    [path], as it does for the user root, the result is [None], and [f] does not
    run. [path] gets its permissions back before the result returns, and when
    [f] raises. An exception that [f] raises passes through. It raises
    [Unix.Unix_error] when [path] does not exist, or when the open fails with
    another error. *)
