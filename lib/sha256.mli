(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(* @cites sha256 *)

(** The SHA-256 digest of a string. *)

val digest : string -> string
(** [digest data] is the SHA-256 digest of the bytes of [data], as 32 bytes.

    @raise Sinter_bridge.Error if the bridge stops on an internal fault. *)

val hex : string -> string
(** [hex data] is the SHA-256 digest of the bytes of [data], as 64 lowercase
    hexadecimal digits.

    @raise Sinter_bridge.Error if the bridge stops on an internal fault. *)
