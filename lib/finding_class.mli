(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(** The built-in finding classes, the gates, and the tier of each class at each
    gate. *)

(** A point where Sinter checks a repository. *)
type gate =
  | Turn  (** at the end of a turn of an agent *)
  | Merge  (** on a change before it merges into the target branch *)
  | Target  (** on the target branch, after a merge *)

(** How hard a finding class bites at one gate. *)
type tier =
  | Off  (** the check does not report the class *)
  | Warn  (** the check reports each finding, and the exit code stays *)
  | Block  (** the check reports each finding, and exits with code 1 *)

val gates : gate list
(** The three gates: [Turn], [Merge], and [Target], in this order. *)

val gate_name : gate -> string
(** [gate_name gate] is the name of [gate]: ["turn"], ["merge"], or ["target"].
*)

val gate_of_name : string -> gate option
(** [gate_of_name name] is the gate whose name is [name], or [None]. *)

val tier_name : tier -> string
(** [tier_name tier] is the name of [tier]: ["off"], ["warn"], or ["block"]. *)

val tier_of_name : string -> tier option
(** [tier_of_name name] is the tier whose name is [name], or [None]. *)

(** A built-in finding class. *)
type t =
  | Parse_error
  | Typo_tag
  | Bad_target
  | Duplicate
  | Bad_scope
  | Misplaced_plan
  | Unpinned
  | Dangling
  | Renamed
  | Suspect
  | Rev_owed
  | Cycle
  | Code_drift
  | Declined
  | Unratified_req
  | Unratified_design
  | Unstamped
  | Amendment
  | Disendorsed
  | Stale_ack
  | Orphan
  | Never_ran
  | Failed
  | Disconnected
  | Unattributed
  | Uncovered
  | Unmet
  | Promise_out_of_scope
  | Unverified_promise
  | Promise_collision
  | Scope_overlap
  | Blocked_on
  | Lease_overlap
  | Unmapped_work
  | Rule_owed
  | Config_changed
  | Undischarged_plan
  | Ledger_broken
  | Pack_drift

val all : t list
(** Every built-in finding class, each once. *)

val name : t -> string
(** [name finding_class] is the name of the class, in lower case with [-]
    between words, for example ["parse-error"]. *)

val of_name : string -> t option
(** [of_name name] is the built-in class whose name is [name], or [None]. Case
    matters. *)

val builtin_tier : t -> gate -> tier option
(** [builtin_tier finding_class gate] is the tier that the class has at the gate
    when nothing sets another. It is [None] when the class takes no tier at that
    gate. [Pack_drift] takes no tier at any gate. *)
