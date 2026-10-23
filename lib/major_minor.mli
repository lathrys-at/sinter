(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(** Versions of the form MAJOR.MINOR: two decimal numbers with no leading zero,
    joined by [.], such as [1.0] or [2.13]. The numbers have no upper bound. *)

type t
(** A version. *)

val make : int -> int -> t
(** [make major minor] is the version [major.minor].

    @raise Invalid_argument if [major] or [minor] is below 0. *)

val of_string : string -> t option
(** [of_string text] is the version that [text] writes, or [None] when [text] is
    not of the form MAJOR.MINOR. ["1.0.0"], ["01.0"], ["1"], ["1."], and
    ["+1.0"] are not of that form. *)

val to_string : t -> string
(** [to_string version] is the version in the form MAJOR.MINOR. *)

val compare : t -> t -> int
(** [compare a b] orders two versions: by the major numbers, and then by the
    minor numbers. It is [0] only for equal versions. *)

val newer : t -> than:t -> bool
(** [newer a ~than:b] is [true] when [a] comes after [b] in the order of
    {!compare}. *)

val older_major : t -> than:t -> bool
(** [older_major a ~than:b] is [true] when the major number of [a] is less than
    the major number of [b]. *)
