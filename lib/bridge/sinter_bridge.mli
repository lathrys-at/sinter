(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(* @cites parser-bridge *)

(** The parser bridge. The bridge loads a tree-sitter grammar that is compiled
    to WebAssembly, parses a source text with it, and runs a tree-sitter query
    over the parse tree. It also computes the SHA-256 digest of a string, and
    reads a TOML document. *)

module Utf_8 = Utf_8

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

type range = {
  start_byte : int;  (** the start, a byte offset from 0 *)
  end_byte : int;  (** the end, exclusive, a byte offset *)
  start_row : int;  (** the start row, from 0 *)
  start_column : int;  (** the start column, in bytes, from 0 *)
  end_row : int;  (** the end row, from 0 *)
  end_column : int;  (** the end column, in bytes, exclusive *)
}
(** A range of a source text. A row ends at a line feed. *)

(** Grammars. *)
module Language : sig
  (** How the WebAssembly runtime failed to load a grammar. *)
  type wasm_kind =
    | Parse  (** the bytes are not a module that the runtime can read *)
    | Compile  (** the module does not compile *)
    | Instantiate  (** the module does not start *)
    | Other

  (** Why a grammar does not load. *)
  type error =
    | Wasm of { kind : wasm_kind; message : string }
        (** the message of the runtime, as UTF-8 text *)
    | Version of int
        (** the grammar has this version of the tree-sitter interface, and the
            bridge reads the versions 13 to 15 *)
    | Name_not_utf_8  (** the grammar name is not UTF-8 text *)

  val message : error -> string
  (** [message error] says why the grammar does not load, for the person who
      runs the tool. *)
end

(** Parse trees. *)
module Tree : sig
  (** Why a parse gives no tree. *)
  type error =
    | Did_not_finish  (** the parser stopped before the end of the text *)
    | Too_long  (** the text is 2^32 bytes or more *)

  type node = {
    node_type : string;  (** the type of the node, for example [pair] *)
    range : range;
  }
  (** One node of a tree. *)

  type error_kind =
    | Error_node  (** an [ERROR] node *)
    | Missing_node  (** a [MISSING] node *)

  type report = {
    has_error : bool;
        (** the error flag of the root: [true] when the tree holds an [ERROR]
            node or a [MISSING] node, shown or not *)
    errors : (error_kind * node) list;
        (** each [ERROR] node, and each [MISSING] node that no [ERROR] node
            holds, in the order of the text. No node of the list holds another.
        *)
    lowest : node option;
        (** the first lowest error node in the order of the text: a node whose
            error flag is set, when no child that the tree shows has its flag
            set. It is [Some _] exactly when [has_error] is [true]. *)
  }
  (** The parse failures of a tree. *)

  val message : error -> string
  (** [message error] says why the parse gave no tree, for the person who runs
      the tool. *)
end

(** Queries. *)
module Query : sig
  (** The kind of a tree-sitter query error. *)
  type kind =
    | Syntax
    | Node_type
    | Field
    | Capture
    | Predicate
    | Structure
    | Language

  (** Why a query does not compile. A row and a column count from 0, and a
      column counts bytes. *)
  type error =
    | Invalid of {
        kind : kind;
        row : int;
        column : int;
        offset : int;  (** a byte offset into the query text *)
        message : string;  (** the message of tree-sitter *)
      }
        (** tree-sitter refuses the query. For [Predicate], the position is the
            start of the pattern; for [Language], it is 0. *)
    | Not_allowed of {
        operator : string;
            (** the predicate or the directive, without its [#], for example
                ["set!"] *)
        pattern : int;  (** the index of the pattern, from 0 *)
        offset : int;  (** the start of the pattern, a byte offset *)
        row : int;  (** the row of the start of the pattern *)
        column : int;  (** the column of the start of the pattern *)
      }
        (** a pattern uses a predicate that is not one of [#eq?], [#not-eq?],
            [#any-eq?], [#any-not-eq?], [#match?], [#not-match?], [#any-match?],
            [#any-not-match?], [#any-of?], and [#not-any-of?], or it uses a
            directive such as [#set!] *)
    | Not_utf_8 of int
        (** the query text is not UTF-8. The integer is the byte offset of its
            first sequence that is not well-formed. *)

  (** Why a query does not run over a tree. *)
  type run_error =
    | Language_mismatch
        (** the query and the tree come from different grammars *)

  type capture = {
    match_number : int;
        (** the number of the match, from 0. The bridge counts the matches in
            the order in which it finds them, with no gap. *)
    pattern : int;  (** the index of the pattern in the query, from 0 *)
    name : string;  (** the capture name, without the [@] *)
    node_type : string;  (** the type of the node *)
    range : range;  (** the range of the node *)
    text : string;
        (** the bytes of the range, from the text that the tree was parsed from.
            They are not UTF-8 when that text is not. *)
  }
  (** One capture of one match. *)

  val message : error -> string
  (** [message error] says why the query does not compile, for the person who
      runs the tool. *)

  val run_message : run_error -> string
  (** [run_message error] says why the query does not run over the tree, for the
      person who runs the tool. *)
end

(** Runner adapters: WebAssembly modules that read test reports. *)
module Adapter : sig
  (** Why a module is not a runner adapter. *)
  type invalid =
    | Not_a_module of string
        (** the bytes are not a module that the runtime compiles. The string is
            the message of the runtime. *)
    | Imports of string list
        (** the module imports something. Each string names one import as
            ["module.name"]. The list is not empty. *)
    | Missing_export of string  (** the module does not export this name *)
    | Wrong_export_type of string
        (** the export of this name is not of the type that an adapter exports
        *)

  (** One of the two inputs of a call. *)
  type input = Request | Report

  (** Why a load or a call of an adapter fails. *)
  type error =
    | Invalid of invalid
    | Out_of_fuel  (** the module ran past its limit of fuel *)
    | Trap of string
        (** the module trapped, or its instance did not start. The string is the
            message of the runtime. *)
    | Memory_limit of int
        (** the module asked for a memory of this many bytes, past its limit *)
    | Alloc of { input : input; address : int; length : int; memory_size : int }
        (** [sinter_alloc] gave 0, or an address whose [length] bytes do not lie
            inside a memory of [memory_size] bytes *)
    | Response_outside_memory of {
        address : int;
        length : int;
        memory_size : int;
      }  (** the response does not lie inside a memory of [memory_size] bytes *)

  (** The two functions that a call can run. *)
  type call = Recognise | Bind

  val message : error -> string
  (** [message error] says why the load or the call failed, for the person who
      runs the tool. *)
end

(** The decoders of the result buffers, in the layouts that the bridge writes.
    Each decoder takes one whole buffer of its kind, and raises [Error] for any
    other bytes. *)
module Decode : sig
  val captures : string -> Query.capture list
  (** [captures buffer] is the captures of a query run, in the order that the
      buffer holds them.

      @raise Error
        if [buffer] is not one whole buffer of captures, or if a capture name or
        a node type is not UTF-8. *)

  val tree : string -> string
  (** [tree buffer] is the parse tree of a buffer of a parse tree, as an
      S-expression.

      @raise Error
        if [buffer] is not one whole buffer of a parse tree, or if the tree is
        not UTF-8. *)

  val digest : string -> string
  (** [digest buffer] is the 32 bytes of a buffer of a digest.

      @raise Error if [buffer] is not one whole buffer of a digest. *)

  val report : string -> Tree.report
  (** [report buffer] is the error report of a buffer of an error report.

      @raise Error
        if [buffer] is not one whole buffer of an error report, if a node type
        is not UTF-8, or if the lowest error node is present while the error
        flag of the root is not set, or the reverse. *)

  val response : string -> string
  (** [response buffer] is the bytes of an adapter response.

      @raise Error if [buffer] is not one whole buffer of a response. *)

  val language_error : string -> Language.error
  (** [language_error buffer] is the error of a grammar load that a buffer of a
      failure holds.

      @raise Error
        if [buffer] is not one whole buffer of a failure, if the failure is an
        internal fault of the bridge (the message of [Error] is then the message
        of the fault), or if it is not the failure of a grammar load. *)

  val tree_error : string -> Tree.error
  (** [tree_error buffer] is the error of a parse, as {!language_error} gives
      the error of a load. *)

  val query_error : string -> Query.error
  (** [query_error buffer] is the error of a query compilation, as
      {!language_error} gives the error of a load. *)

  val run_error : string -> Query.run_error
  (** [run_error buffer] is the error of a query run, as {!language_error} gives
      the error of a load. *)

  val adapter_error : string -> Adapter.error
  (** [adapter_error buffer] is the error of an adapter load or call, as
      {!language_error} gives the error of a load. *)
end

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
