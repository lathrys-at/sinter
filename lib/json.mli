(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(* @cites json-handling *)

(** The printer of all of Sinter's JSON. It writes a value in the canonical form
    of RFC 8785: the keys of each object sorted by UTF-16 code units, the
    strings escaped as RFC 8785 section 3.2.2.2 requires, and no insignificant
    whitespace. A value holds no float. *)

(** One JSON value. *)
type t =
  | Null
  | Bool of bool
  | Int of int  (** an integer from [-(2^53-1)] to [2^53-1] *)
  | String of string  (** a string of valid UTF-8 *)
  | Array of t list  (** the elements, in the order of the output *)
  | Object of (string * t) list
      (** the members: each pair is a key of valid UTF-8 and a value. The order
          of the pairs does not matter: the printer sorts them. *)

(** One step from a value to a value inside it. *)
type step =
  | Key of string  (** to the value of the member with this key *)
  | Index of int  (** to the element at this position of an array, from 0 *)

(** Why the printer refuses a value. Each error holds the path from the whole
    value to the place of the fault, outermost step first. *)
type error =
  | Repeated_key of { path : step list; key : string }
      (** the object at [path] holds [key] twice *)
  | Out_of_range of { path : step list; value : int }
      (** the integer [value] at [path] is outside the range from [-(2^53-1)] to
          [2^53-1] *)
  | Not_utf_8 of { path : step list; text : string }
      (** [text] is not valid UTF-8: the string at [path], or the key of the
          member at [path], whose last step is then [Key text] *)

val to_string : t -> (string, error) result
(** [to_string value] is the canonical form of [value], with no line feed after
    it. It is an error when [value] holds a fault of {!error}. The printer
    checks the keys of an object for a repeated key before it prints the members
    of the object, and it prints the members and the elements in order, so the
    error is the first fault in that order. *)

val compare_keys : string -> string -> int
(** [compare_keys a b] orders two keys by their UTF-16 code units: it is
    negative when [a] comes first, zero when they are equal, and positive when
    [b] comes first. This is the order of the keys of a canonical object.

    A byte that is not part of a valid UTF-8 sequence counts as U+FFFD, so two
    keys that are not valid UTF-8 can compare equal while they differ. On keys
    that are valid UTF-8 the order is total: two keys compare equal only when
    they are equal. *)
