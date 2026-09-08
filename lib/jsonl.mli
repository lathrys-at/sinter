(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(* @cites json-handling *)

(** The canonical form of one JSON Lines record. A record is a JSON object. Its
    keys are sorted by UTF-16 code units. The line holds no insignificant
    whitespace, and it ends with LF.

    A value is a string, an integer, a boolean, or a flat array of one of those
    three. A float, a null, and a nested object are not values. *)

(** One value that is not an array. *)
type scalar = String of string | Int of int | Bool of bool

(** One value of a field. An array holds scalars only. *)
type value = Scalar of scalar | Array of scalar list

type record = (string * value) list
(** One fact. Each pair is a field name and a value. The order of the pairs does
    not matter: the writer sorts them. *)

(** These five make one field value each. None of them checks its argument.
    {!to_string} refuses a string that is not valid UTF-8, and an integer
    outside the range that a record allows. *)

val string : string -> value
val int : int -> value
val bool : bool -> value
val strings : string list -> value
val ints : int list -> value

val to_string : record -> string
(** [to_string record] is the canonical line for [record], without the LF.

    @raise Invalid_argument
      if the record holds the same field name twice, if an integer is outside
      the range [-(2^53-1)] to [2^53-1], or if a string is not valid UTF-8. *)

val output : out_channel -> record -> unit
(** [output channel record] writes the canonical line for [record] to [channel],
    and then one LF.

    @raise Invalid_argument on the conditions that {!to_string} refuses.
    @raise Sys_error
      if a write to [channel] fails. [channel] holds a buffer, so the failure of
      one record can reach the caller at a later write to [channel] or at the
      flush of it. *)

val compare_keys : string -> string -> int
(** [compare_keys a b] orders two field names by their UTF-16 code units. This
    is the order of the keys in a canonical record.

    A byte that is not part of a valid UTF-8 sequence counts as U+FFFD, so two
    names that are not valid UTF-8 can compare equal while they differ. On names
    that are valid UTF-8 the order is total: two names compare equal only when
    they are equal. *)
