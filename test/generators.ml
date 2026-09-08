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
  | Trailing_bytes

let damaged (buffer, runs) ~kind =
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
    (truncated :: wrong_magic :: wrong_kind :: trailing
    :: List.filter_map Fun.id [ length_out_of_range; not_utf_8 ])

let damaged_captures_buffer =
  let open Gen in
  let* captures = list_size (int_range 0 3) capture in
  damaged (captures_bytes captures) ~kind:kind_captures

let damaged_tree_buffer =
  let open Gen in
  let* text = utf_8_string in
  damaged (tree_bytes text) ~kind:kind_tree

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

let source_and_capture =
  let open Gen in
  let* source = source_text in
  let+ capture = capture_in source in
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

let wasm_module ~before ~name =
  let exported = "tree_sitter_" ^ name in
  (* A name, then the kind of the export, then its index. *)
  let entry = leb128 (String.length exported) ^ exported ^ "\000" ^ leb128 0 in
  let custom =
    if before then wasm_section 0 (leb128 4 ^ "name" ^ String.make 3 '\000')
    else ""
  in
  wasm_header ^ custom ^ wasm_section 7 (leb128 1 ^ entry)

let grammar_export_name =
  Gen.map (String.concat "")
    (Gen.list_size (Gen.int_range 1 8)
       (Gen.oneof_list [ "j"; "s"; "o"; "n"; "_"; "0"; "z" ]))

let wasm_module_with_a_name =
  let open Gen in
  let* before = bool in
  let+ name = grammar_export_name in
  (name, wasm_module ~before ~name)

let wasm_bytes =
  let open Gen in
  let noise = string_size ~gen:(char_range '\000' '\255') (int_bound 40) in
  let cut_or_changed =
    let* before = bool in
    let* name = grammar_export_name in
    let whole = wasm_module ~before ~name in
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
