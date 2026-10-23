(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(** Run a tree-sitter query file over source files. *)

(** Why a query file or a source file gives no result. *)
type error =
  | Unreadable of Text_file.error
      (** the file does not read, or it is not UTF-8 text *)
  | Empty  (** the query file holds nothing but white space *)
  | Not_compiled of Sinter_bridge.Query.error  (** the query does not compile *)
  | Not_parsed of Sinter_bridge.Tree.error  (** the parse gives no tree *)
  | Not_run of Sinter_bridge.Query.run_error
      (** the query does not run over the tree *)

val compile :
  Sinter_bridge.Language.t ->
  path:string ->
  (Sinter_bridge.Query.t, error) result
(** [compile language ~path] reads the query file at [path] as UTF-8 text and
    compiles it for [language]. The caller owns the result.

    @raise Invalid_argument if [language] is closed. *)

val captures :
  Sinter_bridge.Language.t ->
  Sinter_bridge.Query.t ->
  path:string ->
  (string * Sinter_bridge.Query.capture list, error) result
(** [captures language query ~path] reads the source file at [path] as UTF-8
    text, parses it with [language], and runs [query] over the tree. It gives
    the text of the file and the captures, in the order of their matches. The
    tree is freed before the function returns.

    @raise Invalid_argument if [language], its engine, or [query] is closed. *)

val tree : Sinter_bridge.Language.t -> path:string -> (string, error) result
(** [tree language ~path] reads the source file at [path] as UTF-8 text, parses
    it with [language], and gives the tree as an S-expression. The tree is freed
    before the function returns.

    @raise Invalid_argument if [language] or its engine is closed. *)

val message : path:string -> error -> string
(** [message ~path error] says why the file at [path] gives no result, for the
    person who runs the tool. The message names [path]. *)
