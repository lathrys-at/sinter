(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

module Gen = QCheck2.Gen
module B = Sinter_bridge

type failure =
  | Internal of string
  | Language of B.Language.error
  | Tree of B.Tree.error
  | Query of B.Query.error
  | Run of B.Query.run_error
  | Adapter of B.Adapter.error

let kind_failure = 5
let kind_captures = 6
let kind_report = 7
let kind_response = 8

type writer = {
  buffer : Buffer.t;
  mutable runs : (int * int) list;
  mutable bytes : (int * int) list;
}

let writer ~kind ~count =
  let buffer = Buffer.create 128 in
  Buffer.add_string buffer "SBR1";
  Buffer.add_int32_le buffer (Int32.of_int kind);
  Buffer.add_int32_le buffer (Int32.of_int count);
  Buffer.add_int32_le buffer 0l;
  { buffer; runs = []; bytes = [] }

let u32 w value = Buffer.add_int32_le w.buffer (Int32.of_int value)
let u64 w value = Buffer.add_int64_le w.buffer (Int64.of_int value)

let text w s =
  w.runs <- (Buffer.length w.buffer, String.length s) :: w.runs;
  u32 w (String.length s);
  Buffer.add_string w.buffer s

let raw w s =
  w.bytes <- (Buffer.length w.buffer, String.length s) :: w.bytes;
  u32 w (String.length s);
  Buffer.add_string w.buffer s

let finish w = (Buffer.contents w.buffer, List.rev w.runs, List.rev w.bytes)
let contents w = Buffer.contents w.buffer

let range w (r : B.range) =
  List.iter (u32 w)
    [
      r.start_byte;
      r.end_byte;
      r.start_row;
      r.start_column;
      r.end_row;
      r.end_column;
    ]

let node w (n : B.Tree.node) =
  range w n.range;
  text w n.node_type

let captures_writer captures =
  let w = writer ~kind:kind_captures ~count:(List.length captures) in
  List.iter
    (fun (c : B.Query.capture) ->
      u32 w c.match_number;
      u32 w c.pattern;
      range w c.range;
      text w c.name;
      text w c.node_type;
      raw w c.text)
    captures;
  w

let flag w value = u32 w (if value then 1 else 0)

let report_writer (report : B.Tree.report) =
  let w = writer ~kind:kind_report ~count:1 in
  flag w report.has_error;
  u32 w (List.length report.errors);
  List.iter
    (fun (kind, n) ->
      u32 w
        (match kind with B.Tree.Error_node -> 0 | B.Tree.Missing_node -> 1);
      node w n)
    report.errors;
  (match report.lowest with
  | None -> flag w false
  | Some n ->
      flag w true;
      node w n);
  w

let response_writer bytes =
  let w = writer ~kind:kind_response ~count:1 in
  raw w bytes;
  w

let wasm_kind = function
  | B.Language.Parse -> 0
  | Compile -> 1
  | Instantiate -> 2
  | Other -> 3

let query_kind = function
  | B.Query.Syntax -> 0
  | Node_type -> 1
  | Field -> 2
  | Capture -> 3
  | Predicate -> 4
  | Structure -> 5
  | Language -> 6

let names w names =
  u32 w (List.length names);
  List.iter (text w) names

let failure_writer failure =
  let w = writer ~kind:kind_failure ~count:1 in
  (match failure with
  | Internal message ->
      u32 w 0;
      text w message
  | Language (B.Language.Wasm { kind; message }) ->
      u32 w 1;
      u32 w (wasm_kind kind);
      text w message
  | Language (B.Language.Version version) ->
      u32 w 2;
      u32 w version
  | Language B.Language.Name_not_utf_8 ->
      invalid_arg "Bridge_buffers: the bridge writes no Name_not_utf_8"
  | Tree B.Tree.Did_not_finish -> u32 w 3
  | Tree B.Tree.Too_long -> u32 w 4
  | Query (B.Query.Invalid { kind; row; column; offset; message }) ->
      List.iter (u32 w) [ 5; query_kind kind; row; column; offset ];
      text w message
  | Query (B.Query.Not_allowed { operator; pattern; offset; row; column }) ->
      u32 w 6;
      text w operator;
      List.iter (u32 w) [ pattern; offset; row; column ]
  | Query (B.Query.Not_utf_8 _) ->
      invalid_arg "Bridge_buffers: the bridge writes no Not_utf_8"
  | Run B.Query.Language_mismatch -> u32 w 7
  | Adapter (B.Adapter.Invalid invalid) -> (
      u32 w 8;
      match invalid with
      | B.Adapter.Not_a_module message ->
          u32 w 0;
          names w [ message ]
      | Imports list ->
          u32 w 1;
          names w list
      | Missing_export name ->
          u32 w 2;
          names w [ name ]
      | Wrong_export_type name ->
          u32 w 3;
          names w [ name ])
  | Adapter B.Adapter.Out_of_fuel -> u32 w 9
  | Adapter (B.Adapter.Trap message) ->
      u32 w 10;
      text w message
  | Adapter (B.Adapter.Memory_limit size) ->
      u32 w 11;
      u64 w size
  | Adapter (B.Adapter.Alloc { input; address; length; memory_size }) ->
      u32 w 12;
      u32 w (match input with B.Adapter.Request -> 0 | Report -> 1);
      u32 w address;
      u32 w length;
      u64 w memory_size
  | Adapter (B.Adapter.Response_outside_memory { address; length; memory_size })
    ->
      u32 w 13;
      u32 w address;
      u32 w length;
      u64 w memory_size);
  w

let encode_captures captures = contents (captures_writer captures)
let encode_report report = contents (report_writer report)
let encode_response bytes = contents (response_writer bytes)
let encode_failure failure = contents (failure_writer failure)
let u32_gen = Gen.oneof [ Gen.nat_small; Gen.int_range 0 0xFFFFFFFF ]
let size_gen = Gen.oneof [ Gen.nat_small; Gen.int_range 0 max_int ]
let any_bytes = Gen.string_size ~gen:Gen.char (Gen.int_bound 12)

let range_gen =
  let open Gen in
  let* start_byte = u32_gen in
  let* end_byte = u32_gen in
  let* start_row = u32_gen in
  let* start_column = u32_gen in
  let* end_row = u32_gen in
  let+ end_column = u32_gen in
  { B.start_byte; end_byte; start_row; start_column; end_row; end_column }

let capture_gen =
  let open Gen in
  let* match_number = u32_gen in
  let* pattern = u32_gen in
  let* range = range_gen in
  let* name = Generators.utf_8_string in
  let* node_type = Generators.utf_8_string in
  let+ text = oneof [ Generators.utf_8_string; any_bytes ] in
  { B.Query.match_number; pattern; name; node_type; range; text }

let node_gen =
  let open Gen in
  let* node_type = Generators.utf_8_string in
  let+ range = range_gen in
  { B.Tree.node_type; range }

let report_value =
  let open Gen in
  let* has_error = bool in
  let* errors =
    list_size (int_range 0 3)
      (pair (oneof_list [ B.Tree.Error_node; B.Tree.Missing_node ]) node_gen)
  in
  let+ lowest = if has_error then map Option.some node_gen else return None in
  { B.Tree.has_error; errors; lowest }

let failure_value =
  let open Gen in
  let message = Generators.utf_8_string in
  oneof
    [
      (let* kind =
         oneof_list
           [
             B.Language.Parse;
             B.Language.Compile;
             B.Language.Instantiate;
             B.Language.Other;
           ]
       in
       let+ message = message in
       Language (B.Language.Wasm { kind; message }));
      map (fun version -> Language (B.Language.Version version)) u32_gen;
      oneof_list [ Tree B.Tree.Did_not_finish; Tree B.Tree.Too_long ];
      (let* kind =
         oneof_list
           B.Query.
             [
               Syntax; Node_type; Field; Capture; Predicate; Structure; Language;
             ]
       in
       let* row = u32_gen in
       let* column = u32_gen in
       let* offset = u32_gen in
       let+ message = message in
       Query (B.Query.Invalid { kind; row; column; offset; message }));
      (let* operator = message in
       let* pattern = u32_gen in
       let* offset = u32_gen in
       let* row = u32_gen in
       let+ column = u32_gen in
       Query (B.Query.Not_allowed { operator; pattern; offset; row; column }));
      return (Run B.Query.Language_mismatch);
      map
        (fun m -> Adapter (B.Adapter.Invalid (B.Adapter.Not_a_module m)))
        message;
      map
        (fun list -> Adapter (B.Adapter.Invalid (B.Adapter.Imports list)))
        (list_size (int_range 1 3) message);
      map
        (fun name ->
          Adapter (B.Adapter.Invalid (B.Adapter.Missing_export name)))
        message;
      map
        (fun name ->
          Adapter (B.Adapter.Invalid (B.Adapter.Wrong_export_type name)))
        message;
      return (Adapter B.Adapter.Out_of_fuel);
      map (fun m -> Adapter (B.Adapter.Trap m)) message;
      map (fun size -> Adapter (B.Adapter.Memory_limit size)) size_gen;
      (let* input = oneof_list [ B.Adapter.Request; B.Adapter.Report ] in
       let* address = u32_gen in
       let* length = u32_gen in
       let+ memory_size = size_gen in
       Adapter (B.Adapter.Alloc { input; address; length; memory_size }));
      (let* address = u32_gen in
       let* length = u32_gen in
       let+ memory_size = size_gen in
       Adapter
         (B.Adapter.Response_outside_memory { address; length; memory_size }));
    ]

let with_buffer encode value = (value, encode value)

let captures =
  Gen.map
    (with_buffer encode_captures)
    (Gen.list_size (Gen.int_range 0 4) capture_gen)

let report = Gen.map (with_buffer encode_report) report_value
let response = Gen.map (with_buffer encode_response) any_bytes
let failure = Gen.map (with_buffer encode_failure) failure_value

let internal =
  Gen.map
    (fun message -> (message, encode_failure (Internal message)))
    Generators.utf_8_string

let damaged_of w ~kind ~count =
  let buffer, runs, bytes = finish w in
  Generators.damaged ~bytes (buffer, runs) ~kind ~count

let damaged_captures =
  let open Gen in
  let* list = list_size (int_range 0 3) capture_gen in
  damaged_of (captures_writer list) ~kind:kind_captures
    ~count:(List.length list)

let damaged_report =
  Gen.bind report_value (fun value ->
      damaged_of (report_writer value) ~kind:kind_report ~count:1)

let damaged_response =
  Gen.bind any_bytes (fun bytes ->
      damaged_of (response_writer bytes) ~kind:kind_response ~count:1)

let damaged_failure =
  Gen.bind failure_value (fun value ->
      damaged_of (failure_writer value) ~kind:kind_failure ~count:1)

let any_buffer =
  let open Gen in
  let whole =
    oneof
      [
        map snd captures;
        map snd report;
        map snd response;
        map snd failure;
        map snd internal;
      ]
  in
  oneof
    [
      string_size ~gen:char (int_range 0 40);
      whole;
      (let* buffer = whole in
       let* at = int_range 0 (String.length buffer) in
       let+ piece = string_size ~gen:char (int_range 1 6) in
       let at = min at (String.length buffer) in
       let after = min (String.length buffer) (at + String.length piece) in
       String.sub buffer 0 at ^ piece
       ^ String.sub buffer after (String.length buffer - after));
    ]

let print_range (r : B.range) =
  Printf.sprintf "%d-%d %d:%d-%d:%d" r.start_byte r.end_byte r.start_row
    r.start_column r.end_row r.end_column

let print_node (n : B.Tree.node) =
  Printf.sprintf "%S %s" n.node_type (print_range n.range)

let print_report (report, buffer) =
  Printf.sprintf "{has_error=%b; errors=[%s]; lowest=%s} %s"
    report.B.Tree.has_error
    (String.concat "; "
       (List.map
          (fun (kind, n) ->
            (match kind with
              | B.Tree.Error_node -> "ERROR "
              | Missing_node -> "MISSING ")
            ^ print_node n)
          report.errors))
    (match report.lowest with None -> "None" | Some n -> print_node n)
    (Generators.print_buffer buffer)

let print_captures (captures, buffer) =
  String.concat "; "
    (List.map
       (fun (c : B.Query.capture) ->
         Printf.sprintf "{m=%d p=%d %S %S %s %S}" c.match_number c.pattern
           c.name c.node_type (print_range c.range) c.text)
       captures)
  ^ " "
  ^ Generators.print_buffer buffer

let print_failure (_, buffer) = Generators.print_buffer buffer
