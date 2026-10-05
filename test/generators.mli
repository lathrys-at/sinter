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

val encode_digest : string -> string
(** [encode_digest digest] is a result buffer that holds the bytes [digest] as
    one digest, in the layout that the bridge writes. *)

val capture : Sinter_bridge.capture QCheck2.Gen.t
(** One capture. Every integer field is in the range of an unsigned 32-bit
    integer, and every string field is valid UTF-8. *)

val captures_buffer : (Sinter_bridge.capture list * string) QCheck2.Gen.t
(** A list of at most four captures, and the result buffer that holds them. *)

val tree_buffer : (string * string) QCheck2.Gen.t
(** A parse tree text, and the result buffer that holds it. *)

val digest_buffer : (string * string) QCheck2.Gen.t
(** A digest of 32 bytes, and the result buffer that holds it. *)

(** How a buffer was damaged. *)
type damage =
  | Truncated  (** bytes were cut from the end *)
  | Length_out_of_range  (** the length of one string runs past the end *)
  | Not_utf_8  (** one string is no longer valid UTF-8 *)
  | Wrong_magic  (** one byte of the first four was changed *)
  | Wrong_kind  (** the kind field names another kind *)
  | Wrong_count  (** the count field names another number of records *)
  | Trailing_bytes  (** bytes were added after the last record *)
(** How a buffer was damaged. *)

val damaged_captures_buffer : (damage * string) QCheck2.Gen.t
(** A capture result buffer that was damaged in one of the seven ways, and the
    way it was damaged. No damaged buffer is a valid capture result buffer. *)

val damaged_tree_buffer : (damage * string) QCheck2.Gen.t
(** A parse tree result buffer that was damaged in one of the seven ways, and
    the way it was damaged. No damaged buffer is a valid parse tree result
    buffer. *)

val damaged_digest_buffer : (damage * string) QCheck2.Gen.t
(** A digest result buffer that was damaged in one of the five ways that apply
    to a buffer that holds no string, and the way it was damaged. No damaged
    buffer is a valid digest result buffer. *)

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
    over a run of it; a whole capture buffer; a whole parse tree buffer; and a
    whole digest buffer. *)

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

val capture_outside : string -> Sinter_bridge.capture QCheck2.Gen.t
(** [capture_outside source] is a capture whose byte range is not inside
    [source]: the end runs past [source], or the end is before the start, or the
    start is below 0. *)

val source_and_capture : (string * Sinter_bridge.capture) QCheck2.Gen.t
(** A source text, and a capture inside it. *)

val source_and_capture_outside : (string * Sinter_bridge.capture) QCheck2.Gen.t
(** A source text, and a capture whose byte range is not inside it. *)

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

(** The shape of a WebAssembly module. Each shape sends the reader of a grammar
    name down a different road: over a section whose size needs two LEB128
    bytes, down a list of exports, or into a section the module cuts short. *)
type wasm_shape =
  | One_export  (** one export, and every count and every length of one byte *)
  | Custom_section_before
      (** a custom section of eight bytes stands before the export section *)
  | Long_custom_section
      (** the custom section holds a body of 128 bytes, so the size of that
          section needs two LEB128 bytes *)
  | Three_exports  (** three exports, and the one of the grammar last *)
  | Long_export_index
      (** two exports, and the one before the grammar carries an index written
          in five LEB128 bytes. The format allows the longer encoding; the
          reader takes five bytes and no more. *)
  | Too_few_exports_declared
      (** the export section declares two exports and holds three, and the one
          of the grammar is the third. The reader stops at the count, so it
          finds no name. *)
  | Too_many_exports_declared
      (** the export section declares three exports and holds two, and the bytes
          of the export of the grammar follow the section. The reader stops at
          the end of the section, so it finds no name. *)
  | Cut_in_a_section
      (** the last two bytes of the module are gone, and the size of the export
          section still counts them. The reader finds no name in a section that
          runs past the end of the module. *)

val wasm_module : wasm_shape -> name:string -> string
(** [wasm_module shape ~name] is a WebAssembly module of [shape] that exports
    one function called ["tree_sitter_"] and [name]. The reader of a grammar
    name finds [name] in every shape but the last three, which state what the
    reader finds instead. *)

val grammar_export_name : string QCheck2.Gen.t
(** A grammar name of one to eight characters, drawn from seven characters. *)

val wasm_module_with_a_name : (string * string) QCheck2.Gen.t
(** A grammar name, and a WebAssembly module that exports it. The shape of the
    module is drawn from the five shapes in which the reader finds a name, so a
    property over this generator meets a section whose size needs two bytes, a
    list of three exports, and an index of five bytes. *)

val wasm_module_whose_name_holds_a_nul : string QCheck2.Gen.t
(** A WebAssembly module, of a drawn shape, whose export names the grammar with
    a NUL byte in the name. *)

val wasm_bytes : string QCheck2.Gen.t
(** Bytes that a reader of a WebAssembly module must survive: any bytes; the
    eight-byte header and then any bytes; a module cut short; a module with one
    byte changed; and a whole module. *)

val grammar_file_path : string QCheck2.Gen.t
(** A file name of at most twelve pieces. A piece is the hyphen, the dot, the
    slash, the underscore, the space, a letter, or ["tree-sitter-"]. *)

(** {1 Output of git diff} *)

val quote_path : string -> string
(** [quote_path path] is [path] as git writes it in a ["diff --git"] line: as it
    is, or in double quotes with C-style escapes when it holds a byte below
    0x20, a double quote, a backslash, or a byte of 0x7F or above. *)

val hunk_header : (string * Sinter_core.Git.Decode.header) QCheck2.Gen.t
(** A hunk header line, without its line feed, and the numbers it holds. A count
    of 1 is left out at times, and text follows the closing [@@] at times. *)

val print_hunk_header : (string * Sinter_core.Git.Decode.header) QCheck2.Print.t
(** The printer for a counterexample of {!hunk_header}. *)

val damaged_hunk_header : string QCheck2.Gen.t
(** A hunk header cut short, a hunk header with a few bytes of its own alphabet
    written over it, or any bytes. *)

val diff_output :
  (string * (string * Sinter_core.Git.change) list) QCheck2.Gen.t
(** The output of [git diff -U0] with up to five sections, and the changes that
    {!Sinter_core.Git.Decode.diff} gives for it. A path can need quotes, and a
    path can have two sections, as git writes for a file whose type changed. A
    section is binary or holds up to four hunks. *)

val diff_output_with_context :
  (string * Sinter_core.Git.hunk list) QCheck2.Gen.t
(** The output of [git diff] for the one path ["f"], with one hunk that holds
    context lines between its runs of changed lines, and the runs. *)

val damaged_diff_output : string QCheck2.Gen.t
(** An output of {!diff_output} cut short, with one line removed or repeated, or
    with a few bytes written over it; or any bytes. *)

val print_change : Sinter_core.Git.change -> string
(** [print_change change] is [change] in a short form for a test message. *)

val print_changes : (string * Sinter_core.Git.change) list QCheck2.Print.t
(** The printer for a list of paths and their changes. *)

(** {1 Output of git for-each-ref} *)

val refs_output : (string * Sinter_core.Git.Decode.ref_entry list) QCheck2.Gen.t
(** The output of [git for-each-ref] with the format that
    {!Sinter_core.Git.Decode.refs} reads, for up to four refs, and those refs.
    An object id has 40 or 64 digits, and an upstream is empty at times. *)

val print_refs_output :
  (string * Sinter_core.Git.Decode.ref_entry list) QCheck2.Print.t
(** The printer for a counterexample of {!refs_output}. *)

val damaged_refs_output : string QCheck2.Gen.t
(** An output of {!refs_output} cut short, or with a few bytes written over it;
    or any bytes. *)
