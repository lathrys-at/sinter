(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(** The check of UTF-8 text for the whole tool. *)

val is_valid : string -> bool
(** [is_valid text] is [true] when every byte of [text] belongs to a well-formed
    UTF-8 sequence. The empty string is valid. *)

val first_invalid : string -> int option
(** [first_invalid text] is the byte offset of the first sequence of [text] that
    is not well-formed UTF-8, or [None] when [text] is valid. *)
