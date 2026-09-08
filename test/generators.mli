(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(** Generators for the property tests. Every generator shrinks. *)

(** {1 Strings} *)

val utf_8_string : string QCheck2.Gen.t
(** A string of valid UTF-8, of at most eight code points. The code points come
    from four ranges: ASCII, the two-byte range, the three-byte range without
    the surrogates, and the range at U+10000 and above. *)

val ascii_string : string QCheck2.Gen.t
(** A string of at most four printable ASCII characters. *)

val key : string QCheck2.Gen.t
(** A field name of at most three code points, drawn from ten code points. Two
    names collide often, and the set holds the pairs for which UTF-16 code unit
    order and UTF-8 byte order disagree. *)

val not_utf_8_string : string QCheck2.Gen.t
(** A string that is not valid UTF-8. The construction gives this, so the
    generator never yields a valid string. *)

(** {1 Records} *)

val jsonl_int : int QCheck2.Gen.t
(** An integer in the range that a canonical record allows, from [-(2^53-1)] to
    [2^53-1]. The corners of the range come up often. *)

val jsonl_int_out_of_range : int QCheck2.Gen.t
(** An integer outside the range that a canonical record allows. *)

val scalar : Sinter_core.Jsonl.scalar QCheck2.Gen.t
(** One value that is not an array. Every string in it is valid UTF-8, and every
    integer is in range. *)

val value : Sinter_core.Jsonl.value QCheck2.Gen.t
(** One field value, a scalar or an array of at most four scalars. *)

val record : Sinter_core.Jsonl.record QCheck2.Gen.t
(** A record of at most six fields. The field names are distinct, every string
    is valid UTF-8, and every integer is in range, so
    {!Sinter_core.Jsonl.to_string} never raises on it. *)

val record_with_a_repeated_field : Sinter_core.Jsonl.record QCheck2.Gen.t
(** A record that holds one field name twice, and that breaks no other rule. *)

val record_with_an_integer_out_of_range : Sinter_core.Jsonl.record QCheck2.Gen.t
(** A record that holds one integer outside the allowed range, and that breaks
    no other rule. *)

val record_with_a_string_that_is_not_utf_8 :
  Sinter_core.Jsonl.record QCheck2.Gen.t
(** A record that holds one string that is not valid UTF-8, in a field name, a
    scalar, or an array item, and that breaks no other rule. *)

val print_record : Sinter_core.Jsonl.record QCheck2.Print.t
(** The printer for a counterexample of type {!Sinter_core.Jsonl.record}. *)

(** {1 The result buffer of the bridge} *)

val encode_captures : Sinter_bridge.capture list -> string
(** [encode_captures captures] is a result buffer that holds [captures], in the
    layout that the bridge writes. *)

val encode_tree : string -> string
(** [encode_tree text] is a result buffer that holds the one parse tree [text],
    in the layout that the bridge writes. *)

val capture : Sinter_bridge.capture QCheck2.Gen.t
(** One capture. Every integer field is in the range of an unsigned 32-bit
    integer, and every string field is valid UTF-8. *)

val captures_buffer : (Sinter_bridge.capture list * string) QCheck2.Gen.t
(** A list of at most four captures, and the result buffer that holds them. *)

val tree_buffer : (string * string) QCheck2.Gen.t
(** A parse tree text, and the result buffer that holds it. *)

(** How a buffer was damaged. *)
type damage =
  | Truncated  (** bytes were cut from the end *)
  | Length_out_of_range  (** the length of one string runs past the end *)
  | Not_utf_8  (** one string is no longer valid UTF-8 *)
  | Wrong_magic  (** one byte of the first four was changed *)
  | Wrong_kind  (** the kind field names another kind *)
  | Trailing_bytes  (** bytes were added after the last record *)

val damaged_captures_buffer : (damage * string) QCheck2.Gen.t
(** A capture result buffer that was damaged in one of the six ways, and the way
    it was damaged. No damaged buffer is a valid capture result buffer. *)

val damaged_tree_buffer : (damage * string) QCheck2.Gen.t
(** A parse tree result buffer that was damaged in one of the six ways, and the
    way it was damaged. No damaged buffer is a valid parse tree result buffer.
*)

val print_buffer : string QCheck2.Print.t
(** The printer for a counterexample that is a result buffer. It gives the bytes
    as hexadecimal. *)

val print_damaged : (damage * string) QCheck2.Print.t
(** The printer for a counterexample of {!damaged_captures_buffer} and
    {!damaged_tree_buffer}. *)

val print_captures : Sinter_bridge.capture list QCheck2.Print.t
(** The printer for a counterexample that is a list of captures. *)

val buffer_bytes : string QCheck2.Gen.t
(** Bytes that a decoder of a result buffer must survive: any bytes; the four
    bytes of the magic and then any bytes; a whole buffer with bytes written
    over a run of it; a whole capture buffer; and a whole parse tree buffer. *)

(** {1 Source text, and a capture inside it} *)

val rows_before : string -> int -> int
(** [rows_before text offset] is the number of line feeds in [text] before
    [offset]. *)

val start_of_line : string -> int -> int
(** [start_of_line text offset] is the offset where the line that holds the byte
    at [offset] starts. It is [0] for a text with no line feed before [offset].
*)

val source_text : string QCheck2.Gen.t
(** A source text of at most sixty pieces. A piece is the line feed, the space,
    the tab, or a code point of one, two, three, or four bytes. The text is
    always valid UTF-8. *)

val capture_in : string -> Sinter_bridge.capture QCheck2.Gen.t
(** [capture_in source] is a capture of [source]. The byte range starts and ends
    at a code point boundary, as a capture of the bridge does. The rows and the
    columns are the rows and the byte columns of that range in [source], and the
    text is the bytes of that range. *)

val source_and_capture : (string * Sinter_bridge.capture) QCheck2.Gen.t
(** A source text, and a capture inside it. *)

val print_source_and_capture : (string * Sinter_bridge.capture) QCheck2.Print.t
(** The printer for a counterexample of {!source_and_capture}. *)

(** {1 Text for the bridge} *)

val json_source : string QCheck2.Gen.t
(** A JSON document that nests at most three deep. Each element of an array and
    each pair of an object sits on a line of its own, and a string in it holds
    code points of one, two, three, and four bytes. *)

val any_utf_8_text : string QCheck2.Gen.t
(** Text of valid UTF-8, of at most forty pieces. The punctuation of JSON comes
    up often, so the text is often a document that almost parses. *)

val any_text : string QCheck2.Gen.t
(** Text of any bytes, valid UTF-8 or not, of at most forty pieces. The
    punctuation of JSON comes up often, so the text is often a document that
    almost parses. A capture of this text can hold bytes that are not UTF-8, so
    only a parse tree comes back for all of it. *)

(** {1 WebAssembly modules} *)

val wasm_module : before:bool -> name:string -> string
(** [wasm_module ~before ~name] is a WebAssembly module that exports one
    function called ["tree_sitter_"] and [name]. When [before] is [true], a
    custom section stands before the export section. *)

val grammar_export_name : string QCheck2.Gen.t
(** A grammar name of one to eight characters, drawn from seven characters. *)

val wasm_module_with_a_name : (string * string) QCheck2.Gen.t
(** A grammar name, and a WebAssembly module that exports it. *)

val wasm_bytes : string QCheck2.Gen.t
(** Bytes that a reader of a WebAssembly module must survive: any bytes; the
    eight-byte header and then any bytes; a module cut short; a module with one
    byte changed; and a whole module. *)

val grammar_file_path : string QCheck2.Gen.t
(** A file name of at most twelve pieces. A piece is the hyphen, the dot, the
    slash, the underscore, the space, a letter, or ["tree-sitter-"]. *)
