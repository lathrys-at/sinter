(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(** The result buffers of the bridge for query captures, error reports, adapter
    responses, and failures, written in test code, and generators of their
    contents. Every generator shrinks. *)

(** The content of a buffer of a failure. *)
type failure =
  | Internal of string  (** an internal fault, with its message *)
  | Language of Sinter_bridge.Language.error  (** never [Name_not_utf_8] *)
  | Tree of Sinter_bridge.Tree.error
  | Query of Sinter_bridge.Query.error  (** never [Not_utf_8] *)
  | Run of Sinter_bridge.Query.run_error
  | Adapter of Sinter_bridge.Adapter.error

val encode_captures : Sinter_bridge.Query.capture list -> string
(** [encode_captures captures] is a buffer of query captures that holds
    [captures]. *)

val encode_report : Sinter_bridge.Tree.report -> string
(** [encode_report report] is a buffer of an error report that holds [report].
*)

val encode_response : string -> string
(** [encode_response bytes] is a buffer of an adapter response that holds
    [bytes]. *)

val encode_failure : failure -> string
(** [encode_failure failure] is a buffer of a failure that holds [failure]. *)

val captures : (Sinter_bridge.Query.capture list * string) QCheck2.Gen.t
(** At most four captures, and their buffer. The text of a capture is any bytes.
*)

val report : (Sinter_bridge.Tree.report * string) QCheck2.Gen.t
(** An error report, and its buffer. The lowest node is present exactly when the
    error flag is set. *)

val response : (string * string) QCheck2.Gen.t
(** Any bytes, and the buffer of a response that holds them. *)

val failure : (failure * string) QCheck2.Gen.t
(** A failure of one of the five families, never [Internal], and its buffer. *)

val internal : (string * string) QCheck2.Gen.t
(** The message of an internal fault, and the buffer of a failure that holds it.
*)

val damaged_captures : (Generators.damage * string) QCheck2.Gen.t
(** A buffer of query captures damaged in one of the seven ways. No damaged
    buffer is a valid buffer of query captures. *)

val damaged_report : (Generators.damage * string) QCheck2.Gen.t
(** A buffer of an error report damaged in one of the seven ways. *)

val damaged_response : (Generators.damage * string) QCheck2.Gen.t
(** A buffer of a response damaged in one of the six ways that apply to a buffer
    whose one string need not be UTF-8. *)

val damaged_failure : (Generators.damage * string) QCheck2.Gen.t
(** A buffer of a failure, never [Internal], damaged in one of the seven ways.
*)

val any_buffer : string QCheck2.Gen.t
(** Bytes that a decoder must survive: any bytes, a whole buffer of one of the
    four kinds, or such a buffer with bytes written over a run of it. *)

val print_failure : (failure * string) QCheck2.Print.t
(** The printer for a counterexample of {!failure}. *)

val print_report : (Sinter_bridge.Tree.report * string) QCheck2.Print.t
(** The printer for a counterexample of {!report}. *)

val print_captures : (Sinter_bridge.Query.capture list * string) QCheck2.Print.t
(** The printer for a counterexample of {!captures}. *)
