(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(** The subtraction of the findings of the base from the findings of the working
    tree, with each position of the base moved through the diff. *)

type t
(** The places of the lines of the base in the working tree, from one diff. *)

val of_diff : (string * Git.change) list -> t
(** [of_diff changes] is the move of positions that [changes] gives, as
    {!Git.diff} gives them. *)

val line : t -> path:string -> int -> int option
(** [line moves ~path base_line] is the line in the working tree that holds the
    line [base_line] of the file [path] of the base. Take the runs whose base
    lines lie before [base_line]: the result is [base_line], plus the lines that
    these runs add, minus the lines that they remove. It is [None] when a run
    removes the line, when the diff deletes the file, and when the diff finds
    the file binary. A path that the diff does not list keeps every line. *)

val subject : t -> Finding.subject -> Finding.subject option
(** [subject moves subject] is [subject] with its position moved by {!line}. A
    line keeps its column. A subject with no position comes back as it is. It is
    [None] when {!line} gives [None]. *)

val subtract : t -> base:Finding.t list -> Finding.t list -> Finding.t list
(** [subtract moves ~base findings] is each finding of [findings] whose id is
    the id of no finding of [base] after {!subject} moves it, in the order of
    [findings]. A finding of [base] whose position {!line} cannot move removes
    nothing. Two findings of [findings] with one id are both removed, or both
    kept. *)
