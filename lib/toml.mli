(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(* @cites toml-reader *)

(** A TOML 1.0.0 document, with the position of every key and value. *)

type position = { line : int; column : int }
(** A place in the text. [line] counts from 1. [column] counts from 1, in
    Unicode code points from the start of the line. A byte order mark at the
    start of the text is not a column. *)

type span = { start : position; stop : position }
(** A piece of the text. [start] is the place of its first character.
    [stop.line] is the line of its last character, and [stop.column] is the
    column one past that character. *)

type key = { name : string; at : span }
(** One part of a key. [name] is the part, decoded: no quotes, and every escape
    resolved. [at] is the span of the part, its quotes included. For a dotted
    key or a table header such as [[a.b.c]], each part has its own span. A table
    that a table header names takes the span of the part in that header. Any
    other part takes the span of the place where the text first writes it. *)

type date = { year : int; month : int; day : int }
type time = { hour : int; minute : int; second : int; nanosecond : int }

(** The offset of a date and time from UTC. *)
type offset =
  | Utc  (** [Z] *)
  | Minutes of int  (** an offset in minutes, for example [-480] *)

type datetime = {
  date : date option;
  time : time option;
  offset : offset option;
}
(** A date, a time, or both. [offset] is [Some _] only when [date] and [time]
    are both [Some _]. *)

type node
(** A value, with its place in the text. *)

type value =
  | String of string
  | Integer of int64
  | Float of float
  | Boolean of bool
  | Datetime of datetime
  | Array of node list
  | Table of table
  | Array_of_tables of table list

and table = (key * node) list
(** The keys of a table, in the order of the start of their spans. No name
    occurs twice. *)

val value : node -> value
(** [value node] is the value that [node] holds. *)

val span : node -> span
(** [span node] is the span of the value. For a string, it holds the quotes; for
    an array, the brackets; for an inline table, the braces. A table that a
    table header or a dotted key makes, and an array of tables, are not one
    piece of text: they take the span of their key. *)

val key_start : node -> position
(** [key_start node] is the place of the first character of the whole key that
    writes [node], as its line writes it. For [a.b.c = 1] it is the place of
    [a], for the node of [c]. For a table that a table header or a dotted key
    makes, for an array of tables, and for a member of an array, it is the start
    of [span node]. *)

(** The kind of a value. *)
module Kind : sig
  type t =
    | String
    | Integer
    | Float
    | Boolean
    | Datetime
    | Array
    | Table
    | Array_of_tables

  val of_value : value -> t
  (** [of_value value] is the kind of [value]. *)

  val name : t -> string
  (** [name kind] names [kind] with its article, for a message: ["a string"],
      ["an integer"], ["a float"], ["a boolean"], ["a date or a time"],
      ["an array"], ["a table"], ["an array of tables"]. *)
end

val string_position : node -> int -> position option
(** [string_position node i] is the place of byte [i] of the string that [node]
    holds, when the text writes that string as it is, on one line: a literal
    string, or a basic string with no escape, that holds no line break. When [i]
    is the length of the string, it is the place one past the last character.
    The result is [None] for every other node.

    @raise Invalid_argument
      if [node] holds a string and [i] is below 0 or above its length. *)

(** {1 Errors} *)

(** What the text was in the middle of, where the error is. *)
type construct =
  | A_value
  | A_basic_string
  | A_literal_string
  | A_multiline_basic_string
  | A_multiline_literal_string
  | An_escape
  | A_short_unicode_escape  (** [\u] and four hexadecimal digits *)
  | A_long_unicode_escape  (** [\U] and eight hexadecimal digits *)
  | An_integer
  | A_hexadecimal_integer
  | An_octal_integer
  | A_binary_integer
  | A_float
  | A_date_or_time
  | A_time
  | A_time_offset
  | An_array
  | An_inline_table
  | A_key
  | A_table_header

(** What the text could hold at the place of the error. *)
type expected =
  | End_of_line
  | Comment
  | Character of char  (** one character, for example [']'] *)
  | Double_bracket  (** [\]\]] *)
  | Digit
  | Leading_digit  (** a digit at the start of a number *)

(** What breaks the rules, beyond the place. *)
type cause =
  | Duplicate_key of string  (** the key, as the reader names it *)
  | Not_a_table of { key : string; found : Kind.t }
      (** a dotted key or a table header goes through [key], the dotted path of
          a key that holds a value of the kind [found] *)
  | Inline_table of string
      (** a dotted key or a table header adds a key to the inline table at this
          dotted path *)
  | Out_of_range
  | Too_deep  (** keys, arrays, or inline tables nest too deep *)
  | Integer_too_large
  | Integer_too_small

(** Why a text is not a TOML 1.0.0 document. *)
type error =
  | Not_utf_8 of { at : position }
      (** the text is not UTF-8; [at] is the place of the first byte that is not
      *)
  | Syntax of {
      at : position;
      construct : construct option;
      expected : expected list;
      cause : cause option;
    }
  | Header_table of {
      at : position;
      key : string;
      table : string list;
      array : bool;
      rest : string list;
    }
      (** the dotted key [key], as the text writes it at [at], adds a key to the
          table [table], which a table header made. [array] is [true] when that
          header is the header of an array of tables. [rest] is the names of the
          dotted key after the table. *)
  | Unrecognized of { at : position }
      (** the reader stopped with a message that this module does not know *)

val read_message :
  string -> (construct option * expected list * cause option) option
(** [read_message message] reads a message of the TOML reader that the bridge
    links into its parts: what the text was in the middle of, what could come
    next, and the cause. It is [None] when a part of [message] is not a form
    that this module knows. {!parse} gives [Syntax] for a message that this
    function reads, and [Unrecognized] for any other. *)

val error_position : error -> position
(** [error_position error] is the place of [error] in the text. *)

val error_message : error -> string
(** [error_message error] says what is wrong, in one line, without the place. *)

val parse : string -> (table, error) result
(** [parse text] reads [text] as a TOML 1.0.0 document and gives its top-level
    table. A form that only TOML 1.1 allows is an error. So is a dotted key that
    adds a key to a table that a table header made.

    @raise Sinter_bridge.Error
      if [text] is 4 GiB or more, or if the bridge stops on an internal fault.
*)

val render_path : string list -> string
(** [render_path names] is the key path of [names] as TOML writes it: each name
    bare when it is a bare key, in double quotes otherwise, and the names joined
    with [.]. *)
