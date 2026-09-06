(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(** Parse source files with a tree-sitter grammar and report what a tree-sitter
    query captures. *)

exception Error of string
(** Something went wrong, and the string says what. The string is fit to show to
    the person who ran the command. *)

val read_file : string -> string
(** [read_file path] is the whole content of the file at [path].

    @raise Error if the file does not open, or does not read. *)

val grammar_name : string -> string
(** [grammar_name path] is the grammar name that the bridge needs, from the name
    of a grammar file. It is the base name without its extension, with each
    hyphen replaced by an underscore and a leading ["tree_sitter_"] removed. The
    name of ["packs/tree-sitter-json.wasm"] is therefore ["json"]. *)

val record_of_capture : path:string -> Sinter_bridge.capture -> Jsonl.record
(** [record_of_capture ~path capture] is the JSONL record for one capture in the
    file at [path]. The fields are:

    - [path]: the file, as it was named on the command line
    - [pat]: the index of the pattern in the query, from 0
    - [cap]: the capture name, without the [@]
    - [node]: the type of the node, for example ["string_content"]
    - [sb], [eb]: the start and the end of the node, as byte offsets from the
      start of the file. The end is exclusive
    - [line], [col]: the start of the node, from 1. The column counts bytes, not
      characters
    - [eline], [ecol]: the end of the node, from 1. The column is exclusive
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

val run :
  grammar:string ->
  query:string option ->
  paths:string list ->
  out_channel ->
  unit
(** [run ~grammar ~query ~paths channel] loads the grammar file at [grammar],
    then handles each file of [paths] in order. When [query] is the path of a
    query file, it writes one canonical JSONL line per capture. When [query] is
    [None], it writes the parse tree of each file as an S-expression, one tree
    per line.

    @raise Error on the first failure. *)
