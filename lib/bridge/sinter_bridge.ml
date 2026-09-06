(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

exception Error of string

(* The C stubs raise this exception. Callback.register_exception makes
   it reachable from C under this name. *)
let () = Callback.register_exception "Sinter_bridge.Error" (Error "")

type engine
type handle

external engine_new : unit -> engine = "sinter_bridge_engine_new_stub"
external engine_free : engine -> unit = "sinter_bridge_engine_free_stub"

external language_load : engine -> string -> string -> handle
  = "sinter_bridge_language_load_stub"

external run : engine -> handle -> string -> string -> string
  = "sinter_bridge_run_stub"

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

(* The decoder of the result buffer. bridge/README.md defines the
   layout. Every integer is unsigned, 32 bits wide, and little-endian.
   No field is aligned, so every read copies the four bytes. *)

let magic = "SBR1"
let header_length = 16
let kind_captures = 0
let kind_tree = 1

let malformed reason =
  raise (Error ("the bridge returned a malformed buffer: " ^ reason))

let check buffer offset count =
  if offset < 0 || count < 0 || offset + count > String.length buffer then
    malformed "a record runs past the end of the buffer"

let read_int buffer offset =
  check buffer offset 4;
  Int32.to_int (String.get_int32_le buffer offset) land 0xFFFFFFFF

(* Read a length in bytes and then that many bytes. Give the string and
   the offset of the byte after it. *)
let read_string buffer offset =
  let length = read_int buffer (offset + 0) in
  check buffer (offset + 4) length;
  (String.sub buffer (offset + 4) length, offset + 4 + length)

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
  let name, offset = read_string buffer (offset + 28) in
  let node_type, offset = read_string buffer offset in
  let text, offset = read_string buffer offset in
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

let captures language ~source ~query =
  if String.length query = 0 then
    invalid_arg "Sinter_bridge.captures: the query is empty";
  let buffer = run language.engine language.handle source query in
  let count = read_header buffer kind_captures in
  let rec read index offset acc =
    if index = count then List.rev acc
    else
      let capture, offset = read_capture buffer offset in
      read (index + 1) offset (capture :: acc)
  in
  read 0 header_length []

let tree language ~source =
  let buffer = run language.engine language.handle source "" in
  let count = read_header buffer kind_tree in
  if count <> 1 then
    malformed
      (Printf.sprintf "a parse tree buffer holds %d records, and 1 was expected"
         count);
  let text, _ = read_string buffer header_length in
  text
