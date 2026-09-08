(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(** Parse source files with a tree-sitter grammar and report what a tree-sitter
    query captures. *)

exception Error of string
(** Something went wrong, and the string says what. The string is fit to show to
    the person who ran the command. *)

val read_file : string -> string
(** [read_file path] is the whole content of the file at [path].

    @raise Error if the file does not open, or if reading it fails. *)

val name_of_wasm : string -> string option
(** [name_of_wasm wasm] is the name of the grammar in the wasm module [wasm],
    read from the export whose name starts with ["tree_sitter_"]. It is [None]
    when the module holds no such export, when the module is not one the reader
    can follow, and when the name holds a NUL byte, which the bridge cannot
    take. *)

val grammar_name : string -> string
(** [grammar_name path] is a grammar name from the name of a grammar file. It is
    the base name without its extension, with each hyphen replaced by an
    underscore and a leading ["tree_sitter_"] removed. The name of
    ["packs/tree-sitter-json.wasm"] is therefore ["json"]. {!run} uses this only
    for a module that {!name_of_wasm} cannot read. *)

val record_of_capture :
  path:string -> source:string -> Sinter_bridge.capture -> Jsonl.record
(** [record_of_capture ~path ~source capture] is the JSONL record for one
    capture in the file at [path]. [source] is the text of that file. The fields
    are:

    - [path]: the file, as it was named on the command line
    - [pat]: the index of the pattern in the query, from 0
    - [cap]: the capture name, without the [@]
    - [node]: the type of the node, for example ["string_content"]
    - [sb], [eb]: the start and the end of the node, as byte offsets from the
      start of the file. The end is exclusive
    - [line], [col]: the start of the node, from 1. The column counts bytes, not
      characters
    - [eline]: the line that holds the last byte of the node, from 1
    - [ecol]: one byte past the last byte of the node, in the line [eline], from
      1
    - [text]: the source text of the node *)

val captures :
  Sinter_bridge.language -> query:string -> path:string -> Jsonl.record list
(** [captures language ~query ~path] reads the file at [path], parses it, runs
    [query] over the parse tree, and gives one record per capture, in the order
    the query produced them.

    @raise Error if the file does not read, or the parse fails. *)

val tree : Sinter_bridge.language -> path:string -> string
(** [tree language ~path] reads the file at [path], parses it, and gives the
    parse tree as an S-expression.

    @raise Error if the file does not read, or the parse fails. *)

(** One result of one file. *)
type item =
  | Capture of Jsonl.record
      (** one capture of the query, in the file the record names *)
  | Tree of { path : string; sexp : string }
      (** the parse tree of the file at [path], as an S-expression *)

val load : Sinter_bridge.t -> grammar:string -> Sinter_bridge.language
(** [load engine ~grammar] reads the grammar file at [grammar] and loads it into
    [engine]. The grammar name comes from the module, and from the file name
    when the module does not carry it. The result stays valid until [engine] is
    closed.

    @raise Error if the file does not read, or the grammar does not load. *)

val fold :
  Sinter_bridge.language ->
  query:string option ->
  paths:string list ->
  f:(item -> unit) ->
  unit
(** [fold language ~query ~paths ~f] handles each file of [paths] in order and
    calls [f] on each item, in the order the items come. When [query] is the
    path of a query file, an item is one capture of that query. When [query] is
    [None], an item is the parse tree of one file. [f] sees no item of a file
    that fails.

    @raise Error
      if a file name is not UTF-8 text, if a file does not read, if the query
      file is empty or does not compile, or if a parse fails. An exception that
      [f] raises passes through. *)

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
    each file as an S-expression, one tree per line. It closes the engine before
    it returns.

    @raise Error on the first failure, and on a failure to write to [channel].
*)
