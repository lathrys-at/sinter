(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(** Slugs: the names of declared items. A letter or a digit here is an ASCII
    letter or an ASCII digit. *)

val is_valid : string -> bool
(** [is_valid text] is [true] when [text] matches the slug pattern
    [[A-Za-z0-9]+([-_.][A-Za-z0-9]+)*]: runs of letters and digits, with one
    [-], [_], or [.] between two runs. *)

val of_heading : string -> string
(** [of_heading text] is the slug of the heading text [text]: each letter made
    lowercase, each run of other bytes than letters and digits made one [-], and
    the [-] at both ends removed. It is [""] when [text] holds no letter and no
    digit. *)
