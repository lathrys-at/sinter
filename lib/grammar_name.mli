(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(** The name under which the bridge loads a grammar. *)

val of_wasm : string -> string option
(** [of_wasm wasm] is the name of the grammar in the wasm module [wasm], read
    from the export whose name starts with ["tree_sitter_"]. It is [None] when
    the module holds no such export, when the module is not one the reader can
    follow, and when the name holds a NUL byte. *)

val of_path : string -> string
(** [of_path path] is a grammar name from the name of a grammar file. It is the
    base name without its extension, with each hyphen replaced by an underscore
    and a leading ["tree_sitter_"] removed. The name of
    ["packs/tree-sitter-json.wasm"] is therefore ["json"]. A loader uses it for
    a module that {!of_wasm} cannot read. *)
