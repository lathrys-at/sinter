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
  | Stale_delivery
  | Delivery_without_change
  | Delivery_on_unmet_step
  | Missing_delivery
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
  | Renamed_step
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
    Stale_delivery;
    Delivery_without_change;
    Delivery_on_unmet_step;
    Missing_delivery;
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
    Renamed_step;
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
  | Stale_delivery -> "stale-delivery"
  | Delivery_without_change -> "delivery-without-change"
  | Delivery_on_unmet_step -> "delivery-on-unmet-step"
  | Missing_delivery -> "missing-delivery"
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
  | Renamed_step -> "renamed-step"
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
  | Stale_delivery -> (Some Block, Some Block, None)
  | Delivery_without_change -> (Some Warn, Some Warn, None)
  | Delivery_on_unmet_step -> (Some Block, Some Block, None)
  | Missing_delivery -> (None, Some Block, None)
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
  | Renamed_step -> (Some Block, Some Block, None)
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

let summary = function
  | Parse_error ->
      "Sinter cannot parse all of a file that it reads, so the check can miss \
       tags in that file."
  | Typo_tag ->
      "The tag word of a tag line is not in the vocabulary but is close to a \
       word of the vocabulary, so Sinter reads no tag on that line."
  | Ignored_tag ->
      "A tag line starts a paragraph that is not the first paragraph of its \
       section or list item, so Sinter reads no tag in that paragraph."
  | Invalid_target ->
      "The target of a tag does not have the form that the tag needs."
  | Duplicate ->
      "Two declarations, two plans, or two steps of one plan have names that \
       are equal or differ only in case."
  | Scope_outside_plan ->
      "The scope of a step covers files that the scope of its plan does not \
       cover."
  | Step_without_promises ->
      "A step of an open plan makes no promise, and the manifest requires a \
       promise in each step."
  | Stale_delivery ->
      "A delivery line in a commit message since the base does not count: its \
       form is wrong, it names no step of an open plan, or its hash does not \
       match the step."
  | Delivery_without_change ->
      "A delivery line in a commit message since the base counts for a step, \
       and the changes since the base change no file in the scope of that \
       step."
  | Delivery_on_unmet_step ->
      "A delivery line in a commit message since the base counts for a step of \
       an open plan, and some promises of the step are not met."
  | Missing_delivery ->
      "The changes since the base meet the promises of a step, and no delivery \
       line in a commit message since the base counts for the step."
  | Misplaced_plan ->
      "A @plan tag is not in the first tag block of a plan file."
  | Missing_plan_id ->
      "A @plan tag gives no plan id after the name of the plan."
  | Unpinned ->
      "A @satisfies, @verifies, @refines, or @supersedes tag gives no revision \
       of the item that it names, so Sinter cannot tell when that item \
       changes."
  | Dangling -> "A tag names an item that no file declares."
  | Renamed ->
      "A tag names an item that the changes since the base renamed, so the tag \
       no longer finds the item."
  | Suspect ->
      "The item that a tag names has a new revision since the revision that \
       the tag gives, so the text with the tag can be out of date."
  | Unbumped ->
      "The changes since the base alter the text of a requirement, a design, \
       or a decision, and they do not raise its revision."
  | Cycle ->
      "A chain of @supersedes and @refines tags leads from an item back to the \
       same item."
  | Code_drift ->
      "The code at a tagged place changed since the base, and the comment with \
       its tags did not, so the comment can be out of date."
  | Declined ->
      "The ledger holds a decline of a requirement, a design, a decision, or a \
       plan, and the item has not changed since the decline."
  | Unapproved_req ->
      "A @satisfies or @verifies tag names a requirement that has no approval."
  | Unapproved_design ->
      "A @satisfies or @verifies tag names a design that has no approval."
  | Awaiting_approval ->
      "A requirement, a design, or a decision is in force and has no approval \
       yet."
  | Unapproved_plan ->
      "A plan is in force, and the ledger holds no approval of its current \
       promises and scopes."
  | Retired ->
      "A @cites tag names an item that is no longer in force, for example an \
       item that a newer item supersedes."
  | Stale_ack ->
      "An @ack tag no longer applies: its hash does not match its block, or it \
       names nothing in its block that it can accept."
  | Wrong_source ->
      "A tag is in a place where its kind needs another source: a @verifies \
       tag outside a test, or a @refines or @supersedes tag outside a \
       declaration."
  | Never_ran ->
      "The test of a @verifies tag did not run, or was skipped, in the test \
       results of this tree."
  | Failed ->
      "The test of a @verifies tag failed in the test results of this tree."
  | Unexercised ->
      "The test of a @verifies tag passed, and it ran no line of the code that \
       satisfies the item that the tag names."
  | Unmeasured ->
      "The test of a @verifies tag passed, and the coverage data cannot show \
       whether this test ran the code that satisfies the item that the tag \
       names."
  | Ambiguous_result ->
      "One test result matches tests or groups in more than one file or under \
       more than one name, so Sinter cannot tell which test it belongs to."
  | Untraced ->
      "A requirement or a design in force has no @verifies tag or no \
       @satisfies tag that names it."
  | Unmet_promise ->
      "The active plan of the session, or its active step, promises a tag that \
       the tree does not hold yet."
  | Promise_out_of_scope ->
      "A promise of a step is met only by files outside the scope of the step."
  | Unverified_promise ->
      "A plan promises a requirement or a design, and it does not promise a \
       @verifies tag that names that item."
  | Promise_collision ->
      "A plan promises to declare a name that the base already declares, or \
       that a plan on another branch promises to declare."
  | Renamed_step ->
      "A step that is started in the base has no step of the same name in the \
       plan now."
  | Scope_overlap ->
      "Two steps of one plan have scopes that overlap and promises in common."
  | Waiting_on ->
      "A tag names an item that a plan on another branch promises to declare, \
       so the tag waits for that branch to merge."
  | Branch_overlap ->
      "The scope of a step overlaps the scope of a plan on another branch."
  | Unplanned_change ->
      "The changes since the base touch a file that no step of an open plan, \
       no rule, and no exempt path covers."
  | Unmet_rule ->
      "A rule asks for something of a subject, and the subject does not have \
       it."
  | Config_changed ->
      "The changes since the base alter an entry of the manifest, and that can \
       change what the check reports."
  | Merged_incomplete ->
      "A step of an open plan has some of its promises met and some not met, \
       so only a part of the step is in the tree."
  | Ledger_broken ->
      "The ledger of approvals and completed plans fails its verification."
  | Pack_mismatch ->
      "A fetched language pack in the cache does not match the hash that the \
       lock file gives for it."
