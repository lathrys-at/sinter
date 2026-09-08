(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(* @cites json-handling *)

(** The canonical form of one JSON Lines record. A record is a JSON object. Its
    keys are sorted by UTF-16 code units. The line holds no insignificant
    whitespace, and it ends with LF.

    A value is a string, an integer, a boolean, or a flat array of one of those
    three. A float, a null, and a nested object are not values. *)

type scalar =
  | String of string
  | Int of int
  | Bool of bool  (** One value that is not an array. *)

type value =
  | Scalar of scalar
  | Array of scalar list
      (** One value of a field. An array holds scalars only. *)

type record = (string * value) list
(** One fact. Each pair is a field name and a value. The order of the pairs does
    not matter: the writer sorts them. *)

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
    and then one LF. It raises the same exceptions as {!to_string}. *)

val is_utf_8 : string -> bool
(** [is_utf_8 text] is [true] when [text] is valid UTF-8. Only such a string can
    be a field name or a string value of a record. *)

val compare_keys : string -> string -> int
(** [compare_keys a b] orders two field names by their UTF-16 code units. This
    is the order of the keys in a canonical record. *)
