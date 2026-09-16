(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

val base : string
(** The version of the next planned release, as [MAJOR.MINOR.PATCH]. A build of
    a release takes its version from the package instead, and a build of a
    development checkout adds the description of the checkout to this value. *)

val render : package:string option -> describe:string -> string
(** [render ~package ~describe] is the version to print, as one line without a
    line feed. The function reads nothing of its own: the caller gives it both
    values, and the same pair always gives the same answer.

    [package] is the version that the build carries, and [None] when it carries
    none. A build of an opam release carries one; a build that [dune build]
    makes does not. A value that does not begin with the letter [v] gets one in
    front of it, and a value that begins with [v] is given back as it stands.
    [Some ""] gives [""], because there is no first letter to read.

    [describe] is the description of the checkout, as
    [git describe --always --dirty] gives it. It is read only when [package] is
    [None]. A description that holds a full stop is the name of a tag and is
    given back as it stands. The description ["unknown"] says that the build
    read no checkout, and the answer is then ["v"], {!base}, and ["-dev"]. Every
    other description is a bare hash, and the answer is ["v"], {!base},
    ["-dev+"], and that hash.

    The function raises nothing, and it returns the empty string for [Some ""]
    alone. *)
