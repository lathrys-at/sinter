(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(** The canonical form of one JSON Lines record, as spec/jsonl.md section 2
    defines it. A record is a JSON object. The keys are sorted by UTF-16 code
    units. The line holds no insignificant whitespace. The line ends with LF.

    The schema allows four kinds of value: a string, an integer, a boolean, and
    a flat array of one of those three. It allows no float, no null, and no
    nested object. The types below allow nothing else. *)

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
      if the record holds the same field name twice, or if an integer is outside
      the range that spec/jsonl.md section 2 allows. *)

val output : out_channel -> record -> unit
(** [output channel record] writes the canonical line for [record] to [channel],
    and then one LF. It raises the same exceptions as {!to_string}. *)

val compare_keys : string -> string -> int
(** [compare_keys a b] orders two field names by their UTF-16 code units. This
    is the order that spec/jsonl.md section 2 requires. *)
