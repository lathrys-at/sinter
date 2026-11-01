(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(** Generated ledgers for the benchmark and the tests: the ref
    [refs/sinter/ledger] of a repository, with a given number of entries in
    chunks of {!Sinter_core.Ledger.chunk_size}, made by one [git fast-import].

    The same numbers give the same ledger, with the same object ids, on every
    run. *)

val entry : ?seq:int -> int -> string
(** [entry ?seq n] is the line of the [n]-th generated entry, from 0, without
    its line feed: an [approval] of the requirement [req:r<n>] at revision 1,
    with the [seq] [seq], [n + 1] by default, a fixed [by], [head], [branch],
    and [tool], and the [ts] of [n] seconds after [2026-01-01T00:00:00Z]. The
    line is canonical and holds its own id. *)

val chunks : string list -> (string * string) list
(** [chunks lines] is the files of a ledger tree that holds [lines] in their
    order: each run of {!Sinter_core.Ledger.chunk_size} lines, and the rest, is
    one chunk, at [entries/<hh>/<id>.jsonl] after the id of its first line. Each
    pair is the path and the content of a chunk, each line with its line feed.

    @raise Invalid_argument
      if a line holds no id of the form [e-] and 12 digits. *)

val write : Git_fixture.t -> entries:int -> per_commit:int -> unit
(** [write repo ~entries ~per_commit] makes the ref [refs/sinter/ledger] of
    [repo]: a first commit of an empty tree, and then one commit for each
    [per_commit] entries of [entry 0] to [entry (entries - 1)], the last commit
    with the rest. Each commit holds the chunks of all entries up to it.

    @raise Invalid_argument if [entries] is negative or [per_commit] below 1. *)
