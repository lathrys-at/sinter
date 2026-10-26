(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

module Utf_8 = Utf_8

exception Error of string
exception Failed of string

let () = Callback.register_exception "Sinter_bridge.Error" (Error "")
let () = Callback.register_exception "Sinter_bridge.Failed" (Failed "")

type engine
type handle
type tree_handle
type query_handle
type adapter_handle

external engine_new : unit -> engine = "sinter_bridge_engine_new_stub"
external engine_free : engine -> unit = "sinter_bridge_engine_free_stub"

external language_load : engine -> string -> string -> handle
  = "sinter_bridge_language_load_stub"

external language_free : handle -> unit = "sinter_bridge_language_free_stub"

external parse : engine -> handle -> string -> tree_handle
  = "sinter_bridge_parse_stub"

external tree_free : tree_handle -> unit = "sinter_bridge_tree_free_stub"
external tree_sexp : tree_handle -> string = "sinter_bridge_tree_sexp_stub"
external tree_errors : tree_handle -> string = "sinter_bridge_tree_errors_stub"

external query_new : handle -> string -> query_handle
  = "sinter_bridge_query_new_stub"

external query_free : query_handle -> unit = "sinter_bridge_query_free_stub"

external query_run : query_handle -> tree_handle -> string
  = "sinter_bridge_query_run_stub"

external adapter_load : engine -> string -> int -> int -> adapter_handle
  = "sinter_bridge_adapter_load_stub"

external adapter_interface : adapter_handle -> int
  = "sinter_bridge_adapter_interface_stub"

external adapter_free : adapter_handle -> unit
  = "sinter_bridge_adapter_free_stub"

external adapter_call :
  adapter_handle -> int -> string -> string -> int -> int -> string
  = "sinter_bridge_adapter_call_byte" "sinter_bridge_adapter_call_stub"

external sha256_buffer : string -> string = "sinter_bridge_sha256_stub"
external toml_buffer : string -> string = "sinter_bridge_toml_parse_stub"

type t = engine

(* @cites rust-bridge *)
(* The decoder of the result buffer. Every integer in the buffer is
   unsigned, 32 bits wide, and little-endian. *)

let magic = "SBR1"
let header_length = 16
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

let read_int buffer offset =
  check buffer offset 4;
  Int32.to_int (String.get_int32_le buffer offset) land 0xFFFFFFFF

let read_string buffer offset ~what =
  let length = read_int buffer offset in
  check buffer (offset + 4) length;
  let text = String.sub buffer (offset + 4) length in
  if not (Utf_8.is_valid text) then raise (Error (what ^ " is not UTF-8 text"));
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

let check_whole buffer offset =
  if offset <> String.length buffer then
    malformed
      (Printf.sprintf "the records end at byte %d and the buffer holds %d bytes"
         offset (String.length buffer))

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

let read_bytes buffer offset =
  let length = read_int buffer offset in
  check buffer (offset + 4) length;
  (String.sub buffer (offset + 4) length, offset + 4 + length)

let read_size buffer offset =
  check buffer offset 8;
  let value = String.get_int64_le buffer offset in
  if
    Int64.compare value 0L < 0 || Int64.compare value (Int64.of_int max_int) > 0
  then malformed "a size does not fit an integer";
  Int64.to_int value

let read_one buffer ~kind ~what read =
  let count = read_header buffer kind in
  if count <> 1 then
    malformed
      (Printf.sprintf "%s buffer holds %d records, and 1 was expected" what
         count);
  let found, offset = read buffer header_length in
  check_whole buffer offset;
  found

type range = {
  start_byte : int;
  end_byte : int;
  start_row : int;
  start_column : int;
  end_row : int;
  end_column : int;
}

let read_range buffer offset =
  let field index = read_int buffer (offset + (4 * index)) in
  ( {
      start_byte = field 0;
      end_byte = field 1;
      start_row = field 2;
      start_column = field 3;
      end_row = field 4;
      end_column = field 5;
    },
    offset + 24 )

module Language_types = struct
  type wasm_kind = Parse | Compile | Instantiate | Other

  type error =
    | Wasm of { kind : wasm_kind; message : string }
    | Version of int
    | Name_not_utf_8

  let message = function
    | Wasm { kind; message } ->
        let what =
          match kind with
          | Parse -> "Failed to parse wasm"
          | Compile -> "Failed to compile wasm"
          | Instantiate -> "Failed to instantiate wasm module"
          | Other -> "Unknown error"
        in
        what ^ ": " ^ message
    | Version version ->
        Printf.sprintf
          "Incompatible language version %d. Expected minimum 13, maximum 15"
          version
    | Name_not_utf_8 -> "the grammar name is not valid UTF-8"
end

module Tree_types = struct
  type error = Did_not_finish | Too_long
  type node = { node_type : string; range : range }
  type error_kind = Error_node | Missing_node

  type report = {
    has_error : bool;
    errors : (error_kind * node) list;
    lowest : node option;
  }

  let message = function
    | Did_not_finish -> "the grammar produced no parse tree"
    | Too_long ->
        "the source text is 4 GiB or more, and the result buffer holds no \
         offset that large"
end

module Query_types = struct
  type kind =
    | Syntax
    | Node_type
    | Field
    | Capture
    | Predicate
    | Structure
    | Language

  type error =
    | Invalid of {
        kind : kind;
        row : int;
        column : int;
        offset : int;
        message : string;
      }
    | Not_allowed of {
        operator : string;
        pattern : int;
        offset : int;
        row : int;
        column : int;
      }
    | Not_utf_8 of int

  type run_error = Language_mismatch

  type capture = {
    match_number : int;
    pattern : int;
    name : string;
    node_type : string;
    range : range;
    text : string;
  }

  let message = function
    | Invalid { kind; row; column; offset = _; message } -> (
        let what =
          match kind with
          | Field -> "Invalid field name "
          | Node_type -> "Invalid node type "
          | Capture -> "Invalid capture name "
          | Predicate -> "Invalid predicate: "
          | Structure -> "Impossible pattern:\n"
          | Syntax -> "Invalid syntax:\n"
          | Language -> ""
        in
        match kind with
        | Language -> message
        | _ ->
            Printf.sprintf "Query error at %d:%d. %s%s" (row + 1) (column + 1)
              what message)
    | Not_allowed { operator; row; column; _ } ->
        Printf.sprintf
          "Query error at %d:%d. A query cannot use #%s. It can use only the \
           predicates #eq?, #not-eq?, #any-eq?, #any-not-eq?, #match?, \
           #not-match?, #any-match?, #any-not-match?, #any-of?, and \
           #not-any-of?"
          (row + 1) (column + 1) operator
    | Not_utf_8 offset ->
        Printf.sprintf "the query is not UTF-8 text, at byte %d" offset

  let run_message Language_mismatch =
    "the query and the parse tree come from different grammars"
end

module Adapter_types = struct
  type invalid =
    | Not_a_module of string
    | Imports of string list
    | Missing_export of string
    | Wrong_export_type of string

  type input = Request | Report

  type error =
    | Invalid of invalid
    | Out_of_fuel
    | Trap of string
    | Memory_limit of int
    | Alloc of { input : input; address : int; length : int; memory_size : int }
    | Response_outside_memory of {
        address : int;
        length : int;
        memory_size : int;
      }

  type call = Recognise | Bind

  let message = function
    | Invalid (Not_a_module message) ->
        "the adapter is not a WebAssembly module: " ^ message
    | Invalid (Imports names) ->
        "the adapter imports " ^ String.concat ", " names
        ^ ", and an adapter imports nothing"
    | Invalid (Missing_export name) ->
        Printf.sprintf "the adapter does not export %s" name
    | Invalid (Wrong_export_type name) ->
        Printf.sprintf "the export %s of the adapter has the wrong type" name
    | Out_of_fuel -> "the adapter ran past its limit of fuel"
    | Trap message -> "the adapter stopped: " ^ message
    | Memory_limit size ->
        Printf.sprintf
          "the adapter asked for %d bytes of memory, which is past its limit"
          size
    | Alloc { input; address; length; memory_size } ->
        let what =
          match input with Request -> "request" | Report -> "report"
        in
        if address = 0 then
          Printf.sprintf "sinter_alloc gave 0 for the %d bytes of the %s" length
            what
        else
          Printf.sprintf
            "sinter_alloc gave the address %d for the %d bytes of the %s, and \
             the memory holds %d bytes"
            address length what memory_size
    | Response_outside_memory { address; length; memory_size } ->
        Printf.sprintf
          "the response at the address %d holds %d bytes, and the memory holds \
           %d bytes"
          address length memory_size
end

type failure =
  | Language_failure of Language_types.error
  | Tree_failure of Tree_types.error
  | Query_failure of Query_types.error
  | Run_failure of Query_types.run_error
  | Adapter_failure of Adapter_types.error

let kind_captures = 6
let kind_report = 7
let kind_response = 8
let kind_failure = 5

let read_node buffer offset =
  let range, offset = read_range buffer offset in
  let node_type, offset =
    read_string buffer offset ~what:"the type of a node"
  in
  ({ Tree_types.node_type; range }, offset)

let read_query_capture buffer offset =
  let match_number = read_int buffer offset in
  let pattern = read_int buffer (offset + 4) in
  let range, offset = read_range buffer (offset + 8) in
  let name, offset = read_string buffer offset ~what:"the name of a capture" in
  let node_type, offset =
    read_string buffer offset ~what:"the type of a node"
  in
  let text, offset = read_bytes buffer offset in
  ({ Query_types.match_number; pattern; name; node_type; range; text }, offset)

let read_report buffer offset =
  let has_error = read_flag buffer offset ~what:"the error flag of the root" in
  let errors, offset =
    read_list buffer (offset + 4) (fun buffer offset ->
        let kind =
          match read_int buffer offset with
          | 0 -> Tree_types.Error_node
          | 1 -> Tree_types.Missing_node
          | other ->
              malformed (Printf.sprintf "an error node has the form %d" other)
        in
        let node, offset = read_node buffer (offset + 4) in
        ((kind, node), offset))
  in
  let present = read_flag buffer offset ~what:"the flag of the lowest node" in
  if present <> has_error then
    malformed "the lowest error node and the error flag of the root disagree";
  if present then
    let node, offset = read_node buffer (offset + 4) in
    ({ Tree_types.has_error; errors; lowest = Some node }, offset)
  else ({ Tree_types.has_error; errors; lowest = None }, offset + 4)

let read_message buffer offset =
  read_string buffer offset ~what:"the message of a failure"

let wasm_kind = function
  | 0 -> Language_types.Parse
  | 1 -> Language_types.Compile
  | 2 -> Language_types.Instantiate
  | 3 -> Language_types.Other
  | other -> malformed (Printf.sprintf "a grammar error has the kind %d" other)

let query_kind = function
  | 0 -> Query_types.Syntax
  | 1 -> Query_types.Node_type
  | 2 -> Query_types.Field
  | 3 -> Query_types.Capture
  | 4 -> Query_types.Predicate
  | 5 -> Query_types.Structure
  | 6 -> Query_types.Language
  | other -> malformed (Printf.sprintf "a query error has the kind %d" other)

let read_invalid buffer offset =
  let cause = read_int buffer offset in
  let names, offset =
    read_list buffer (offset + 4) (fun buffer offset ->
        read_string buffer offset ~what:"a name in an adapter error")
  in
  let one () =
    match names with
    | [ name ] -> name
    | _ ->
        malformed
          (Printf.sprintf "an adapter error of cause %d holds %d names" cause
             (List.length names))
  in
  let invalid =
    match cause with
    | 0 -> Adapter_types.Not_a_module (one ())
    | 1 ->
        if names = [] then malformed "an adapter error names no import";
        Adapter_types.Imports names
    | 2 -> Adapter_types.Missing_export (one ())
    | 3 -> Adapter_types.Wrong_export_type (one ())
    | other ->
        malformed (Printf.sprintf "an adapter error has the cause %d" other)
  in
  (invalid, offset)

let read_failure buffer offset =
  let code = read_int buffer offset in
  let offset = offset + 4 in
  match code with
  | 0 ->
      let message, _ = read_message buffer offset in
      raise (Error message)
  | 1 ->
      let kind = wasm_kind (read_int buffer offset) in
      let message, offset = read_message buffer (offset + 4) in
      (Language_failure (Language_types.Wasm { kind; message }), offset)
  | 2 ->
      ( Language_failure (Language_types.Version (read_int buffer offset)),
        offset + 4 )
  | 3 -> (Tree_failure Tree_types.Did_not_finish, offset)
  | 4 -> (Tree_failure Tree_types.Too_long, offset)
  | 5 ->
      let kind = query_kind (read_int buffer offset) in
      let row = read_int buffer (offset + 4) in
      let column = read_int buffer (offset + 8) in
      let error_offset = read_int buffer (offset + 12) in
      let message, offset = read_message buffer (offset + 16) in
      ( Query_failure
          (Query_types.Invalid
             { kind; row; column; offset = error_offset; message }),
        offset )
  | 6 ->
      let operator, offset =
        read_string buffer offset ~what:"the operator of a predicate"
      in
      let pattern = read_int buffer offset in
      let pattern_offset = read_int buffer (offset + 4) in
      let row = read_int buffer (offset + 8) in
      let column = read_int buffer (offset + 12) in
      ( Query_failure
          (Query_types.Not_allowed
             { operator; pattern; offset = pattern_offset; row; column }),
        offset + 16 )
  | 7 -> (Run_failure Query_types.Language_mismatch, offset)
  | 8 ->
      let invalid, offset = read_invalid buffer offset in
      (Adapter_failure (Adapter_types.Invalid invalid), offset)
  | 9 -> (Adapter_failure Adapter_types.Out_of_fuel, offset)
  | 10 ->
      let message, offset = read_message buffer offset in
      (Adapter_failure (Adapter_types.Trap message), offset)
  | 11 ->
      ( Adapter_failure (Adapter_types.Memory_limit (read_size buffer offset)),
        offset + 8 )
  | 12 ->
      let input =
        match read_int buffer offset with
        | 0 -> Adapter_types.Request
        | 1 -> Adapter_types.Report
        | other ->
            malformed (Printf.sprintf "an allocation names the input %d" other)
      in
      let address = read_int buffer (offset + 4) in
      let length = read_int buffer (offset + 8) in
      let memory_size = read_size buffer (offset + 12) in
      ( Adapter_failure
          (Adapter_types.Alloc { input; address; length; memory_size }),
        offset + 20 )
  | 13 ->
      let address = read_int buffer offset in
      let length = read_int buffer (offset + 4) in
      let memory_size = read_size buffer (offset + 8) in
      ( Adapter_failure
          (Adapter_types.Response_outside_memory
             { address; length; memory_size }),
        offset + 16 )
  | other -> malformed (Printf.sprintf "a failure has the code %d" other)

let decode_failure buffer select =
  let failure =
    read_one buffer ~kind:kind_failure ~what:"a failure" read_failure
  in
  match select failure with
  | Some error -> error
  | None -> malformed "the failure does not belong to the call"

module Decode = struct
  let captures buffer =
    let count = read_header buffer kind_captures in
    let rec read index offset acc =
      if index = count then (List.rev acc, offset)
      else
        let capture, offset = read_query_capture buffer offset in
        read (index + 1) offset (capture :: acc)
    in
    let found, offset = read 0 header_length [] in
    check_whole buffer offset;
    found

  let tree = decode_tree
  let digest = decode_digest

  let report buffer =
    read_one buffer ~kind:kind_report ~what:"an error report" read_report

  let response buffer =
    read_one buffer ~kind:kind_response ~what:"a response" read_bytes

  let language_error buffer =
    decode_failure buffer (function Language_failure e -> Some e | _ -> None)

  let tree_error buffer =
    decode_failure buffer (function Tree_failure e -> Some e | _ -> None)

  let query_error buffer =
    decode_failure buffer (function Query_failure e -> Some e | _ -> None)

  let run_error buffer =
    decode_failure buffer (function Run_failure e -> Some e | _ -> None)

  let adapter_error buffer =
    decode_failure buffer (function Adapter_failure e -> Some e | _ -> None)
end

let fault buffer = decode_failure buffer (fun _ -> None)

let create () =
  match engine_new () with
  | engine -> engine
  | exception Failed buffer -> fault buffer

let close engine = engine_free engine

let sha256 data =
  match sha256_buffer data with
  | buffer -> Decode.digest buffer
  | exception Failed buffer -> fault buffer

module Language = struct
  include Language_types

  type t = { engine : engine; handle : handle }

  let load engine ~name ~wasm =
    if String.contains name '\000' then
      invalid_arg
        "Sinter_bridge.Language.load: the grammar name holds a NUL byte";
    if not (Utf_8.is_valid name) then Result.Error Name_not_utf_8
    else
      match language_load engine name wasm with
      | handle -> Ok { engine; handle }
      | exception Failed buffer -> Result.Error (Decode.language_error buffer)

  let close language = language_free language.handle
end

module Tree = struct
  include Tree_types

  type t = tree_handle

  let parse (language : Language.t) source =
    match parse language.engine language.handle source with
    | tree -> Ok tree
    | exception Failed buffer -> Result.Error (Decode.tree_error buffer)

  let close = tree_free

  let sexp tree =
    match tree_sexp tree with
    | buffer -> Decode.tree buffer
    | exception Failed buffer -> fault buffer

  let errors tree =
    match tree_errors tree with
    | buffer -> Decode.report buffer
    | exception Failed buffer -> fault buffer
end

module Query = struct
  include Query_types

  type t = query_handle

  let compile (language : Language.t) text =
    match Utf_8.first_invalid text with
    | Some offset -> Result.Error (Not_utf_8 offset)
    | None -> (
        match query_new language.handle text with
        | query -> Ok query
        | exception Failed buffer -> Result.Error (Decode.query_error buffer))

  let close = query_free

  let run query tree =
    match query_run query tree with
    | buffer -> Ok (Decode.captures buffer)
    | exception Failed buffer -> Result.Error (Decode.run_error buffer)
end

module Adapter = struct
  include Adapter_types

  type t = adapter_handle

  let check_limits ~fuel ~memory =
    if fuel < 0 then
      invalid_arg "Sinter_bridge.Adapter: the fuel limit is below 0";
    if memory < 0 then
      invalid_arg "Sinter_bridge.Adapter: the memory limit is below 0"

  let load engine ~wasm ~fuel ~memory =
    check_limits ~fuel ~memory;
    match adapter_load engine wasm fuel memory with
    | adapter -> Ok adapter
    | exception Failed buffer -> Result.Error (Decode.adapter_error buffer)

  let version = adapter_interface
  let close = adapter_free

  let call adapter function_ ~request ~report ~fuel ~memory =
    check_limits ~fuel ~memory;
    let number = match function_ with Recognise -> 0 | Bind -> 1 in
    match adapter_call adapter number request report fuel memory with
    | buffer -> Ok (Decode.response buffer)
    | exception Failed buffer -> Result.Error (Decode.adapter_error buffer)
end

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

  let read_span buffer offset ~length =
    let start_byte = read_int buffer offset in
    let end_byte = read_int buffer (offset + 4) in
    if start_byte > end_byte then malformed "a span ends before it starts";
    if end_byte > length then malformed "a span runs past the end of the text";
    (start_byte, end_byte, offset + 8)

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
    match toml_buffer text with
    | exception Failed buffer -> fault buffer
    | buffer ->
        decode
          ~length:
            (String.length text
             [@mutaml.skip
               "the bridge writes no span that runs past the text it reads, so \
                a bound one byte larger accepts the same buffers; the tests of \
                decode check the bound itself"])
          buffer
end
