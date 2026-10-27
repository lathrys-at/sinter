(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(** The built-in finding classes, the gates, and the tier of each class at each
    gate. *)

(** A point where Sinter checks a repository. *)
type gate =
  | Turn  (** at the end of a turn of an agent *)
  | Review  (** on a change before it merges into the default branch *)
  | Merged  (** on the default branch, after a merge *)

(** How hard a finding class bites at one gate. *)
type tier =
  | Off  (** the check does not report the class *)
  | Warn  (** the check reports each finding, and the exit code stays *)
  | Block  (** the check reports each finding, and exits with code 1 *)

val gates : gate list
(** The three gates: [Turn], [Review], and [Merged], in this order. *)

val gate_name : gate -> string
(** [gate_name gate] is the name of [gate]: ["turn"], ["review"], or ["merged"].
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
  | Ignored_tag
  | Invalid_target
  | Duplicate
  | Scope_outside_plan
  | Misplaced_plan
  | Unpinned
  | Dangling
  | Renamed
  | Suspect
  | Unbumped
  | Cycle
  | Code_drift
  | Declined
  | Unapproved_req
  | Unapproved_design
  | Awaiting_approval
  | Unapproved_plan
  | Retired
  | Stale_ack
  | Wrong_source
  | Never_ran
  | Failed
  | Unexercised
  | Unmeasured
  | Ambiguous_result
  | Untraced
  | Unmet_promise
  | Promise_out_of_scope
  | Unverified_promise
  | Promise_collision
  | Scope_overlap
  | Waiting_on
  | Branch_overlap
  | Unplanned_change
  | Unmet_rule
  | Config_changed
  | Merged_incomplete
  | Ledger_broken
  | Pack_mismatch

val all : t list
(** Every built-in finding class, each once, in the order in which [t] declares
    them. [compare] on [t] follows this order. *)

val name : t -> string
(** [name finding_class] is the name of the class, in lower case with [-]
    between words, for example ["parse-error"]. *)

val of_name : string -> t option
(** [of_name name] is the built-in class whose name is [name], or [None]. Case
    matters. *)

val builtin_tier : t -> gate -> tier option
(** [builtin_tier finding_class gate] is the tier that the class has at the gate
    when nothing sets another. It is [None] when the class takes no tier at that
    gate. [Pack_mismatch] takes no tier at any gate. *)
