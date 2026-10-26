(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(** The files of the built-in pack [markdown], embedded in the binary. *)

val grammar : string
(** The block grammar of tree-sitter-markdown, release v0.5.4: the bytes of its
    [.wasm] file. *)

val query : string
(** The query that captures the blocks of a markdown file: the text of a [.scm]
    file. *)
