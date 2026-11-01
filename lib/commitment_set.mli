(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(** The commitment-set hash of a plan. *)

type step = {
  scope : string list;  (** the effective scope of the step *)
  promises : (string * string) list;
      (** the promises of the step: the tag word and the tag target of each, for
          example [("req", "auth-lockout")] *)
}
(** The promises of one step, with the scope that they share. *)

val bytes : scope:string list -> step list -> string
(** [bytes ~scope steps] is the canonical bytes that the commitment-set hash
    covers, for a plan whose plan scope is [scope] and whose steps are [steps]:
    one object in the canonical form of RFC 8785, with no line feed, with the
    keys [promises] and [scope]. [promises] holds one object for each promise of
    each step, with the keys [scope], the effective scope of the step, [target],
    and [word]. Each array of globs holds each glob once, in byte order. The
    promises are in the order of their word, then their target, then the
    canonical bytes of their scope, each in byte order. The order of [scope], of
    [steps], of the promises of a step, and of the globs of a step changes
    nothing, and nor does the step that holds a promise when two steps have one
    scope. Each scope of a step is sorted and printed once.

    @raise Invalid_argument if a glob, a word, or a target is not valid UTF-8.
*)

val hash : scope:string list -> step list -> string
(** [hash ~scope steps] is the commitment-set hash: the 64 lowercase hexadecimal
    digits of the SHA-256 of {!bytes}[ ~scope steps].

    @raise Invalid_argument if a glob, a word, or a target is not valid UTF-8.
    @raise Sinter_bridge.Error if the bridge stops on an internal fault. *)

val size : scope:string list -> step list -> int
(** [size ~scope steps] is the length of {!bytes}[ ~scope steps], computed
    without the bytes: its work grows with the bytes of the globs, the words,
    and the targets, and not with the length of {!bytes}.

    @raise Invalid_argument if a glob, a word, or a target is not valid UTF-8.
*)
