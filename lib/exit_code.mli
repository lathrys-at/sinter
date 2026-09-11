(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(* @cites exit-codes *)

(** The exit codes that every command of the tool returns. A control line of the
    serve mode carries the same codes in its [code] field. *)

val clean : int
(** The command succeeded and reported no finding. *)

val findings : int
(** The command succeeded and reported at least one finding. *)

val usage_error : int
(** The command line, or the request, is wrong. *)

val environment_error : int
(** The command could not run in this environment. *)

val refused : int
(** The command refused to act. *)
