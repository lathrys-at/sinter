(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(* @cites parser-bridge *)

(** The parser bridge. The bridge loads a tree-sitter grammar that is compiled
    to WebAssembly, parses a source text with it, and runs a tree-sitter query
    over the parse tree. *)

exception Error of string
(** The bridge failed. The string is the message of the failure. *)

type t
(** An engine. An engine holds the WebAssembly runtime and every grammar that
    was loaded into it. An engine is not safe to use from two threads at the
    same time. *)

type language
(** A grammar that was loaded into an engine. The value keeps its engine alive.
*)

type capture = {
  pattern : int;  (** the index of the pattern in the query, from 0 *)
  name : string;  (** the capture name, without the [@] *)
  node_type : string;  (** the type of the node, for example [string] *)
  start_byte : int;  (** the start of the node, a byte offset from 0 *)
  end_byte : int;  (** the end of the node, exclusive, a byte offset *)
  start_row : int;  (** the start row of the node, from 0 *)
  start_column : int;  (** the start column, in bytes, from 0 *)
  end_row : int;  (** the end row of the node, from 0 *)
  end_column : int;  (** the end column, in bytes, exclusive *)
  text : string;  (** the source text of the node *)
}
(** One capture of one pattern of a query. *)

val create : unit -> t
(** [create ()] makes an engine.

    @raise Error if the WebAssembly runtime does not start. *)

val close : t -> unit
(** [close engine] frees the engine and every grammar in it. Every later call
    that uses the engine raises [Invalid_argument]. The garbage collector frees
    an engine that no value refers to, so a program does not have to call this
    function. *)

val load : t -> name:string -> wasm:string -> language
(** [load engine ~name ~wasm] loads a grammar into [engine]. [name] is the
    grammar name without the [tree_sitter_] prefix, for example ["json"]. [wasm]
    is the content of the grammar's [.wasm] file.

    @raise Error if the grammar does not load.
    @raise Invalid_argument if [name] holds a NUL byte. *)

val captures : language -> source:string -> query:string -> capture list
(** [captures language ~source ~query] parses [source] with [language] and runs
    [query] over the parse tree. [query] is tree-sitter query source, the
    content of a [.scm] file. The captures come back in the order in which the
    query cursor produced them.

    @raise Error if the parse or the query fails.
    @raise Invalid_argument if [query] is empty. *)

val tree : language -> source:string -> string
(** [tree language ~source] parses [source] with [language] and gives the parse
    tree as an S-expression.

    @raise Error if the parse fails. *)
