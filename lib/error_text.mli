(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(** An error for the person who runs the tool: what is wrong, what to do, and
    the place of the fault in a file when the fault has one. *)

type place = {
  path : string;  (** the file, as the person or the repository names it *)
  span : Toml.span;  (** the text at fault *)
  line : string option;
      (** the line of the start of [span], without its line ending; [None] when
          the text of the file is not at hand *)
}
(** A place in a file. *)

type t = {
  fault : string;  (** what is wrong, with no full stop at the end *)
  help : string;
      (** what the person can do, with no full stop at the end; empty only for a
          usage error whose text {!Usage.error} does not read *)
  place : place option;
}
(** One error. *)

val fault_of_sinter : string
(** The help of an error that only a fault of Sinter can cause:
    [report this as a fault of sinter]. *)

val output_help : string
(** The help of an error of a write to an output:
    [check that the output stays open and that the disk has space]. *)
