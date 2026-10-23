(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(** Path sets: a set of paths that a list of globs gives.

    A member of the list that starts with [!] is a [!] glob, and the rest of the
    member is a glob. Every other member is a plain glob. A path is in the set
    when a plain glob matches it and no [!] glob matches it. The order of the
    members does not change the set. *)

type t
(** A path set whose members are valid. *)

(** One member of a path set. *)
type member = Plain of Glob.t | Excluded of Glob.t

(** Why a list of strings is not a path set. Each index is the index of a member
    in the list, from 0. *)
type error =
  | Bad_glob of { index : int; start : int; error : Glob.error }
      (** the member is not a glob, or not [!] and then a glob. [start] is the
          offset of the glob in the member: [1] after a [!], [0] otherwise. The
          offsets of [error] count from the start of the glob. *)
  | Repeated of { index : int; member : string }
      (** the member is equal to an earlier member, byte for byte *)
  | No_plain_glob
      (** the list is not empty, and every member of it is a [!] glob *)

val empty : t
(** The set that holds no path. *)

val of_strings : string list -> (t, error list) result
(** [of_strings members] is the path set of [members]. The errors are each
    [Bad_glob] and [Repeated] error, in the order of the members, and then
    [No_plain_glob] when it applies and every member is a valid [!] glob. The
    empty list gives {!empty}. *)

val members : t -> member list
(** [members set] is the members of [set], in the order of the list that made
    it. *)

val is_empty : t -> bool
(** [is_empty set] is [true] when [set] has no member. *)

val mem : t -> string -> bool
(** [mem set path] is [true] when [path] is in [set]: a plain glob of [set]
    matches [path], and no [!] glob of [set] matches it. *)

val member_to_string : member -> string
(** [member_to_string member] is the member as the list writes it: a [!] in
    front of the glob of an [Excluded] member. *)
