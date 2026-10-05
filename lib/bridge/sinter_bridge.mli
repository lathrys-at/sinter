(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(* @cites parser-bridge *)

(** The parser bridge. The bridge loads a tree-sitter grammar that is compiled
    to WebAssembly, parses a source text with it, and runs a tree-sitter query
    over the parse tree. It also computes the SHA-256 digest of a string, and
    reads a TOML document. *)

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
    query cursor produced them. Every string of every capture is valid UTF-8.

    @raise Error
      if the parse or the query fails, or if a range of [source] that a capture
      covers is not valid UTF-8.
    @raise Invalid_argument if [query] is empty. *)

val tree : language -> source:string -> string
(** [tree language ~source] parses [source] with [language] and gives the parse
    tree as an S-expression. The result is valid UTF-8.

    @raise Error if the parse fails, or if the parse tree is not valid UTF-8. *)

val decode_captures : string -> capture list
(** [decode_captures buffer] is the captures that [buffer] holds. [buffer] is
    one result buffer of a capture run, in the layout that the bridge writes.
    The captures come back in the order in which the buffer holds them.

    @raise Error
      if [buffer] is not one whole capture result buffer of that layout, or if a
      string in it is not valid UTF-8. *)

val decode_tree : string -> string
(** [decode_tree buffer] is the parse tree that [buffer] holds, as an
    S-expression. [buffer] is one result buffer of a parse tree run, in the
    layout that the bridge writes.

    @raise Error
      if [buffer] is not one whole parse tree result buffer of that layout, or
      if the tree in it is not valid UTF-8. *)

val sha256 : string -> string
(** [sha256 data] is the SHA-256 digest of the bytes of [data], as 32 bytes.

    @raise Error if the bridge stops on an internal fault. *)

val decode_digest : string -> string
(** [decode_digest buffer] is the digest that [buffer] holds, as 32 bytes.
    [buffer] is one result buffer of a digest, in the layout that the bridge
    writes.

    @raise Error
      if [buffer] is not one whole digest result buffer of that layout. *)

(** A TOML document as the bridge reads it: byte offsets into the text, and the
    messages of the TOML reader that the bridge links. *)
module Toml_raw : sig
  type offset =
    | Utc  (** [Z] *)
    | Minutes of int  (** an offset from UTC, in minutes *)

  type datetime = {
    date : (int * int * int) option;  (** the year, the month, the day *)
    time : (int * int * int * int) option;
        (** the hour, the minute, the second, the nanosecond *)
    offset : offset option;
  }
  (** A date, a time, or both. [offset] is [Some _] only when [date] and [time]
      are both [Some _]. *)

  type value =
    | String of string
    | Integer of int64
    | Float of float
    | Boolean of bool
    | Datetime of datetime
    | Array of item list
    | Table of table  (** a table that a table header or a dotted key makes *)
    | Inline_table of table
    | Array_of_tables of table list

  and item = {
    value : value;
    start_byte : int;  (** the start of the value, a byte offset from 0 *)
    end_byte : int;  (** the end of the value, exclusive, a byte offset *)
  }
  (** A value and its byte span. The span of an inline table holds its braces. A
      table that a header or a dotted key makes, and an array of tables, take
      the byte span of their key. *)

  and table = entry list
  (** The keys of one table, in the order in which the reader holds them. *)

  and entry = {
    name : string;  (** the key, decoded *)
    key_start : int;  (** the start of the key in the text, a byte offset *)
    key_end : int;  (** the end of the key, exclusive, a byte offset *)
    item : item;
  }

  (** Why a text is not a TOML document. *)
  type error =
    | Crate_error of { start_byte : int; end_byte : int; message : string }
        (** the reader's own error: the byte span where it stopped, and its
            message, which can hold more than one line *)
    | Header_table of {
        start_byte : int;
        end_byte : int;
        key : string;
        table : string list;
        array : bool;
        rest : string list;
      }
        (** a dotted key, at the byte span [start_byte] to [end_byte] and
            written [key], adds a key to the table that [table] names from the
            top level, and a table header made that table. [array] is [true]
            when the table is the last table of an array of tables. [rest] is
            the names of the dotted key after that table. *)

  val parse : string -> (table, error) result
  (** [parse text] reads [text] as a TOML document and gives its top-level
      table, or the error. Every byte offset in the result is inside [text].

      @raise Error
        if [text] is not UTF-8, if it is 4 GiB or more, or if the bridge stops
        on an internal fault. *)

  val decode : length:int -> string -> (table, error) result
  (** [decode ~length buffer] is the document or the error that [buffer] holds.
      [buffer] is one result buffer of a TOML text of [length] bytes, in the
      layout that the bridge writes.

      @raise Error
        if [buffer] is not one whole TOML result buffer of that layout, if a
        string in it is not valid UTF-8, or if a byte span in it ends before it
        starts or runs past [length]. *)
end
