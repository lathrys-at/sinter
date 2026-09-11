(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(* @cites json-handling *)

(** One request of the serve mode. A request is one line of JSON. This module
    reads such a line and gives a value that the rest of the library can use. It
    is the only module that reads JSON. *)

type rid =
  | Text of string
  | Number of int
      (** The caller's tag for one request. The request holds it in the field
          [rid], and every line of the answer carries it back in the field
          [rid], as the caller gave it. A [Text] holds valid UTF-8. A [Number]
          is between [-(2^53-1)] and [2^53-1]. *)

type output =
  | Captures of string
      (** the path of a query file; report what the query captures *)
  | Tree  (** report the parse tree of each file as an S-expression *)

type op =
  | Parse of { grammar : string; output : output; files : string list }
      (** [grammar] is the path of a grammar file. [files] holds one path or
          more. Every string is valid UTF-8. *)

type t = { rid : rid; op : op }
(** One request: the caller's tag, and the work to do. *)

type cause =
  | Not_json
  | Not_an_object
  | No_rid
  | Bad_rid
  | No_op
  | Bad_op
  | Unknown_op of string
  | Unknown_field of string
  | Repeated_field of string
  | Missing_field of string
  | Wrong_type of { field : string; wanted : string }
  | Empty_field of string
  | Not_text of string
  | Both_query_and_tree
  | Neither_query_nor_tree
      (** Why a line is not a request. [Wrong_type] names the field and the kind
          of value the field takes, for example ["an array of strings"].
          [Not_text] names a field whose string is not valid UTF-8. *)

type error = { rid : rid option; cause : cause }
(** Why a line is not a request, and the tag to answer with. [rid] is [None]
    when the line carries no tag that this module can read back. *)

val of_line : string -> (t, error) result
(** [of_line line] reads one line of JSON as a request. [line] may end with a
    line feed or not. This function returns a request or an error for every
    string, and it raises nothing. *)

val message : cause -> string
(** [message cause] is one sentence for the person who runs the tool. It says
    what is wrong with the request. It names no file of the repository. *)

val value_of_rid : rid -> Jsonl.value
(** [value_of_rid rid] is [rid] as a value of a JSONL record. *)
