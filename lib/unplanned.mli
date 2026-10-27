(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(** The finding class [unplanned-change]: each hunk of the diff between the base
    and the working tree that no step of an open plan, no rule, and no exempt
    path covers, and that is not a mechanical repair ({!Repair}). *)

val findings :
  ?same:(string -> bool) ->
  base:Facts.t ->
  manifest:string option ->
  Facts.t ->
  (string * Git.change) list ->
  Finding.t list
(** [findings ~same ~base ~manifest facts diff] is one finding of
    [unplanned-change] for each hunk of {!Git.hunks} of each change of [diff]
    that meets all these conditions, in the order of [diff] and then of the
    hunks:

    + The path of the change is not under a historical path of the manifest of
      [facts] ({!Manifest.is_historical}).
    + {!Facts.covering} [facts] gives no step for the path.
    + The path is not exempt, by {!Manifest.is_exempt} with the manifest of
      [facts]. A path is a plan file when it is the path of a plan of [facts] or
      of [base]. [manifest] is the path of the manifest relative to the root of
      the working tree, and [None] when the manifest is outside it.
    + The hunk is not a mechanical repair, by {!Repair.hunk} with
      {!Repair.fixes} [~same ~base facts], the document of the path in
      {!Facts.files} [base], and the document of the path in {!Facts.files}
      [facts].

    No rule covers a path: sinter reads no rule file.

    [base] is the facts of the base tree with the manifest of the working tree,
    and [diff] is as {!Git.diff} gives it. [same] and [base] are as
    {!Adjudicator.tombstones} takes them; [base] holds each file of [diff] whose
    content changes.

    The subject of a finding is the hunk, by the id [hunk:<path>:<line>-<eline>]
    with the lines of {!Git.hunk}. The place is the path and the span from the
    column 1 of [line] to the column [ecol] of [eline]: the file can be absent
    from the working tree, and the line can be past the end of the file. The
    detail is
    [no step of an open plan, no rule, and no exempt path covers <path>]. The
    finding has no fix, and it is not ackable. *)
