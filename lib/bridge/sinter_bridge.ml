(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

exception Error of string

(* The C stubs raise this exception. *)
let () = Callback.register_exception "Sinter_bridge.Error" (Error "")

type engine
type handle

external engine_new : unit -> engine = "sinter_bridge_engine_new_stub"
external engine_free : engine -> unit = "sinter_bridge_engine_free_stub"

external language_load : engine -> string -> string -> handle
  = "sinter_bridge_language_load_stub"

external run : engine -> handle -> string -> string -> string
  = "sinter_bridge_run_stub"

external sha256_buffer : string -> string = "sinter_bridge_sha256_stub"
external toml_buffer : string -> string = "sinter_bridge_toml_parse_stub"

type t = engine

(* The engine owns the grammar, so the record keeps the engine alive
   for as long as the grammar is in use. *)
type language = { engine : engine; handle : handle }

type capture = {
  pattern : int;
  name : string;
  node_type : string;
  start_byte : int;
  end_byte : int;
  start_row : int;
  start_column : int;
  end_row : int;
  end_column : int;
  text : string;
}

let create () = engine_new ()
let close engine = engine_free engine

let load engine ~name ~wasm =
  if String.contains name '\000' then
    invalid_arg "Sinter_bridge.load: the grammar name holds a NUL byte";
  { engine; handle = language_load engine name wasm }

(* @cites parser-bridge *)
(* The decoder of the result buffer. Every integer in the buffer is
   unsigned, 32 bits wide, and little-endian. *)

let magic = "SBR1"
let header_length = 16
let kind_captures = 0
let kind_tree = 1
let kind_digest = 2
let digest_length = 32

let malformed reason =
  raise (Error ("the bridge returned a malformed buffer: " ^ reason))

let check buffer offset count =
  if
    (offset < 0)
    [@mutaml.skip
      "check is not in the interface, and no call reaches it with an offset \
       below 4: read_header reads 4 and 8, and a record starts at \
       header_length"]
    || count < 0
    || offset + count > String.length buffer
  then malformed "a record runs past the end of the buffer"

(* The mask gives the unsigned value of the four bytes. It needs an
   int of more than 32 bits, so Sinter runs on 64-bit machines only. *)
let read_int buffer offset =
  check buffer offset 4;
  Int32.to_int (String.get_int32_le buffer offset) land 0xFFFFFFFF

let is_utf_8 text =
  let length = String.length text in
  let rec walk offset =
    offset >= length
    ||
    let decoded = String.get_utf_8_uchar text offset in
    Uchar.utf_decode_is_valid decoded
    && walk (offset + Uchar.utf_decode_length decoded)
  in
  walk 0

(* Give the string and the offset of the byte after it. Every string
   of the buffer is UTF-8, so a caller of this module never sees other
   bytes. [what] names the string in the message of a failure: the
   buffer is well formed when a string of it is not UTF-8, and the
   caller must be told which string. *)
let read_string buffer offset ~what =
  let length = read_int buffer offset in
  check buffer (offset + 4) length;
  let text = String.sub buffer (offset + 4) length in
  if not (is_utf_8 text) then raise (Error (what ^ " is not UTF-8 text"));
  (text, offset + 4 + length)

let read_header buffer expected_kind =
  if String.length buffer < header_length then
    malformed "the buffer is shorter than the header";
  if not (String.equal (String.sub buffer 0 4) magic) then
    malformed "the first four bytes are not SBR1";
  let kind = read_int buffer 4 in
  if kind <> expected_kind then
    malformed
      (Printf.sprintf "the kind is %d, and %d was expected" kind expected_kind);
  read_int buffer 8

let read_capture buffer offset =
  let pattern = read_int buffer offset in
  let start_byte = read_int buffer (offset + 4) in
  let end_byte = read_int buffer (offset + 8) in
  let start_row = read_int buffer (offset + 12) in
  let start_column = read_int buffer (offset + 16) in
  let end_row = read_int buffer (offset + 20) in
  let end_column = read_int buffer (offset + 24) in
  let name, offset =
    read_string buffer (offset + 28) ~what:"the name of a capture"
  in
  let node_type, offset =
    read_string buffer offset ~what:"the type of a node"
  in
  let text, offset = read_string buffer offset ~what:"the text of a node" in
  ( {
      pattern;
      name;
      node_type;
      start_byte;
      end_byte;
      start_row;
      start_column;
      end_row;
      end_column;
      text;
    },
    offset )

let check_whole buffer offset =
  if offset <> String.length buffer then
    malformed
      (Printf.sprintf "the records end at byte %d and the buffer holds %d bytes"
         offset (String.length buffer))

let decode_captures buffer =
  let count = read_header buffer kind_captures in
  let rec read index offset acc =
    if index = count then (List.rev acc, offset)
    else
      let capture, offset = read_capture buffer offset in
      read (index + 1) offset (capture :: acc)
  in
  let found, offset = read 0 header_length [] in
  check_whole buffer offset;
  found

let decode_tree buffer =
  let count = read_header buffer kind_tree in
  if count <> 1 then
    malformed
      (Printf.sprintf "a parse tree buffer holds %d records, and 1 was expected"
         count);
  let text, offset = read_string buffer header_length ~what:"the parse tree" in
  check_whole buffer offset;
  text

let decode_digest buffer =
  let count = read_header buffer kind_digest in
  if count <> 1 then
    malformed
      (Printf.sprintf "a digest buffer holds %d records, and 1 was expected"
         count);
  check_whole buffer (header_length + digest_length);
  String.sub buffer header_length digest_length

let sha256 data = decode_digest (sha256_buffer data)

(* @cites toml-reader *)
module Toml_raw = struct
  type offset = Utc | Minutes of int

  type datetime = {
    date : (int * int * int) option;
    time : (int * int * int * int) option;
    offset : offset option;
  }

  type value =
    | String of string
    | Integer of int64
    | Float of float
    | Boolean of bool
    | Datetime of datetime
    | Array of item list
    | Table of table
    | Inline_table of table
    | Array_of_tables of table list

  and item = { value : value; start_byte : int; end_byte : int }
  and table = entry list
  and entry = { name : string; key_start : int; key_end : int; item : item }

  type error =
    | Crate_error of { start_byte : int; end_byte : int; message : string }
    | Header_table of {
        start_byte : int;
        end_byte : int;
        key : string;
        table : string list;
        array : bool;
        rest : string list;
      }

  let kind_document = 3
  let kind_error = 4

  (* [read_list buffer offset read] reads a count and then that many
     elements with [read]. *)
  let read_list buffer offset read =
    let count = read_int buffer offset in
    let rec loop index offset acc =
      if index = count then (List.rev acc, offset)
      else
        let element, offset = read buffer offset in
        loop (index + 1) offset (element :: acc)
    in
    loop 0 (offset + 4) []

  let read_flag buffer offset ~what =
    match read_int buffer offset with
    | 0 -> false
    | 1 -> true
    | other -> malformed (Printf.sprintf "%s is %d, not 0 or 1" what other)

  (* A span of the text, which is [length] bytes long. *)
  let read_span buffer offset ~length =
    let start_byte = read_int buffer offset in
    let end_byte = read_int buffer (offset + 4) in
    if start_byte > end_byte then malformed "a span ends before it starts";
    if end_byte > length then malformed "a span runs past the end of the text";
    (start_byte, end_byte, offset + 8)

  (* The two's complement of a 32-bit value. *)
  let signed_32 value =
    if value >= 0x80000000 then value - 0x100000000 else value

  let read_datetime buffer offset =
    let parts = read_int buffer offset in
    let field index = read_int buffer (offset + 4 + (4 * index)) in
    let date = Some (field 0, field 1, field 2) in
    let time = Some (field 3, field 4, field 5, field 6) in
    let offset_value =
      match field 7 with
      | 0 -> Utc
      | 1 -> Minutes (signed_32 (field 8))
      | other -> malformed (Printf.sprintf "the offset kind is %d" other)
    in
    let datetime =
      match parts with
      | 1 -> { date; time = None; offset = None }
      | 2 -> { date = None; time; offset = None }
      | 3 -> { date; time; offset = None }
      | 7 -> { date; time; offset = Some offset_value }
      | other ->
          malformed (Printf.sprintf "a date or time holds the parts %d" other)
    in
    (datetime, offset + 40)

  let rec read_item buffer offset ~length =
    let tag = read_int buffer offset in
    let start_byte, end_byte, offset = read_span buffer (offset + 4) ~length in
    let value, offset =
      match tag with
      | 0 ->
          let text, offset = read_string buffer offset ~what:"a TOML string" in
          (String text, offset)
      | 1 ->
          check buffer offset 8;
          (Integer (String.get_int64_le buffer offset), offset + 8)
      | 2 ->
          check buffer offset 8;
          ( Float (Int64.float_of_bits (String.get_int64_le buffer offset)),
            offset + 8 )
      | 3 -> (Boolean (read_flag buffer offset ~what:"a boolean"), offset + 4)
      | 4 ->
          let datetime, offset = read_datetime buffer offset in
          (Datetime datetime, offset)
      | 5 ->
          let items, offset =
            read_list buffer offset (fun buffer offset ->
                read_item buffer offset ~length)
          in
          (Array items, offset)
      | 6 ->
          let table, offset = read_table buffer offset ~length in
          (Table table, offset)
      | 7 ->
          let tables, offset =
            read_list buffer offset (fun buffer offset ->
                read_table buffer offset ~length)
          in
          (Array_of_tables tables, offset)
      | 8 ->
          let table, offset = read_table buffer offset ~length in
          (Inline_table table, offset)
      | other -> malformed (Printf.sprintf "a TOML value has the tag %d" other)
    in
    ({ value; start_byte; end_byte }, offset)

  and read_table buffer offset ~length =
    read_list buffer offset (fun buffer offset ->
        let name, offset = read_string buffer offset ~what:"a TOML key" in
        let key_start, key_end, offset = read_span buffer offset ~length in
        let item, offset = read_item buffer offset ~length in
        ({ name; key_start; key_end; item }, offset))

  let read_name buffer offset = read_string buffer offset ~what:"a TOML key"

  let read_error buffer offset ~length =
    let form = read_int buffer offset in
    let start_byte, end_byte, offset = read_span buffer (offset + 4) ~length in
    match form with
    | 0 ->
        let message, offset =
          read_string buffer offset ~what:"the message of a TOML error"
        in
        (Crate_error { start_byte; end_byte; message }, offset)
    | 1 ->
        let key, offset = read_string buffer offset ~what:"a TOML key" in
        let table, offset = read_list buffer offset read_name in
        let array = read_flag buffer offset ~what:"the array flag" in
        let rest, offset = read_list buffer (offset + 4) read_name in
        (Header_table { start_byte; end_byte; key; table; array; rest }, offset)
    | other -> malformed (Printf.sprintf "a TOML error has the form %d" other)

  let decode ~length buffer =
    if String.length buffer < header_length then
      malformed "the buffer is shorter than the header";
    let kind = read_int buffer 4 in
    let read_one read =
      let count = read_header buffer kind in
      if count <> 1 then
        malformed
          (Printf.sprintf "a TOML buffer holds %d records, and 1 was expected"
             count);
      let found, offset = read buffer header_length ~length in
      check_whole buffer offset;
      found
    in
    if kind = kind_document then Ok (read_one read_table)
    else if kind = kind_error then Error (read_one read_error)
    else
      malformed
        (Printf.sprintf "the kind is %d, and %d or %d was expected" kind
           kind_document kind_error)

  let parse text =
    decode
      ~length:
        (String.length text
         [@mutaml.skip
           "the bridge writes no span that runs past the text it reads, so a \
            bound one byte larger accepts the same buffers; the tests of \
            decode check the bound itself"])
      (toml_buffer text)
end

let captures language ~source ~query =
  if String.length query = 0 then
    invalid_arg "Sinter_bridge.captures: the query is empty";
  decode_captures (run language.engine language.handle source query)

let tree language ~source =
  decode_tree (run language.engine language.handle source "")
