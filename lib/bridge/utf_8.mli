(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(** The check of UTF-8 text for the whole tool. *)

val is_valid : string -> bool
(** [is_valid text] is [true] when every byte of [text] belongs to a well-formed
    UTF-8 sequence. The empty string is valid. *)

val first_invalid : string -> int option
(** [first_invalid text] is the byte offset of the first sequence of [text] that
    is not well-formed UTF-8, or [None] when [text] is valid. *)

val escaped : string -> string
(** [escaped text] is [text] with each byte that is not part of a well-formed
    UTF-8 sequence written as [\x] and two lowercase hexadecimal digits. Text
    that is valid UTF-8 comes back with the same bytes. The time and the memory
    of the call are in proportion to the length of [text]. *)
