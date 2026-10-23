(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

let unsigned value =
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

(* The last byte is the one whose bit 6 already holds the sign of the
   rest of the value. *)
let signed value =
  let buffer = Buffer.create 10 in
  let rec write value =
    let part = Int64.to_int (Int64.logand value 0x7FL) in
    let rest = Int64.shift_right value 7 in
    let sign = part land 0x40 <> 0 in
    if (Int64.equal rest 0L && not sign) || (Int64.equal rest (-1L) && sign)
    then Buffer.add_char buffer (Char.chr part)
    else (
      Buffer.add_char buffer (Char.chr (part lor 0x80));
      write rest)
  in
  write value;
  Buffer.contents buffer

let header = "\000asm\001\000\000\000"

let section identifier body =
  String.make 1 (Char.chr identifier) ^ unsigned (String.length body) ^ body

let name text = unsigned (String.length text) ^ text
let vector items = unsigned (List.length items) ^ String.concat "" items

type value_type = I32 | I64
type func_type = value_type list * value_type list
type instruction = string

let unreachable = "\x00"
let drop = "\x1a"

let i32_const value =
  let value = if value >= 0x80000000 then value - 0x100000000 else value in
  "\x41" ^ signed (Int64.of_int value)

let i64_const value = "\x42" ^ signed value
let local_get index = "\x20" ^ unsigned index
let global_get index = "\x23" ^ unsigned index
let global_set index = "\x24" ^ unsigned index
let i32_add = "\x6a"
let i64_extend_i32_u = "\xad"
let i64_shl = "\x86"
let i64_or = "\x84"
let memory_grow = "\x40\x00"

(* loop (empty block type), br 0, end *)
let loop_forever = "\x03\x40\x0c\x00\x0b"

type import = Import_func of int | Import_memory of int
type export = Export_func of int | Export_memory | Export_global of int

type memory = {
  minimum : int;
  maximum : int option;
  shared : bool;
  memory64 : bool;
}

type t = {
  types : func_type list;
  imports : (string * string * import) list;
  functions : (int * instruction list) list;
  memory : memory option;
  globals : (value_type * bool * instruction list) list;
  exports : (string * export) list;
  data : (int * string) list;
}

let value_type = function I32 -> "\x7f" | I64 -> "\x7e"
let expression instructions = String.concat "" instructions ^ "\x0b"

let encode_type (params, results) =
  "\x60"
  ^ vector (List.map value_type params)
  ^ vector (List.map value_type results)

let encode_import (module_name, field, import) =
  name module_name ^ name field
  ^
  match import with
  | Import_func index -> "\x00" ^ unsigned index
  | Import_memory minimum -> "\x02\x00" ^ unsigned minimum

let encode_memory memory =
  let flags =
    (match memory.maximum with None -> 0 | Some _ -> 1)
    lor (if memory.shared then 2 else 0)
    lor if memory.memory64 then 4 else 0
  in
  String.make 1 (Char.chr flags)
  ^ unsigned memory.minimum
  ^ match memory.maximum with None -> "" | Some maximum -> unsigned maximum

let encode_global (kind, mutable_, init) =
  value_type kind ^ (if mutable_ then "\x01" else "\x00") ^ expression init

let encode_export (field, export) =
  name field
  ^
  match export with
  | Export_func index -> "\x00" ^ unsigned index
  | Export_memory -> "\x02\x00"
  | Export_global index -> "\x03" ^ unsigned index

(* A body declares no local of its own. *)
let encode_code (_, body) = name ("\x00" ^ expression body)

let encode_data (address, bytes) =
  "\x00" ^ expression [ i32_const address ] ^ name bytes

let encode module_ =
  let optional identifier = function
    | [] -> ""
    | items -> section identifier (vector items)
  in
  String.concat ""
    [
      header;
      optional 1 (List.map encode_type module_.types);
      optional 2 (List.map encode_import module_.imports);
      optional 3 (List.map (fun (index, _) -> unsigned index) module_.functions);
      (match module_.memory with
      | None -> ""
      | Some memory -> section 5 (vector [ encode_memory memory ]));
      optional 6 (List.map encode_global module_.globals);
      optional 7 (List.map encode_export module_.exports);
      optional 10 (List.map encode_code module_.functions);
      optional 11 (List.map encode_data module_.data);
    ]

type alloc = Bump | Zero | Address of int

type body =
  | Respond of string
  | Echo_request
  | Echo_report
  | Range of int * int
  | Loop
  | Grow of int
  | Trap

type adapter = {
  version : int;
  interface_body : instruction list option;
  alloc : alloc;
  recognise : body;
  bind : body;
  pages : int;
  memory_kind : memory -> memory;
  extra_imports : (string * string * import) list;
  missing : string list;
  wrong_types : (string * func_type) list;
  memory_as_global : bool;
  extra_exports : bool;
}

let adapter =
  {
    version = 1;
    interface_body = None;
    alloc = Bump;
    recognise = Respond {|{"recognised":true}|};
    bind = Echo_report;
    pages = 1;
    memory_kind = Fun.id;
    extra_imports = [];
    missing = [];
    wrong_types = [];
    memory_as_global = false;
    extra_exports = false;
  }

let pair address length =
  Int64.logor
    (Int64.shift_left (Int64.of_int address) 32)
    (Int64.logand (Int64.of_int length) 0xFFFFFFFFL)

(* The address and the length of a pair of i32 locals, as the result
   of a call function. *)
let echo address length =
  [
    local_get address;
    i64_extend_i32_u;
    i64_const 32L;
    i64_shl;
    local_get length;
    i64_extend_i32_u;
    i64_or;
  ]

(* The body of a call function. [at] is the address of the data
   segment that holds a [Respond] text. *)
let call_body ~at = function
  | Respond text -> [ i64_const (pair at (String.length text)) ]
  | Echo_request -> echo 0 1
  | Echo_report -> echo 2 3
  | Range (address, length) -> [ i64_const (pair address length) ]
  | Loop -> [ loop_forever; unreachable ]
  | Grow pages -> [ i32_const pages; memory_grow; drop; i64_const 0L ]
  | Trap -> [ unreachable ]

let response = function Respond text -> text | _ -> ""

(* A body that gives a zero of each result type. *)
let zeros (_, results) =
  List.map
    (function I32 -> i32_const 0 | I64 -> i64_const 0L)
    (List.rev results)

let interface_type = ([], [ I32 ])
let alloc_type = ([ I32 ], [ I32 ])
let call_type = ([ I32; I32; I32; I32 ], [ I64 ])

let adapter_module spec =
  let recognise_at = 16 in
  let recognise_text = response spec.recognise in
  let bind_at = recognise_at + String.length recognise_text in
  let bind_text = response spec.bind in
  let heap = max 1024 (bind_at + String.length bind_text) in
  let alloc_body =
    match spec.alloc with
    | Bump -> [ global_get 0; global_get 0; local_get 0; i32_add; global_set 0 ]
    | Zero -> [ i32_const 0 ]
    | Address address -> [ i32_const address ]
  in
  let functions =
    [
      ( "sinter_interface",
        interface_type,
        Option.value spec.interface_body ~default:[ i32_const spec.version ] );
      ("sinter_alloc", alloc_type, alloc_body);
      ("sinter_recognise", call_type, call_body ~at:recognise_at spec.recognise);
      ("sinter_bind", call_type, call_body ~at:bind_at spec.bind);
    ]
  in
  (* A function of a wrong type takes the type and a body that fits
     it. *)
  let functions =
    List.map
      (fun (field, kind, body) ->
        match List.assoc_opt field spec.wrong_types with
        | Some other -> (field, other, zeros other)
        | None -> (field, kind, body))
      functions
  in
  let types =
    List.sort_uniq compare (List.map (fun (_, k, _) -> k) functions)
  in
  let type_index kind =
    let rec find index = function
      | [] -> invalid_arg "Wasm_builder: a type that is not in the list"
      | first :: rest -> if first = kind then index else find (index + 1) rest
    in
    find 0 types
  in
  (* An imported function takes the type of the first function. *)
  let first_type =
    match types with first :: _ -> first | [] -> interface_type
  in
  let imports =
    List.map
      (function
        | module_name, field, Import_func _ ->
            (module_name, field, Import_func (type_index first_type))
        | other -> other)
      spec.extra_imports
  in
  let imported =
    List.length
      (List.filter
         (function _, _, Import_func _ -> true | _ -> false)
         imports)
  in
  let globals =
    (I32, true, [ i32_const heap ])
    ::
    (if spec.extra_exports then
       [ (I32, false, [ i32_const heap ]); (I32, false, [ i32_const heap ]) ]
     else [])
  in
  let exports =
    List.mapi
      (fun index (field, _, _) -> (field, Export_func (imported + index)))
      functions
    @ [
        ( "memory",
          if spec.memory_as_global then Export_global 0 else Export_memory );
      ]
    @
    if spec.extra_exports then
      [ ("__data_end", Export_global 1); ("__heap_base", Export_global 2) ]
    else []
  in
  let exports =
    List.filter (fun (field, _) -> not (List.mem field spec.missing)) exports
  in
  let data =
    List.filter
      (fun (_, text) -> String.length text > 0)
      [ (recognise_at, recognise_text); (bind_at, bind_text) ]
  in
  encode
    {
      types;
      imports;
      functions =
        List.map (fun (_, kind, body) -> (type_index kind, body)) functions;
      memory =
        Some
          (spec.memory_kind
             {
               minimum = spec.pages;
               maximum = None;
               shared = false;
               memory64 = false;
             });
      globals;
      exports;
      data;
    }
