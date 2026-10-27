(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(** The comparison of the manifest of the working tree with the base manifest:
    the findings of the class [config-changed]. *)

(** {1 Comparison sets} *)

(** The value of an entry. *)
type value = String of string | Boolean of bool

type side
(** The comparison set of one manifest: one entry for each setting, with its id,
    its value, and its place in the text. *)

val side : plan_file:(string -> bool) -> location:string -> Toml.table -> side
(** [side ~plan_file ~location document] is the comparison set of the manifest
    whose TOML document is [document]. It holds:

    - one entry for each of [default-branch], [check.warn-only], and
      [evidence.test-coverage]: the value that [document] writes, else the
      default ["main"], [false], or ["optional"];
    - one entry for each other key of one value: [scan.packs.<name>.version],
      [scan.namespaces.<ns>], and [check.tiers.<gate>.<class>], whose id is
      [gate:<gate>/<class>] and whose value is the written tier;
    - one entry for each member of [scan.packs.<name>.files],
      [check.historical], [plan.exempt], [plan.locations.<kind>],
      [ledger.approval-required], and [ledger.agent-markers], and one entry for
      each table under [scan.packs.<name>.runners], whose value is the name of
      the runner. A member that occurs twice gives one entry, from its first
      place.

    A member that is also built in gives no entry. The built-in member of
    [check.historical] is {!Manifest.builtin_historical}. The built-in members
    of [plan.exempt] are each path for which [plan_file] is [true], [location],
    and {!Manifest.lock_file}.

    The function reads any document, and checks no glob, branch name, or id
    pattern. Every other key and value gives no entry:

    - a key that is not at a place of the layout of the manifest;
    - a value whose TOML type is not the type of its key, and a member of an
      array that is not a string;
    - the name of a pack, a namespace, or a runner for which {!Manifest.is_name}
      is [false];
    - the keys [version] and [runners] of the pack [markdown];
    - a pair of [check.tiers] whose gate is not a gate, whose class is not a
      built-in class, whose class takes no tier at the gate, or whose class is
      [config-changed];
    - a kind under [plan.locations] other than [req], [design], and [decision];
    - a value that is not one of the words of its key: a tier, a member of
      [ledger.approval-required], and the value of [evidence.test-coverage];
    - [sinter-spec], and each key under [scan.packs.<name>.runners.<runner>]. *)

val entries : side -> (string * value) list
(** [entries side] is the id and the value of each entry of [side], sorted by id
    in byte order. *)

(** {1 Changes} *)

(** What a change does to the checks of Sinter. *)
type direction =
  | Strengthens  (** Sinter checks more after the change *)
  | Weakens  (** Sinter checks less after the change *)
  | Changes  (** the change has no single direction *)

(** The values of the two sides of a change. *)
type form =
  | Changed of { old : value; now : value }
      (** both sides have a value: the base, then the working tree *)
  | Added of value  (** only the working tree has the entry *)
  | Removed of value  (** only the base has the entry *)

type change = private {
  id : string;  (** the id of the entry *)
  key : string list;
      (** the key path of the entry; for a member, the key path of its array *)
  form : form;
  direction : direction;
  written : Toml.span option;
      (** the position of the entry in the working manifest; [None] when the
          working manifest does not write it *)
  was : Toml.span option;
      (** the position of the entry in the base manifest; [None] when the base
          manifest does not write it *)
  tombstone : bool;
      (** [true] when the working tree has no setting fact or gate fact with the
          id: the entry is not a pair of [check.tiers], and only the base has it
      *)
}
(** One change between the base and the working tree. The position of a key of
    one value and of a pair of [check.tiers] runs from the first character of
    its key, as its line writes it, to the last character of its value. The
    position of a member is its string, its quotes included. The position of a
    runner table is the name of the runner in the first key that names the
    table. *)

val changes : base:side -> side -> change list
(** [changes ~base side] is one change for each id that is in one of [base] and
    [side] only, and for each id whose two values differ, sorted by id in byte
    order.

    A pair of [check.tiers] always has the form [Changed], with the tier that
    applies on each side ({!Manifest.tier}): the written tier, else [warn] when
    the [check.warn-only] of that side is [true] and the built-in tier is
    [block], else the built-in tier.

    The direction is [Changes] for [default-branch], a pack version, and a
    runner. For the other keys:

    - a member of [scan.packs.<name>.files]: a plain glob added, or a [!] glob
      removed, strengthens; a plain glob removed, or a [!] glob added, weakens;
    - a member of [check.historical], [plan.exempt], or [plan.locations.<kind>]:
      the reverse;
    - [scan.namespaces.<ns>]: removed strengthens, added weakens, and a changed
      pattern changes;
    - [check.warn-only]: [false] in the working tree strengthens, [true]
      weakens;
    - a pair of [check.tiers]: a tier that rises in the order [off], [warn],
      [block] strengthens, one that falls weakens, and one that stays changes;
    - a member of [ledger.approval-required] or [ledger.agent-markers]: added
      strengthens, removed weakens;
    - [evidence.test-coverage]: ["required"] in the working tree strengthens,
      ["optional"] weakens. *)

val detail : change -> string
(** [detail change] is the detail of the finding of [change]:
    [<key path>: <old> -> <new> (<direction>)] for the form [Changed], and
    [<key path>: added <new> (<direction>)] or
    [<key path>: removed <old> (<direction>)] otherwise. A string stands as
    {!Toml.basic_string} gives it, and a boolean as [true] or [false]. The
    direction is [strengthens], [weakens], or [changes]. *)

(** {1 Findings} *)

val findings :
  plan_file:(string -> bool) ->
  location:string ->
  hunks:Git.hunk list ->
  base:string option ->
  Toml.table ->
  Finding.t list
(** [findings ~plan_file ~location ~hunks ~base document] is one finding of
    [config-changed] for each change between the base manifest and the working
    manifest, whose document is [document], in the order of {!changes}.
    [location] is the path of the working manifest, relative to the repository
    root. [base] is the text of the file at [location] in the base tree, or
    [None] when the base tree holds no such file. [hunks] is the hunks of the
    diff of [location]. [plan_file] is as {!side} takes it, for both sides.

    A text of [base] that is not a TOML 1.1.0 document gives the comparison set
    of an empty document, and each detail then ends with
    [; the base manifest is not valid TOML].

    The subject of a finding is the fact with the id of the change; for a change
    whose [tombstone] is [true], it is [tombstone:<id>]. A finding sits at
    [location], at the position of the entry in the working manifest when the
    working manifest writes it. Otherwise it sits at the first hunk whose
    removed lines of the base hold the first line of the entry in the base
    manifest, from column 1 of the hunk's first line to its [ecol] on its last
    line; with no such hunk, at line 1, column 1, with no character.

    @raise Sinter_bridge.Error
      if [base] is 4 GiB or more, or if the bridge stops on an internal fault.
*)
