(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

val base : string
(** The version of the next planned release, as [MAJOR.MINOR.PATCH]. A build of
    a release takes its version from the package instead, and a build of a
    development checkout adds the description of the checkout to this value. *)
