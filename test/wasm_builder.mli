(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(** A builder of WebAssembly modules in the binary format. The tests build
    runner adapters with it, the valid ones and the ones that break a rule, so
    that they need no WebAssembly toolchain. *)

(** {1 The encoding} *)

val unsigned : int -> string
(** [unsigned value] is [value] as an unsigned LEB128 number. [value] is 0 or
    more. *)

val signed : int64 -> string
(** [signed value] is [value] as a signed LEB128 number. *)

val header : string
(** The eight bytes that start a module: the magic and version 1. *)

val section : int -> string -> string
(** [section identifier body] is a section with the identifier [identifier] and
    the content [body]. *)

(** {1 Modules} *)

type value_type = I32 | I64

type func_type = value_type list * value_type list
(** The parameters and the results of a function. *)

type instruction
(** One instruction, with its immediate values. *)

val unreachable : instruction
val drop : instruction

val i32_const : int -> instruction
(** [i32_const value] pushes the 32 bits of [value]. [value] is from [-2^31] to
    [2^32 - 1], and a value of [2^31] or more stands for its two's complement.
*)

val i64_const : int64 -> instruction
val local_get : int -> instruction
val global_get : int -> instruction
val global_set : int -> instruction
val i32_add : instruction
val i64_extend_i32_u : instruction
val i64_shl : instruction
val i64_or : instruction

val memory_grow : instruction
(** Grows the memory 0 by the number of pages on the stack, and pushes the old
    size in pages, or [-1]. *)

val loop_forever : instruction
(** A loop that branches to its own start and never ends. *)

type import =
  | Import_func of int  (** a function of the type with this index *)
  | Import_memory of int  (** a memory with this minimum number of pages *)

type export =
  | Export_func of int  (** the function with this index *)
  | Export_memory  (** the memory 0 *)
  | Export_global of int  (** the global with this index *)

type memory = {
  minimum : int;  (** pages of 64 KiB *)
  maximum : int option;
  shared : bool;
  memory64 : bool;  (** the address type is 64 bits wide *)
}

type t = {
  types : func_type list;
  imports : (string * string * import) list;
      (** the module name, the field name, and what the import is *)
  functions : (int * instruction list) list;
      (** the index of the type, and the body without its final [end]. The index
          of a function counts the imported functions first. *)
  memory : memory option;
  globals : (value_type * bool * instruction list) list;
      (** the type, whether the global is mutable, and the constant expression
          that sets it, without its final [end] *)
  exports : (string * export) list;
  data : (int * string) list;  (** the address in memory 0, and the bytes *)
}

val encode : t -> string
(** [encode module_] is the binary format of [module_]. The encoding checks
    nothing: a module that breaks a rule of WebAssembly gives bytes that a
    runtime refuses. *)

(** {1 Runner adapters} *)

(** What [sinter_alloc] does. *)
type alloc =
  | Bump
      (** gives the next free address. The first is 1024, or the end of the data
          of the module when the data runs past 1024. *)
  | Zero  (** gives 0 *)
  | Address of int  (** gives this address, read as unsigned *)

(** What a call function ([sinter_recognise] or [sinter_bind]) does. *)
type body =
  | Respond of string
      (** gives the bytes, which a data segment of the module holds *)
  | Echo_request  (** gives the request back *)
  | Echo_report  (** gives the report back *)
  | Range of int * int
      (** gives this address and this length, each read as unsigned *)
  | Loop  (** runs until the fuel ends *)
  | Grow of int  (** grows the memory by this number of pages *)
  | Trap  (** runs [unreachable] *)
  | Custom of instruction list
      (** runs these instructions, which leave one [i64] on the stack *)

type adapter = {
  version : int;  (** what [sinter_interface] gives *)
  interface_body : instruction list option;
      (** the body of [sinter_interface] in place of the version *)
  alloc : alloc;
  recognise : body;
  bind : body;
  pages : int;  (** the minimum size of the memory, in pages *)
  memory_kind : memory -> memory;
      (** a change to the memory, such as [shared] *)
  extra_imports : (string * string * import) list;
      (** imports to add. An imported function takes the type of the first
          function of the module, whatever index the import names. *)
  missing : string list;  (** names of the five exports to leave out *)
  wrong_types : (string * func_type) list;
      (** a function export of these names, with this type in place of its own
      *)
  memory_as_global : bool;  (** [memory] names a global, not the memory *)
  extra_exports : bool;
      (** the module also exports the globals [__data_end] and [__heap_base] *)
}

val adapter : adapter
(** A valid adapter of version 1. Its memory is one page. [sinter_alloc] is
    {!Bump}. [sinter_recognise] gives [{"recognised":true}], and [sinter_bind]
    gives the report back. *)

val adapter_module : adapter -> string
(** [adapter_module spec] is the binary format of the adapter that [spec]
    describes. *)
