(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(** An index of a list of path sets, which finds the sets that hold a path
    without a match of the path against each set. *)

type t
(** An index of a list of path sets. *)

val make : Path_set.t list -> t
(** [make sets] is the index of [sets]. It files each plain glob of each set
    under the {!Glob.leading_names} of the glob. *)

val holders : t -> string -> int list
(** [holders index path] is the position in the list of {!make}, from 0, of each
    set that holds [path], as {!Path_set.mem} decides, in rising order.

    The function matches [path] only against the sets that have a plain glob
    whose leading names start [path]. So the time is about the number of names
    in [path], plus the matches against those sets. *)
