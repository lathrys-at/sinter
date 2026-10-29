(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(** Load a grammar file into an engine. *)

(** Why a grammar file gives no grammar. *)
type error =
  | Unreadable of Text_file.error  (** the file does not read *)
  | Not_loaded of Sinter_bridge.Language.error
      (** the bridge does not load the grammar *)

val load :
  Sinter_bridge.t -> path:string -> (Sinter_bridge.Language.t, error) result
(** [load engine ~path] reads the grammar file at [path] and loads it into
    [engine]. The grammar name comes from the module, and from the file name
    when the module does not carry it. The caller owns the result.

    @raise Invalid_argument if [engine] is closed. *)

val message : path:string -> error -> string
(** [message ~path error] says why the grammar file at [path] gives no grammar,
    for the person who runs the tool. The message names [path]. *)

val help : error -> string
(** [help error] says what the person who runs the tool can do about [error]. It
    is never empty. *)
