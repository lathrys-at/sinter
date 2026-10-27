(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(** The ids of the facts of the manifest, and of tombstones. A key path is the
    names of the keys from the top of the manifest down to a value. *)

val setting : string list -> string
(** [setting key] is [setting:<key path>], the id of a setting fact of one
    value. The key path is the names of [key] joined with [.].

    @raise Invalid_argument
      if [key] is empty, or if a name of [key] is empty or holds [.] or [=]. *)

val member : string list -> string -> string
(** [member key value] is [setting:<key path>=<value>], the id of a setting fact
    of one member of an array. [value] can hold any byte.

    @raise Invalid_argument on the conditions of {!setting}. *)

val gate : Finding_class.gate -> Finding_class.t -> string
(** [gate gate finding_class] is [gate:<gate>/<class>], the id of a gate fact,
    with the names of {!Finding_class.gate_name} and {!Finding_class.name}. *)

val tombstone : string -> string
(** [tombstone was] is [tombstone:<was>], the id of the tombstone of the fact of
    the base whose id is [was]. *)
