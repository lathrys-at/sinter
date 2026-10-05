(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

open Sinter_core
module Gen = QCheck2.Gen

(* Strings. *)

let string_of_code_points points =
  let buffer = Buffer.create (4 * List.length points) in
  List.iter
    (fun point -> Buffer.add_utf_8_uchar buffer (Uchar.of_int point))
    points;
  Buffer.contents buffer

let code_point =
  Gen.oneof
    [
      Gen.int_range 0x00 0x7F;
      Gen.int_range 0x80 0x7FF;
      Gen.oneof [ Gen.int_range 0x800 0xD7FF; Gen.int_range 0xE000 0xFFFF ];
      Gen.int_range 0x10000 0x10FFFF;
    ]

let utf_8_string =
  Gen.map string_of_code_points (Gen.list_size (Gen.int_range 0 8) code_point)

let ascii_string =
  Gen.map string_of_code_points
    (Gen.list_size (Gen.int_range 0 4) (Gen.int_range 0x20 0x7E))

(* U+E000 is a three-byte code point, and U+10000 is a four-byte one.
   In UTF-8 byte order U+E000 comes first; in UTF-16 code unit order
   U+10000 comes first, because its high surrogate is below U+E000. *)
let key =
  Gen.map string_of_code_points
    (Gen.list_size (Gen.int_range 0 3)
       (Gen.oneof_list
          [
            0x41;
            0x61;
            0x7F;
            0x80;
            0x7FF;
            0x800;
            0xE000;
            0xFFFF;
            0x10000;
            0x10FFFF;
          ]))

(* Each run below is invalid UTF-8 wherever it stands: an unused byte,
   a truncated sequence, an overlong sequence, a surrogate, a code
   point above U+10FFFF, or a continuation byte with no lead byte. A
   valid prefix and a printable ASCII suffix cannot repair one. *)
let bad_run =
  Gen.oneof_list
    [
      "\xff";
      "\xfe";
      "\xc3";
      "\x80";
      "\xc0\xaf";
      "\xe0\x80\x80";
      "\xed\xa0\x80";
      "\xf5\x80\x80\x80";
    ]

let not_utf_8_string =
  Gen.map3
    (fun prefix bad suffix -> prefix ^ bad ^ suffix)
    utf_8_string bad_run ascii_string

(* Records. *)

let max_value = 9007199254740991

let jsonl_int =
  Gen.oneof
    [
      Gen.int_range (-max_value) max_value;
      Gen.int_small;
      Gen.oneof_list [ 0; 1; -1; max_value; -max_value ];
    ]

let jsonl_int_out_of_range =
  Gen.oneof
    [
      Gen.int_range (max_value + 1) max_int;
      Gen.int_range min_int (-max_value - 1);
      Gen.oneof_list [ max_value + 1; -max_value - 1; max_int; min_int ];
    ]

let scalar =
  Gen.oneof
    [
      Gen.map (fun s -> Jsonl.String s) utf_8_string;
      Gen.map (fun i -> Jsonl.Int i) jsonl_int;
      Gen.map (fun b -> Jsonl.Bool b) Gen.bool;
    ]

let value =
  Gen.oneof
    [
      Gen.map (fun s -> Jsonl.Scalar s) scalar;
      Gen.map
        (fun l -> Jsonl.Array l)
        (Gen.list_size (Gen.int_range 0 4) scalar);
    ]

let record_key = Gen.oneof [ key; utf_8_string ]

(* Keep the first pair of each name, so that the record holds no name
   twice. *)
let with_distinct_names pairs =
  let rec keep seen = function
    | [] -> []
    | (name, value) :: rest ->
        if List.exists (String.equal name) seen then keep seen rest
        else (name, value) :: keep (name :: seen) rest
  in
  keep [] pairs

let record =
  Gen.map with_distinct_names
    (Gen.list_size (Gen.int_range 0 6) (Gen.pair record_key value))

(* Put [pair] into [record] at position [index]. *)
let insert record index pair =
  let index = if record = [] then 0 else index mod (List.length record + 1) in
  let rec place at = function
    | rest when at = index -> pair :: rest
    | [] -> [ pair ]
    | first :: rest -> first :: place (at + 1) rest
  in
  place 0 record

let record_with_a_repeated_field =
  let open Gen in
  let* fields =
    map with_distinct_names (list_size (int_range 1 5) (pair record_key value))
  in
  let* which = int_range 0 (List.length fields - 1) in
  let* replacement = value in
  let+ index = int_range 0 (List.length fields) in
  let name, _ = List.nth fields which in
  insert fields index (name, replacement)

let record_with_an_integer_out_of_range =
  let open Gen in
  let* fields = record in
  let* name = record_key in
  let* out_of_range = jsonl_int_out_of_range in
  let* in_an_array = bool in
  let+ index = int_range 0 (List.length fields) in
  let broken =
    if in_an_array then Jsonl.Array [ Jsonl.Int out_of_range ]
    else Jsonl.Scalar (Jsonl.Int out_of_range)
  in
  let name =
    if List.mem_assoc name fields then name ^ "\xef\xbf\xbd" else name
  in
  insert fields index (name, broken)

let record_with_a_string_that_is_not_utf_8 =
  let open Gen in
  let* fields = record in
  let* name = record_key in
  let* bad = not_utf_8_string in
  let* where = int_range 0 2 in
  let+ index = int_range 0 (List.length fields) in
  let name =
    if List.mem_assoc name fields then name ^ "\xef\xbf\xbd" else name
  in
  match where with
  | 0 -> insert fields index (bad, Jsonl.Scalar (Jsonl.Bool true))
  | 1 -> insert fields index (name, Jsonl.Scalar (Jsonl.String bad))
  | _ -> insert fields index (name, Jsonl.Array [ Jsonl.String bad ])

let print_scalar = function
  | Jsonl.String s -> Printf.sprintf "String %S" s
  | Jsonl.Int i -> Printf.sprintf "Int %d" i
  | Jsonl.Bool b -> Printf.sprintf "Bool %b" b

let print_value = function
  | Jsonl.Scalar s -> print_scalar s
  | Jsonl.Array items ->
      "Array [" ^ String.concat "; " (List.map print_scalar items) ^ "]"

let print_record fields =
  "["
  ^ String.concat "; "
      (List.map
         (fun (name, value) ->
           Printf.sprintf "(%S, %s)" name (print_value value))
         fields)
  ^ "]"

(* The result buffer of the bridge. *)

let kind_captures = 0
let kind_tree = 1
let add_u32 buffer value = Buffer.add_int32_le buffer (Int32.of_int value)

(* Record the offset of each length field, and the length it holds, so
   that a damaged buffer can aim at one. *)
let add_run buffer runs s =
  runs := (Buffer.length buffer, String.length s) :: !runs;
  add_u32 buffer (String.length s);
  Buffer.add_string buffer s

let add_header buffer ~kind ~count =
  Buffer.add_string buffer "SBR1";
  add_u32 buffer kind;
  add_u32 buffer count;
  add_u32 buffer 0

let captures_bytes captures =
  let buffer = Buffer.create 256 in
  let runs = ref [] in
  add_header buffer ~kind:kind_captures ~count:(List.length captures);
  List.iter
    (fun (c : Sinter_bridge.capture) ->
      add_u32 buffer c.pattern;
      add_u32 buffer c.start_byte;
      add_u32 buffer c.end_byte;
      add_u32 buffer c.start_row;
      add_u32 buffer c.start_column;
      add_u32 buffer c.end_row;
      add_u32 buffer c.end_column;
      add_run buffer runs c.name;
      add_run buffer runs c.node_type;
      add_run buffer runs c.text)
    captures;
  (Buffer.contents buffer, List.rev !runs)

let tree_bytes text =
  let buffer = Buffer.create 256 in
  let runs = ref [] in
  add_header buffer ~kind:kind_tree ~count:1;
  add_run buffer runs text;
  (Buffer.contents buffer, List.rev !runs)

let encode_captures captures = fst (captures_bytes captures)
let encode_tree text = fst (tree_bytes text)
let u32 = Gen.oneof [ Gen.nat_small; Gen.int_range 0 0xFFFFFFFF ]

let capture =
  let open Gen in
  let* pattern = u32 in
  let* start_byte = u32 in
  let* end_byte = u32 in
  let* start_row = u32 in
  let* start_column = u32 in
  let* end_row = u32 in
  let* end_column = u32 in
  let* name = utf_8_string in
  let* node_type = utf_8_string in
  let+ text = utf_8_string in
  {
    Sinter_bridge.pattern;
    name;
    node_type;
    start_byte;
    end_byte;
    start_row;
    start_column;
    end_row;
    end_column;
    text;
  }

let captures_buffer =
  Gen.map
    (fun captures -> (captures, encode_captures captures))
    (Gen.list_size (Gen.int_range 0 4) capture)

let tree_buffer = Gen.map (fun text -> (text, encode_tree text)) utf_8_string

type damage =
  | Truncated
  | Length_out_of_range
  | Not_utf_8
  | Wrong_magic
  | Wrong_kind
  | Wrong_count
  | Trailing_bytes

let damaged (buffer, runs) ~kind ~count =
  let open Gen in
  let length = String.length buffer in
  let changed f =
    let bytes = Bytes.of_string buffer in
    f bytes;
    Bytes.to_string bytes
  in
  let truncated =
    let+ cut = int_range 0 (length - 1) in
    (Truncated, String.sub buffer 0 cut)
  in
  let wrong_magic =
    let+ index = int_range 0 3 in
    (Wrong_magic, changed (fun bytes -> Bytes.set bytes index '\000'))
  in
  let wrong_kind =
    let+ other = oneof_list (List.filter (( <> ) kind) [ 0; 1; 2; 255 ]) in
    ( Wrong_kind,
      changed (fun bytes -> Bytes.set_int32_le bytes 4 (Int32.of_int other)) )
  in
  let wrong_count =
    let+ other =
      oneof_list (List.filter (( <> ) count) [ 0; 1; 2; 3; 0xFFFFFFF0 ])
    in
    ( Wrong_count,
      changed (fun bytes -> Bytes.set_int32_le bytes 8 (Int32.of_int other)) )
  in
  let trailing =
    let+ extra = string_size (int_range 1 4) in
    (Trailing_bytes, buffer ^ extra)
  in
  let length_out_of_range =
    match runs with
    | [] -> None
    | _ ->
        Some
          (let+ which = int_range 0 (List.length runs - 1) in
           let at, _ = List.nth runs which in
           ( Length_out_of_range,
             changed (fun bytes ->
                 Bytes.set_int32_le bytes at (Int32.of_int 0xFFFFFFF0)) ))
  in
  let not_utf_8 =
    match List.filter (fun (_, held) -> held > 0) runs with
    | [] -> None
    | usable ->
        Some
          (let* which = int_range 0 (List.length usable - 1) in
           let at, held = List.nth usable which in
           let+ inside = int_range 0 (held - 1) in
           ( Not_utf_8,
             changed (fun bytes -> Bytes.set bytes (at + 4 + inside) '\xff') ))
  in
  oneof
    (truncated :: wrong_magic :: wrong_kind :: wrong_count :: trailing
    :: List.filter_map Fun.id [ length_out_of_range; not_utf_8 ])

let damaged_captures_buffer =
  let open Gen in
  let* captures = list_size (int_range 0 3) capture in
  damaged (captures_bytes captures) ~kind:kind_captures
    ~count:(List.length captures)

let damaged_tree_buffer =
  let open Gen in
  let* text = utf_8_string in
  damaged (tree_bytes text) ~kind:kind_tree ~count:1

let print_buffer buffer =
  String.concat ""
    (List.init (String.length buffer) (fun index ->
         Printf.sprintf "%02x" (Char.code buffer.[index])))

let print_damage = function
  | Truncated -> "Truncated"
  | Length_out_of_range -> "Length_out_of_range"
  | Not_utf_8 -> "Not_utf_8"
  | Wrong_magic -> "Wrong_magic"
  | Wrong_kind -> "Wrong_kind"
  | Wrong_count -> "Wrong_count"
  | Trailing_bytes -> "Trailing_bytes"

let print_damaged (damage, buffer) =
  print_damage damage ^ " " ^ print_buffer buffer

let print_capture (c : Sinter_bridge.capture) =
  Printf.sprintf
    "{pattern=%d; name=%S; node_type=%S; sb=%d; eb=%d; sr=%d; sc=%d; er=%d; \
     ec=%d; text=%S}"
    c.pattern c.name c.node_type c.start_byte c.end_byte c.start_row
    c.start_column c.end_row c.end_column c.text

let print_captures captures =
  "[" ^ String.concat "; " (List.map print_capture captures) ^ "]"

(* Splice [piece] into [text] at [at], over the bytes that stand
   there. *)
let splice text at piece =
  let at = min at (String.length text) in
  let after = min (String.length text) (at + String.length piece) in
  String.sub text 0 at ^ piece
  ^ String.sub text after (String.length text - after)

let buffer_bytes =
  let open Gen in
  let any = string_size (int_range 0 40) in
  let whole = map (fun (_, buffer) -> buffer) captures_buffer in
  oneof
    [
      any;
      map (fun bytes -> "SBR1" ^ bytes) any;
      (let* buffer = whole in
       let* at = int_range 0 (String.length buffer) in
       let+ piece = string_size (int_range 1 6) in
       splice buffer at piece);
      whole;
      map (fun (_, buffer) -> buffer) tree_buffer;
    ]

(* Source text, and a capture inside it. *)

let rows_before text offset =
  let rows = ref 0 in
  for index = 0 to offset - 1 do
    if text.[index] = '\n' then incr rows
  done;
  !rows

let start_of_line text offset =
  let start = ref 0 in
  for index = 0 to offset - 1 do
    if text.[index] = '\n' then start := index + 1
  done;
  !start

let source_text =
  Gen.map (String.concat "")
    (Gen.list_size (Gen.int_bound 60)
       (Gen.oneof_list_weighted
          [
            (8, "a");
            (4, "\n");
            (3, " ");
            (2, "\xc3\xa9");
            (2, "\xe2\x82\xac");
            (2, "\xf0\x9f\x94\xa5");
            (1, "\t");
          ]))

(* Every offset where a code point starts, and then the length of the
   text. A capture of the bridge starts and ends at one of these. *)
let code_point_offsets text =
  let length = String.length text in
  let rec walk offset acc =
    if offset >= length then List.rev (length :: acc)
    else
      let decoded = String.get_utf_8_uchar text offset in
      walk (offset + Uchar.utf_decode_length decoded) (offset :: acc)
  in
  walk 0 []

let capture_in source =
  let open Gen in
  let offsets = Array.of_list (code_point_offsets source) in
  let last = Array.length offsets - 1 in
  let* first = int_bound last in
  let* beyond = int_range first last in
  let* pattern = nat_small in
  let* name = oneof_list [ "key"; "value"; "number"; "d" ] in
  let+ node_type =
    oneof_list [ "string_content"; "number"; "pair"; "document" ]
  in
  let start_byte = offsets.(first) and end_byte = offsets.(beyond) in
  {
    Sinter_bridge.pattern;
    name;
    node_type;
    start_byte;
    end_byte;
    start_row = rows_before source start_byte;
    start_column = start_byte - start_of_line source start_byte;
    end_row = rows_before source end_byte;
    end_column = end_byte - start_of_line source end_byte;
    text = String.sub source start_byte (end_byte - start_byte);
  }

(* A capture whose byte range is not inside the source: the end runs
   past the source, or the end is before the start, or the start is
   below 0. The end row is one past the row of the end byte, so that
   the reader of the span reaches the branch that steps back a line. *)
let capture_outside source =
  let open Gen in
  let length = String.length source in
  let held offset = min (max offset 0) length in
  let* start_byte, end_byte =
    oneof
      [
        (let* start_byte = int_bound length in
         let+ beyond = int_range 1 8 in
         (start_byte, length + beyond));
        (let* start_byte = int_range 1 (length + 1) in
         let+ end_byte = int_bound (start_byte - 1) in
         (start_byte, end_byte));
        (let* start_byte = int_range (-8) (-1) in
         let+ end_byte = int_bound length in
         (start_byte, end_byte));
      ]
  in
  let* pattern = nat_small in
  let+ end_column = oneof_list [ 0; 0; 1; 2 ] in
  {
    Sinter_bridge.pattern;
    name = "d";
    node_type = "document";
    start_byte;
    end_byte;
    start_row = rows_before source (held start_byte);
    start_column = held start_byte - start_of_line source (held start_byte);
    end_row = rows_before source (held end_byte) + 1;
    end_column;
    text = "";
  }

let source_and_capture =
  let open Gen in
  let* source = source_text in
  let+ capture = capture_in source in
  (source, capture)

let source_and_capture_outside =
  let open Gen in
  let* source = source_text in
  let+ capture = capture_outside source in
  (source, capture)

let print_source_and_capture (source, capture) =
  Printf.sprintf "source=%S capture=%s" source (print_capture capture)

(* Text for the bridge. *)

let json_source =
  let open Gen in
  let pad width = String.make width ' ' in
  let text =
    map
      (fun pieces -> "\"" ^ String.concat "" pieces ^ "\"")
      (list_size (int_bound 6)
         (oneof_list_weighted
            [
              (8, "a");
              (4, "b");
              (2, "1");
              (2, " ");
              (1, "\\\"");
              (1, "\\\\");
              (1, "\\n");
              (2, "\xc3\xa9");
              (2, "\xe2\x82\xac");
              (2, "\xf0\x9f\x94\xa5");
            ]))
  in
  let leaf =
    oneof_weighted
      [
        (4, text);
        (3, map string_of_int (int_range (-9999) 9999));
        (1, oneof_list [ "true"; "false"; "null" ]);
      ]
  in
  let block indent opening closing items =
    if items = [] then opening ^ closing
    else
      opening ^ "\n"
      ^ String.concat ",\n"
          (List.map (fun item -> pad (indent + 2) ^ item) items)
      ^ "\n" ^ pad indent ^ closing
  in
  let rec value indent depth =
    if depth <= 0 then leaf
    else
      oneof_weighted
        [ (5, leaf); (3, array indent depth); (3, object_ indent depth) ]
  and array indent depth =
    map (block indent "[" "]")
      (list_size (int_bound 4) (value (indent + 2) (depth - 1)))
  and object_ indent depth =
    map (block indent "{" "}")
      (list_size (int_bound 4)
         (map
            (fun (key, item) -> key ^ ": " ^ item)
            (pair text (value (indent + 2) (depth - 1)))))
  in
  value 0 3

let any_utf_8_text =
  let open Gen in
  map (String.concat "")
    (list_size (int_bound 40)
       (oneof_weighted
          [
            ( 6,
              oneof_list
                [ "{"; "}"; "["; "]"; ":"; ","; "\""; "1"; "a"; " "; "\n" ] );
            (2, utf_8_string);
          ]))

let any_text =
  let open Gen in
  map (String.concat "")
    (list_size (int_bound 40)
       (oneof_weighted
          [
            ( 6,
              oneof_list
                [ "{"; "}"; "["; "]"; ":"; ","; "\""; "1"; "a"; " "; "\n" ] );
            (2, map (String.make 1) (char_range '\000' '\255'));
          ]))

(* WebAssembly modules. *)

let leb128 value =
  let buffer = Buffer.create 5 in
  let rest = ref value in
  let more = ref true in
  while !more do
    let part = !rest land 0x7F in
    rest := !rest lsr 7;
    if !rest = 0 then (
      Buffer.add_char buffer (Char.chr part);
      more := false)
    else Buffer.add_char buffer (Char.chr (part lor 0x80))
  done;
  Buffer.contents buffer

let wasm_header = "\000asm\001\000\000\000"

let wasm_section identifier body =
  String.make 1 (Char.chr identifier) ^ leb128 (String.length body) ^ body

(* One export: the length of the name, the name, the kind of the
   export, and its index. The index is a LEB128 number, and the format
   allows an encoding longer than the value needs, so the caller gives
   the bytes of the index and not the value. *)
let wasm_export ~index name =
  leb128 (String.length name) ^ name ^ "\000" ^ index

(* The export section. [declared] is the count the section states,
   which the caller can set against the number of exports that follow
   it. *)
let wasm_export_section ~declared exports =
  wasm_section 7 (leb128 declared ^ String.concat "" exports)

(* A custom section. Its body is the name of the section and then
   [content]. *)
let wasm_custom_section content = wasm_section 0 (leb128 4 ^ "name" ^ content)

type wasm_shape =
  | One_export
  | Custom_section_before
  | Long_custom_section
  | Three_exports
  | Long_export_index
  | Too_few_exports_declared
  | Too_many_exports_declared
  | Cut_in_a_section

(* A custom section whose body is 128 bytes, so that the size of the
   section needs two LEB128 bytes. Five of those bytes are the name of
   the section, and the rest is padding.

   The padding is 0xFF, and not 0. A reader that loses its place
   inside the section then meets a number that never ends, and it
   stops. Through a run of zeros it would walk on, two bytes at a
   time, and it could come out at the export section by luck. *)
let long_custom_section =
  let name = leb128 4 ^ "name" in
  wasm_custom_section (String.make (128 - String.length name) '\255')

let wasm_module shape ~name =
  let grammar = "tree_sitter_" ^ name in
  let index = leb128 0 in
  let one_export =
    wasm_export_section ~declared:1 [ wasm_export ~index grammar ]
  in
  (* Three exports, and the one of the grammar last. *)
  let three =
    [
      wasm_export ~index "a"; wasm_export ~index "b"; wasm_export ~index grammar;
    ]
  in
  match shape with
  | One_export -> wasm_header ^ one_export
  | Custom_section_before ->
      wasm_header ^ wasm_custom_section (String.make 3 '\000') ^ one_export
  | Long_custom_section -> wasm_header ^ long_custom_section ^ one_export
  | Three_exports -> wasm_header ^ wasm_export_section ~declared:3 three
  | Long_export_index ->
      wasm_header
      ^ wasm_export_section ~declared:2
          [
            wasm_export ~index:"\128\128\128\128\000" "a";
            wasm_export ~index grammar;
          ]
  | Too_few_exports_declared ->
      wasm_header ^ wasm_export_section ~declared:2 three
  | Too_many_exports_declared ->
      (* The bytes of the export of the grammar follow the section,
         and the size of the section does not cover them. A reader
         that trusts the count over the size walks into them. *)
      wasm_header
      ^ wasm_export_section ~declared:3
          [ wasm_export ~index "a"; wasm_export ~index "b" ]
      ^ wasm_export ~index grammar
  | Cut_in_a_section ->
      let whole = wasm_header ^ one_export in
      (* The kind and the index of the one export go, and the size of
         the section still counts them. *)
      String.sub whole 0 (String.length whole - 2)

let wasm_shapes_that_hold_a_name =
  [
    One_export;
    Custom_section_before;
    Long_custom_section;
    Three_exports;
    Long_export_index;
  ]

let grammar_export_name =
  Gen.map (String.concat "")
    (Gen.list_size (Gen.int_range 1 8)
       (Gen.oneof_list [ "j"; "s"; "o"; "n"; "_"; "0"; "z" ]))

let wasm_module_with_a_name =
  let open Gen in
  let* shape = oneof_list wasm_shapes_that_hold_a_name in
  let+ name = grammar_export_name in
  (name, wasm_module shape ~name)

(* A module whose export names the grammar with a NUL byte in the
   name. The bridge loads a grammar under a C string, so it can load
   no grammar under such a name. *)
let wasm_module_whose_name_holds_a_nul =
  let open Gen in
  let* shape = oneof_list wasm_shapes_that_hold_a_name in
  let* head = grammar_export_name in
  let+ tail = grammar_export_name in
  wasm_module shape ~name:(head ^ "\000" ^ tail)

let wasm_bytes =
  let open Gen in
  let noise = string_size ~gen:(char_range '\000' '\255') (int_bound 40) in
  let cut_or_changed =
    let* shape = oneof_list wasm_shapes_that_hold_a_name in
    let* name = grammar_export_name in
    let whole = wasm_module shape ~name in
    let* cut = int_range 0 (String.length whole) in
    let short = String.sub whole 0 cut in
    if String.length short = 0 then return short
    else
      let* at = int_bound (String.length short - 1) in
      let+ replacement = char_range '\000' '\255' in
      let bytes = Bytes.of_string short in
      Bytes.set bytes at replacement;
      Bytes.to_string bytes
  in
  oneof_weighted
    [
      (2, noise);
      (2, map (fun rest -> wasm_header ^ rest) noise);
      (3, cut_or_changed);
      (1, map snd wasm_module_with_a_name);
    ]

let grammar_file_path =
  Gen.map (String.concat "")
    (Gen.list_size (Gen.int_bound 12)
       (Gen.oneof_list_weighted
          [
            (6, "a");
            (3, "-");
            (2, ".");
            (2, "/");
            (1, "_");
            (1, "tree-sitter-");
            (1, " ");
          ]))

(* The output of git diff. *)

let must_quote c = c < ' ' || c = '"' || c = '\\' || c >= '\x7f'

let quote_path path =
  if not (String.exists must_quote path) then path
  else
    let buffer = Buffer.create (2 * String.length path) in
    Buffer.add_char buffer '"';
    String.iter
      (fun c ->
        match c with
        | '\007' -> Buffer.add_string buffer "\\a"
        | '\b' -> Buffer.add_string buffer "\\b"
        | '\t' -> Buffer.add_string buffer "\\t"
        | '\n' -> Buffer.add_string buffer "\\n"
        | '\011' -> Buffer.add_string buffer "\\v"
        | '\012' -> Buffer.add_string buffer "\\f"
        | '\r' -> Buffer.add_string buffer "\\r"
        | '"' -> Buffer.add_string buffer "\\\""
        | '\\' -> Buffer.add_string buffer "\\\\"
        | c when must_quote c ->
            Buffer.add_string buffer (Printf.sprintf "\\%03o" (Char.code c))
        | c -> Buffer.add_char buffer c)
      path;
    Buffer.add_char buffer '"';
    Buffer.contents buffer

let diff_path =
  Gen.map (String.concat "")
    (Gen.list_size (Gen.int_range 1 6)
       (Gen.oneof_list_weighted
          [
            (8, "a");
            (3, "/");
            (2, " ");
            (2, " b/");
            (2, "\t");
            (1, "\n");
            (1, "\"");
            (1, "\\");
            (1, "\x01");
            (1, "\x7f");
            (1, "\xc3\xa9");
            (1, "\xff");
          ]))

(* [header_range ~start ~count] is one side of a hunk header. Git
   leaves out a count of 1; the generator writes it out at times. *)
let header_range ~sign ~start ~count =
  let open Gen in
  let+ write_one = bool in
  if count = 1 && not write_one then Printf.sprintf "%c%d" sign start
  else Printf.sprintf "%c%d,%d" sign start count

let function_text = Gen.oneof_list [ ""; " "; " let f x ="; " @@ x @@"; " \t" ]

let hunk_header =
  let open Gen in
  let range = pair (int_bound 2000) (int_bound 50) in
  let* old_start, old_count = range in
  let* new_start, new_count = range in
  let old_start = if old_count > 0 then old_start + 1 else old_start in
  let new_start = if new_count > 0 then new_start + 1 else new_start in
  let* old_side = header_range ~sign:'-' ~start:old_start ~count:old_count in
  let* new_side = header_range ~sign:'+' ~start:new_start ~count:new_count in
  let+ tail = function_text in
  ( Printf.sprintf "@@ %s %s @@%s" old_side new_side tail,
    Git.Decode.{ old_start; old_count; new_start; new_count } )

let print_hunk_header (text, (h : Git.Decode.header)) =
  Printf.sprintf "%S {old_start=%d; old_count=%d; new_start=%d; new_count=%d}"
    text h.old_start h.old_count h.new_start h.new_count

let damaged_hunk_header =
  let open Gen in
  let* text, _ = hunk_header in
  let length = String.length text in
  oneof
    [
      map (fun at -> String.sub text 0 at) (int_bound length);
      (let* at = int_bound length in
       let+ piece =
         string_size
           ~gen:(oneof_list [ '@'; '-'; '+'; ','; ' '; '0'; '9'; 'x'; '\n' ])
           (int_range 1 3)
       in
       splice text at piece);
      string_size (int_range 0 24);
    ]

(* The lines of a run of changed lines, as git -U0 writes them, and the
   marker that git writes after a last line with no line feed. *)
let changed_lines sign count =
  let open Gen in
  let* lines =
    list_size (pure count)
      (map
         (fun text -> Printf.sprintf "%c%s" sign text)
         (string_size
            ~gen:(oneof_list [ 'a'; ' '; '-'; '+'; '@'; '\\'; '\r'; '\000' ])
            (int_bound 6)))
  in
  let+ marker =
    oneof_weighted
      [ (5, pure []); (1, pure [ "\\ No newline at end of file" ]) ]
  in
  if count > 0 then lines @ marker else lines

(* One hunk of git -U0: its text, and the hunk that the reader gives. *)
let u0_hunk =
  let open Gen in
  let* added, removed =
    oneof
      [ pair (int_range 1 4) (int_bound 4); pair (int_bound 4) (int_range 1 4) ]
  in
  let* line = int_range 1 3000 in
  let* old_start = int_range (if removed > 0 then 1 else 0) 3000 in
  let new_start, eline =
    if added > 0 then (line, line + added - 1) else (line - 1, line)
  in
  let* old_side = header_range ~sign:'-' ~start:old_start ~count:removed in
  let* new_side = header_range ~sign:'+' ~start:new_start ~count:added in
  let* tail = function_text in
  let* minus = changed_lines '-' removed in
  let+ plus = changed_lines '+' added in
  ( (Printf.sprintf "@@ %s %s @@%s" old_side new_side tail :: minus) @ plus,
    Git.{ line; eline; added; removed } )

(* The header lines of a section, in front of its hunks. *)
let section_headers path ~binary =
  let open Gen in
  let named = quote_path ("a/" ^ path) and other = quote_path ("b/" ^ path) in
  let* modes =
    oneof_list
      [
        [];
        [ "old mode 100644"; "new mode 100755" ];
        [ "new file mode 100644" ];
        [ "deleted file mode 100644" ];
      ]
  in
  let index = "index 0123abc..4567def" in
  let+ names =
    oneof_list
      [
        [ "--- " ^ named; "+++ " ^ other ]; [ "--- /dev/null"; "+++ " ^ other ];
      ]
  in
  let first = Printf.sprintf "diff --git %s %s" named other in
  if binary then
    (first :: modes)
    @ [ index; Printf.sprintf "Binary files %s and %s differ" named other ]
  else (first :: modes) @ (index :: names)

(* One section: its lines, its path, whether it is binary, and its
   hunks. A binary section holds no hunk. *)
let section path =
  let open Gen in
  let* binary = oneof_weighted [ (4, pure false); (1, pure true) ] in
  let* headers = section_headers path ~binary in
  let+ hunks = if binary then pure [] else list_size (int_bound 4) u0_hunk in
  (headers @ List.concat_map fst hunks, path, binary, List.map snd hunks)

let diff_output =
  let open Gen in
  let* paths = list_size (int_bound 5) diff_path in
  (* A path drawn twice stands for a file whose type changed: git then
     writes two sections for it. *)
  let* sections = flatten_list (List.map section paths) in
  let lines = List.concat_map (fun (lines, _, _, _) -> lines) sections in
  let output = String.concat "" (List.map (fun line -> line ^ "\n") lines) in
  let paths = List.sort_uniq String.compare paths in
  let expected =
    List.map
      (fun path ->
        let mine =
          List.filter (fun (_, p, _, _) -> String.equal p path) sections
        in
        if List.exists (fun (_, _, binary, _) -> binary) mine then
          (path, Git.Binary)
        else (path, Git.Modified (List.concat_map (fun (_, _, _, h) -> h) mine)))
      paths
  in
  pure (output, expected)

(* One hunk that holds context lines between its runs of changed lines,
   as git writes it when its configuration asks for context: its text,
   and the runs that the reader gives. *)
let diff_output_with_context =
  let open Gen in
  let run =
    oneof
      [ pair (int_range 1 3) (int_bound 3); pair (int_bound 3) (int_range 1 3) ]
  in
  let* runs = list_size (int_range 1 4) run in
  let* gaps = list_size (pure (List.length runs)) (int_range 1 3) in
  let* trailing = int_bound 2 in
  let* start = int_range 1 500 in
  let rec build lines runs_found cursor old_count new_count = function
    | [] ->
        let lines = lines @ List.init trailing (fun _ -> " c") in
        (lines, List.rev runs_found, old_count + trailing, new_count + trailing)
    | ((added, removed), gap) :: rest ->
        let context = List.init gap (fun _ -> " c") in
        let line = cursor + gap in
        let eline = if added > 0 then line + added - 1 else line in
        let changed =
          List.init removed (fun _ -> "-x") @ List.init added (fun _ -> "+y")
        in
        build
          (lines @ context @ changed)
          (Git.{ line; eline; added; removed } :: runs_found)
          (line + added)
          (old_count + gap + removed)
          (new_count + gap + added)
          rest
  in
  let lines, runs, old_count, new_count =
    build [] [] start 0 0 (List.combine runs gaps)
  in
  let header =
    Printf.sprintf "@@ -%d,%d +%d,%d @@" start old_count start new_count
  in
  let output =
    String.concat ""
      (List.map
         (fun line -> line ^ "\n")
         ([
            "diff --git a/f b/f";
            "index 0123abc..4567def 100644";
            "--- a/f";
            "+++ b/f";
            header;
          ]
         @ lines))
  in
  pure (output, runs)

let damaged_diff_output =
  let open Gen in
  let* output, _ = diff_output in
  let lines = String.split_on_char '\n' output in
  let count = List.length lines in
  oneof
    [
      map (fun at -> String.sub output 0 at) (int_bound (String.length output));
      map
        (fun at -> String.concat "\n" (List.filteri (fun i _ -> i <> at) lines))
        (int_bound count);
      map
        (fun at ->
          String.concat "\n"
            (List.concat
               (List.mapi (fun i l -> if i = at then [ l; l ] else [ l ]) lines)))
        (int_bound count);
      (let* at = int_bound (String.length output) in
       let+ piece =
         string_size
           ~gen:
             (oneof_list [ '@'; '-'; '+'; ' '; '\\'; '"'; '\n'; 'd'; '0'; ',' ])
           (int_range 1 4)
       in
       splice output at piece);
      string_size (int_range 0 40);
    ]

let print_change = function
  | Git.Added -> "Added"
  | Git.Deleted -> "Deleted"
  | Git.Binary -> "Binary"
  | Git.Modified hunks ->
      "Modified ["
      ^ String.concat "; "
          (List.map
             (fun (h : Git.hunk) ->
               Printf.sprintf "%d-%d +%d -%d" h.line h.eline h.added h.removed)
             hunks)
      ^ "]"

let print_changes changes =
  "["
  ^ String.concat "; "
      (List.map
         (fun (path, change) ->
           Printf.sprintf "%S %s" path (print_change change))
         changes)
  ^ "]"

(* The output of git for-each-ref. *)

let kind_name = function
  | Git.Decode.Blob -> "blob"
  | Git.Decode.Tree -> "tree"
  | Git.Decode.Commit -> "commit"
  | Git.Decode.Tag -> "tag"

let ref_name =
  Gen.map
    (fun parts -> String.concat "/" ("refs" :: parts))
    (Gen.list_size (Gen.int_range 1 3)
       (Gen.oneof_list [ "heads"; "remotes"; "origin"; "main"; "a b"; "x@y" ]))

let object_id =
  let open Gen in
  let* length = oneof_list [ 40; 64 ] in
  string_size
    ~gen:(oneof_list (String.to_seq "0123456789abcdef" |> List.of_seq))
    (pure length)

let ref_entry =
  let open Gen in
  let* refname = ref_name in
  let* kind = oneof_list Git.Decode.[ Blob; Tree; Commit; Tag ] in
  let* id = object_id in
  let+ upstream = oneof [ pure ""; ref_name ] in
  Git.Decode.{ refname; kind; id; upstream }

let render_ref (entry : Git.Decode.ref_entry) =
  String.concat "\000"
    [ entry.refname; kind_name entry.kind; entry.id; entry.upstream ]
  ^ "\n"

let refs_output =
  Gen.map
    (fun entries -> (String.concat "" (List.map render_ref entries), entries))
    (Gen.list_size (Gen.int_bound 4) ref_entry)

let print_refs_output (output, _) = Printf.sprintf "%S" output

let damaged_refs_output =
  let open Gen in
  let* output, _ = refs_output in
  let length = String.length output in
  oneof
    [
      map (fun at -> String.sub output 0 at) (int_bound length);
      (let* at = int_bound length in
       let+ piece =
         string_size
           ~gen:(oneof_list [ '\000'; '\n'; 'a'; 'g'; ' '; 'c' ])
           (int_range 1 3)
       in
       splice output at piece);
      string_size (int_range 0 40);
    ]
