(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(** Parse source files with a tree-sitter grammar and report what a tree-sitter
    query captures. *)

exception Error of Error_text.t
(** Something went wrong. The error says what, and what to do, for the person
    who ran the command. It has no place. *)

(** One result of one file. *)
type item =
  | Capture of Jsonl.record
      (** one capture of the query, in the file the record names *)
  | Tree of { path : string; sexp : string }
      (** the parse tree of the file at [path], as an S-expression *)

val fold :
  Sinter_bridge.Language.t ->
  query:string option ->
  paths:string list ->
  f:(item -> unit) ->
  unit
(** [fold language ~query ~paths ~f] handles each file of [paths] in order and
    calls [f] on each item, in the order the items come. When [query] is the
    path of a query file, an item is one capture of that query. When [query] is
    [None], an item is the parse tree of one file. [f] sees no item of a file
    that fails. [fold] checks every name in [paths] before it reads a file, so a
    name that is not UTF-8 text fails before [f] sees any item.

    Every string of every record of an item is valid UTF-8, and so is the
    S-expression of a tree item. [fold] compiles the query once, and frees the
    query and each tree before it returns.

    @raise Error
      if a file name is not UTF-8 text, if a file does not read, if the query
      file is empty or does not compile, if a parse fails, or if a string of a
      record would not be valid UTF-8. An exception that [f] raises passes
      through.
    @raise Invalid_argument if [language] or its engine is closed. *)

val run :
  grammar:string ->
  query:string option ->
  paths:string list ->
  out_channel ->
  unit
(** [run ~grammar ~query ~paths channel] makes an engine of its own, loads the
    grammar file at [grammar] into it, then handles each file of [paths] in
    order. When [query] is the path of a query file, it writes one canonical
    JSONL line per capture. When [query] is [None], it writes the parse tree of
    each file as an S-expression, one tree per line. It frees the grammar and
    the engine before it returns.

    @raise Error on the first failure, and on a failure to write to [channel].
*)
