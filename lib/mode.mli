(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(** The mode of a run of [sinter check] or [sinter scan]. *)

type t =
  | Tree  (** the findings of the working tree *)
  | Diff  (** the findings that the working tree adds to those of the base *)

val name : t -> string
(** [name mode] is ["tree"] or ["diff"], as the field [mode] of a record holds
    it. *)
