(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

type gate = Turn | Review | Merged
type tier = Off | Warn | Block

let gates = [ Turn; Review; Merged ]

let gate_name = function
  | Turn -> "turn"
  | Review -> "review"
  | Merged -> "merged"

let gate_of_name name = List.find_opt (fun g -> gate_name g = name) gates
let tiers_in_order = [ Off; Warn; Block ]
let tier_name = function Off -> "off" | Warn -> "warn" | Block -> "block"

let tier_of_name name =
  List.find_opt (fun t -> tier_name t = name) tiers_in_order

type t =
  | Parse_error
  | Typo_tag
  | Ignored_tag
  | Invalid_target
  | Duplicate
  | Scope_outside_plan
  | Step_without_promises
  | Stale_mark
  | Mark_on_unmet_step
  | Misplaced_plan
  | Missing_plan_id
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

let all =
  [
    Parse_error;
    Typo_tag;
    Ignored_tag;
    Invalid_target;
    Duplicate;
    Scope_outside_plan;
    Step_without_promises;
    Stale_mark;
    Mark_on_unmet_step;
    Misplaced_plan;
    Missing_plan_id;
    Unpinned;
    Dangling;
    Renamed;
    Suspect;
    Unbumped;
    Cycle;
    Code_drift;
    Declined;
    Unapproved_req;
    Unapproved_design;
    Awaiting_approval;
    Unapproved_plan;
    Retired;
    Stale_ack;
    Wrong_source;
    Never_ran;
    Failed;
    Unexercised;
    Unmeasured;
    Ambiguous_result;
    Untraced;
    Unmet_promise;
    Promise_out_of_scope;
    Unverified_promise;
    Promise_collision;
    Scope_overlap;
    Waiting_on;
    Branch_overlap;
    Unplanned_change;
    Unmet_rule;
    Config_changed;
    Merged_incomplete;
    Ledger_broken;
    Pack_mismatch;
  ]

let name = function
  | Parse_error -> "parse-error"
  | Typo_tag -> "typo-tag"
  | Ignored_tag -> "ignored-tag"
  | Invalid_target -> "invalid-target"
  | Duplicate -> "duplicate"
  | Scope_outside_plan -> "scope-outside-plan"
  | Step_without_promises -> "step-without-promises"
  | Stale_mark -> "stale-mark"
  | Mark_on_unmet_step -> "mark-on-unmet-step"
  | Misplaced_plan -> "misplaced-plan"
  | Missing_plan_id -> "missing-plan-id"
  | Unpinned -> "unpinned"
  | Dangling -> "dangling"
  | Renamed -> "renamed"
  | Suspect -> "suspect"
  | Unbumped -> "unbumped"
  | Cycle -> "cycle"
  | Code_drift -> "code-drift"
  | Declined -> "declined"
  | Unapproved_req -> "unapproved-req"
  | Unapproved_design -> "unapproved-design"
  | Awaiting_approval -> "awaiting-approval"
  | Unapproved_plan -> "unapproved-plan"
  | Retired -> "retired"
  | Stale_ack -> "stale-ack"
  | Wrong_source -> "wrong-source"
  | Never_ran -> "never-ran"
  | Failed -> "failed"
  | Unexercised -> "unexercised"
  | Unmeasured -> "unmeasured"
  | Ambiguous_result -> "ambiguous-result"
  | Untraced -> "untraced"
  | Unmet_promise -> "unmet-promise"
  | Promise_out_of_scope -> "promise-out-of-scope"
  | Unverified_promise -> "unverified-promise"
  | Promise_collision -> "promise-collision"
  | Scope_overlap -> "scope-overlap"
  | Waiting_on -> "waiting-on"
  | Branch_overlap -> "branch-overlap"
  | Unplanned_change -> "unplanned-change"
  | Unmet_rule -> "unmet-rule"
  | Config_changed -> "config-changed"
  | Merged_incomplete -> "merged-incomplete"
  | Ledger_broken -> "ledger-broken"
  | Pack_mismatch -> "pack-mismatch"

(* @cites incompleteness-at-turn *)
let tiers = function
  | Parse_error -> (Some Warn, Some Block, Some Block)
  | Typo_tag -> (Some Warn, Some Warn, Some Warn)
  | Ignored_tag -> (Some Warn, Some Warn, Some Warn)
  | Invalid_target -> (Some Block, Some Block, Some Block)
  | Duplicate -> (Some Block, Some Block, Some Block)
  | Scope_outside_plan -> (Some Block, Some Block, None)
  | Step_without_promises -> (Some Block, Some Block, Some Block)
  | Stale_mark -> (Some Block, Some Block, Some Block)
  | Mark_on_unmet_step -> (Some Block, Some Block, Some Block)
  | Misplaced_plan -> (Some Block, Some Block, Some Block)
  | Missing_plan_id -> (Some Block, Some Block, Some Block)
  | Unpinned -> (Some Block, Some Block, Some Block)
  | Dangling -> (Some Block, Some Block, Some Block)
  | Renamed -> (Some Block, Some Block, Some Block)
  | Suspect -> (Some Block, Some Block, Some Block)
  | Unbumped -> (Some Block, Some Block, Some Block)
  | Cycle -> (Some Block, Some Block, Some Block)
  | Code_drift -> (Some Warn, Some Warn, None)
  | Declined -> (Some Warn, Some Block, None)
  | Unapproved_req -> (Some Block, Some Block, Some Block)
  | Unapproved_design -> (Some Warn, Some Warn, Some Warn)
  | Awaiting_approval -> (None, Some Warn, Some Warn)
  | Unapproved_plan -> (Some Warn, Some Block, None)
  | Retired -> (Some Warn, Some Block, Some Block)
  | Stale_ack -> (Some Block, Some Block, Some Block)
  | Wrong_source -> (Some Block, Some Block, Some Block)
  | Never_ran -> (Some Warn, Some Block, Some Block)
  | Failed -> (Some Block, Some Block, Some Block)
  | Unexercised -> (Some Warn, Some Block, Some Block)
  | Unmeasured -> (Some Off, Some Warn, Some Warn)
  | Ambiguous_result -> (Some Warn, Some Block, Some Block)
  | Untraced -> (None, Some Warn, Some Warn)
  | Unmet_promise -> (None, Some Off, None)
  | Promise_out_of_scope -> (Some Warn, Some Warn, None)
  | Unverified_promise -> (Some Warn, Some Warn, None)
  | Promise_collision -> (Some Block, Some Block, None)
  | Scope_overlap -> (Some Warn, Some Warn, None)
  | Waiting_on -> (Some Off, Some Warn, None)
  | Branch_overlap -> (Some Warn, Some Warn, None)
  | Unplanned_change -> (Some Block, Some Block, None)
  | Unmet_rule -> (Some Warn, Some Block, Some Block)
  | Config_changed -> (Some Warn, Some Warn, Some Warn)
  | Merged_incomplete -> (None, Some Block, Some Block)
  | Ledger_broken -> (None, None, Some Block)
  | Pack_mismatch -> (None, None, None)

let of_name text = List.find_opt (fun c -> name c = text) all

let builtin_tier finding_class gate =
  let turn, review, merged = tiers finding_class in
  match gate with Turn -> turn | Review -> review | Merged -> merged
