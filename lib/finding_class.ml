(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

type gate = Turn | Merge | Target
type tier = Off | Warn | Block

let gates = [ Turn; Merge; Target ]

let gate_name = function
  | Turn -> "turn"
  | Merge -> "merge"
  | Target -> "target"

let gate_of_name name = List.find_opt (fun g -> gate_name g = name) gates
let tiers_in_order = [ Off; Warn; Block ]
let tier_name = function Off -> "off" | Warn -> "warn" | Block -> "block"

let tier_of_name name =
  List.find_opt (fun t -> tier_name t = name) tiers_in_order

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
  | Law_touched
  | Undischarged_plan
  | Ledger_broken
  | Pack_drift

let all =
  [
    Parse_error;
    Typo_tag;
    Bad_target;
    Duplicate;
    Bad_scope;
    Misplaced_plan;
    Unpinned;
    Dangling;
    Renamed;
    Suspect;
    Rev_owed;
    Cycle;
    Code_drift;
    Declined;
    Unratified_req;
    Unratified_design;
    Unstamped;
    Amendment;
    Disendorsed;
    Stale_ack;
    Orphan;
    Never_ran;
    Failed;
    Disconnected;
    Unattributed;
    Uncovered;
    Unmet;
    Promise_out_of_scope;
    Unverified_promise;
    Promise_collision;
    Scope_overlap;
    Blocked_on;
    Lease_overlap;
    Unmapped_work;
    Rule_owed;
    Law_touched;
    Undischarged_plan;
    Ledger_broken;
    Pack_drift;
  ]

let name = function
  | Parse_error -> "parse-error"
  | Typo_tag -> "typo-tag"
  | Bad_target -> "bad-target"
  | Duplicate -> "duplicate"
  | Bad_scope -> "bad-scope"
  | Misplaced_plan -> "misplaced-plan"
  | Unpinned -> "unpinned"
  | Dangling -> "dangling"
  | Renamed -> "renamed"
  | Suspect -> "suspect"
  | Rev_owed -> "rev-owed"
  | Cycle -> "cycle"
  | Code_drift -> "code-drift"
  | Declined -> "declined"
  | Unratified_req -> "unratified-req"
  | Unratified_design -> "unratified-design"
  | Unstamped -> "unstamped"
  | Amendment -> "amendment"
  | Disendorsed -> "disendorsed"
  | Stale_ack -> "stale-ack"
  | Orphan -> "orphan"
  | Never_ran -> "never-ran"
  | Failed -> "failed"
  | Disconnected -> "disconnected"
  | Unattributed -> "unattributed"
  | Uncovered -> "uncovered"
  | Unmet -> "unmet"
  | Promise_out_of_scope -> "promise-out-of-scope"
  | Unverified_promise -> "unverified-promise"
  | Promise_collision -> "promise-collision"
  | Scope_overlap -> "scope-overlap"
  | Blocked_on -> "blocked-on"
  | Lease_overlap -> "lease-overlap"
  | Unmapped_work -> "unmapped-work"
  | Rule_owed -> "rule-owed"
  | Law_touched -> "law-touched"
  | Undischarged_plan -> "undischarged-plan"
  | Ledger_broken -> "ledger-broken"
  | Pack_drift -> "pack-drift"

(* The tiers at the gates turn, merge, and target. *)
let tiers = function
  | Parse_error -> (Some Warn, Some Block, Some Block)
  | Typo_tag -> (Some Warn, Some Warn, Some Warn)
  | Bad_target -> (Some Block, Some Block, Some Block)
  | Duplicate -> (Some Block, Some Block, Some Block)
  | Bad_scope -> (Some Block, Some Block, None)
  | Misplaced_plan -> (Some Block, Some Block, Some Block)
  | Unpinned -> (Some Block, Some Block, Some Block)
  | Dangling -> (Some Block, Some Block, Some Block)
  | Renamed -> (Some Block, Some Block, Some Block)
  | Suspect -> (Some Block, Some Block, Some Block)
  | Rev_owed -> (Some Block, Some Block, Some Block)
  | Cycle -> (Some Block, Some Block, Some Block)
  | Code_drift -> (Some Warn, Some Warn, None)
  | Declined -> (Some Warn, Some Block, None)
  | Unratified_req -> (Some Block, Some Block, Some Block)
  | Unratified_design -> (Some Warn, Some Warn, Some Warn)
  | Unstamped -> (Some Off, Some Warn, Some Warn)
  | Amendment -> (Some Warn, Some Block, None)
  | Disendorsed -> (Some Warn, Some Block, Some Block)
  | Stale_ack -> (Some Block, Some Block, Some Block)
  | Orphan -> (Some Block, Some Block, Some Block)
  | Never_ran -> (Some Warn, Some Block, Some Block)
  | Failed -> (Some Block, Some Block, Some Block)
  | Disconnected -> (Some Warn, Some Block, Some Block)
  | Unattributed -> (Some Off, Some Warn, Some Warn)
  | Uncovered -> (Some Off, Some Warn, Some Warn)
  | Unmet -> (Some Off, Some Off, None)
  | Promise_out_of_scope -> (Some Warn, Some Warn, None)
  | Unverified_promise -> (Some Warn, Some Warn, None)
  | Promise_collision -> (Some Block, Some Block, None)
  | Scope_overlap -> (Some Warn, Some Warn, None)
  | Blocked_on -> (Some Off, Some Warn, None)
  | Lease_overlap -> (Some Warn, Some Warn, None)
  | Unmapped_work -> (Some Block, Some Block, None)
  | Rule_owed -> (Some Warn, Some Block, Some Block)
  | Law_touched -> (Some Warn, Some Warn, Some Warn)
  | Undischarged_plan -> (None, None, Some Block)
  | Ledger_broken -> (None, None, Some Block)
  | Pack_drift -> (None, None, None)

let of_name text = List.find_opt (fun c -> name c = text) all

let builtin_tier finding_class gate =
  let turn, merge, target = tiers finding_class in
  match gate with Turn -> turn | Merge -> merge | Target -> target
