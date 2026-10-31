(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

module Ids = Set.Make (String)
module Names = Map.Make (String)

type declared = { slug : string; rev : int; xh : string }

type tombstone = {
  kind : string;
  was : string;
  place : (string * Markdown.span) option;
  declared : declared option;
}

let declaration_kinds = [ "req"; "design"; "decision" ]

let is_declaration (declaration : Facts.declaration) =
  List.mem declaration.kind declaration_kinds

let tombstones ?(same = fun _ -> false) ~base facts =
  let candidates = ref [] in
  Facts.iter_identities
    ~within:(fun path -> not (same path))
    base
    (fun identity -> candidates := identity :: !candidates);
  let candidates = List.rev !candidates in
  let wanted =
    List.fold_left
      (fun ids (identity : Facts.identity) -> Ids.add identity.id ids)
      Ids.empty candidates
  in
  let present = ref Ids.empty in
  Facts.iter_identities facts (fun identity ->
      if Ids.mem identity.id wanted then present := Ids.add identity.id !present);
  let declared =
    List.fold_left
      (fun found (declaration : Facts.declaration) ->
        let id = Facts.declaration_id declaration in
        if Ids.mem id wanted && not (Names.mem id found) then
          Names.add id
            {
              slug = declaration.slug;
              rev = declaration.rev;
              xh = declaration.extent.hash;
            }
            found
        else found)
      Names.empty (Facts.declarations base)
  in
  List.rev
    (snd
       (List.fold_left
          (fun (seen, found) (identity : Facts.identity) ->
            if Ids.mem identity.id !present || Ids.mem identity.id seen then
              (seen, found)
            else
              ( Ids.add identity.id seen,
                {
                  kind = identity.kind;
                  was = identity.id;
                  place = identity.place;
                  declared =
                    (if List.mem identity.kind declaration_kinds then
                       Names.find_opt identity.id declared
                     else None);
                }
                :: found ))
          (Ids.empty, []) candidates))

let in_place_order (a : Facts.declaration) (b : Facts.declaration) =
  compare (a.path, a.span.start.line) (b.path, b.span.start.line)

let by_slug ~same ~base facts slugs =
  Names.map (List.sort in_place_order)
  @@ List.fold_left
       (fun found (declaration : Facts.declaration) ->
         if is_declaration declaration && Ids.mem declaration.slug slugs then
           Names.update declaration.slug
             (fun earlier ->
               Some (declaration :: Option.value earlier ~default:[]))
             found
         else found)
       Names.empty
       (List.rev
          (Facts.declarations base
          @ List.filter
              (fun (declaration : Facts.declaration) -> same declaration.path)
              (Facts.declarations facts)))

let place (declaration : Facts.declaration) =
  { Finding.path = declaration.path; span = declaration.span }

let subject (declaration : Facts.declaration) =
  Finding.Fact
    { id = Facts.declaration_id declaration; ack_name = declaration.slug }

let unbumped ~base ~same facts =
  let candidates =
    List.filter
      (fun (declaration : Facts.declaration) ->
        is_declaration declaration && not (same declaration.path))
      (Facts.declarations facts)
  in
  let earlier =
    by_slug ~same ~base facts
      (Ids.of_list
         (List.map (fun (d : Facts.declaration) -> d.slug) candidates))
  in
  List.filter_map
    (fun (declaration : Facts.declaration) ->
      let held =
        Option.value (Names.find_opt declaration.slug earlier) ~default:[]
      in
      let same (old : Facts.declaration) =
        String.equal old.kind declaration.kind
        && String.equal old.extent.hash declaration.extent.hash
      in
      match
        List.fold_left
          (fun top (old : Facts.declaration) ->
            match top with
            | Some (kept : Facts.declaration) when kept.rev >= old.rev -> top
            | _ -> Some old)
          None held
      with
      | Some highest
        when (not (List.exists same held))
             && List.for_all
                  (fun (old : Facts.declaration) -> old.rev >= declaration.rev)
                  held ->
          let detail =
            match
              List.find_opt
                (fun (old : Facts.declaration) ->
                  String.equal old.kind declaration.kind)
                held
            with
            | Some _ ->
                Printf.sprintf
                  "the extent of %s differs from the base, and its revision is \
                   not above v%d"
                  (Facts.declaration_id declaration)
                  highest.rev
            | None ->
                Printf.sprintf
                  "the base declares %s v%d, so %s needs a higher revision for \
                   its change of kind"
                  (Facts.declaration_id highest)
                  highest.rev
                  (Facts.declaration_id declaration)
          in
          Some
            (Finding.make Finding_class.Unbumped (subject declaration)
               ~place:(place declaration) ~detail
               ~fix:(Fix.bump declaration.tag (highest.rev + 1))
               ?mark:
                 (let label =
                    Printf.sprintf "changed since the base, still v%d"
                      declaration.rev
                  in
                  match
                    Finding.part declaration.tag Tag_line.Revision label
                  with
                  | Some _ as marked -> marked
                  | None -> Finding.part declaration.tag Tag_line.Word label)
               ())
      | Some _ | None -> None)
    candidates

let rename ~base ~same ~tombstones facts =
  let gone =
    List.filter_map
      (fun (tombstone : tombstone) ->
        Option.map
          (fun declared -> (tombstone.kind, declared))
          tombstone.declared)
      tombstones
  in
  let fresh =
    lazy
      (let candidates =
         List.filter
           (fun (declaration : Facts.declaration) ->
             is_declaration declaration && not (same declaration.path))
           (Facts.declarations facts)
       in
       let held =
         by_slug ~same ~base facts
           (Ids.of_list
              (List.map (fun (d : Facts.declaration) -> d.slug) candidates))
       in
       List.filter
         (fun (declaration : Facts.declaration) ->
           not
             (List.exists
                (fun (old : Facts.declaration) ->
                  String.equal old.kind declaration.kind)
                (Option.value
                   (Names.find_opt declaration.slug held)
                   ~default:[])))
         candidates)
  in
  let successor slug =
    match
      List.filter
        (fun (_, (declared : declared)) -> String.equal declared.slug slug)
        gone
    with
    | [ (kind, declared) ] -> (
        match
          ( List.filter
              (fun (_, (other : declared)) -> String.equal other.xh declared.xh)
              gone,
            List.filter
              (fun (d : Facts.declaration) ->
                String.equal d.extent.hash declared.xh)
              (Lazy.force fresh) )
        with
        | [ _ ], [ (next : Facts.declaration) ] when String.equal next.kind kind
          ->
            Some (kind ^ ":" ^ slug, next)
        | _ -> None)
    | _ -> None
  in
  successor

let renamed ~base ~same ~tombstones facts =
  let successor = rename ~base ~same ~tombstones facts in
  List.filter_map
    (fun ((edge : Facts.edge), target) ->
      match target with
      | Facts.Unresolved { dangling = true } ->
          Option.map
            (fun (was, (next : Facts.declaration)) ->
              Finding.make Finding_class.Renamed
                (Finding.Fact
                   { id = Facts.edge_id edge; ack_name = edge.target_text })
                ~place:{ Finding.path = edge.path; span = edge.span }
                ~detail:
                  (Printf.sprintf
                     "the base declares %s, and %s has its extent now" was
                     (Facts.declaration_id next))
                ~fix:(Fix.rename edge.tag next.slug next.rev)
                ?mark:
                  (Finding.part edge.tag Tag_line.Target
                     "renamed since the base")
                ~related:
                  [
                    {
                      Finding.label = "declared here now";
                      place = Some (place next);
                    };
                  ]
                ())
            (successor edge.target_text)
      | Facts.Unresolved { dangling = false }
      | Facts.Declaration _ | Facts.External _ ->
          None)
    (Facts.edges facts)

module Keys = Set.Make (struct
  type t = string list

  let compare = List.compare String.compare
end)

let promise_key (promise : Facts.promise) = [ promise.word; promise.target ]

let promise_collisions ~base ~same facts =
  let candidates =
    List.concat_map
      (fun (plan : Facts.plan) ->
        if not (same plan.path) then
          List.concat_map
            (fun (step : Facts.step) ->
              List.filter_map
                (fun (promise : Facts.promise) ->
                  if List.mem promise.word declaration_kinds then
                    Some (plan, step, promise)
                  else None)
                step.promises)
            plan.steps
        else [])
      (Facts.plans facts)
  in
  let promised =
    List.fold_left
      (fun keys (plan : Facts.plan) ->
        List.fold_left
          (fun keys (step : Facts.step) ->
            List.fold_left
              (fun keys promise ->
                let key = promise_key promise in
                let keys = Keys.add (Facts.full_form plan :: key) keys in
                match plan.id with
                | None -> Keys.add ("" :: plan.slug :: plan.path :: key) keys
                | Some _ -> keys)
              keys step.promises)
          keys plan.steps)
      Keys.empty
      (Facts.plans base
      @ List.filter
          (fun (plan : Facts.plan) -> same plan.path)
          (Facts.plans facts))
  in
  let held (plan : Facts.plan) promise =
    let key = promise_key promise in
    Keys.mem (Facts.full_form plan :: key) promised
    || Keys.mem ("" :: plan.slug :: plan.path :: key) promised
  in
  let declared =
    by_slug ~same ~base facts
      (Ids.of_list
         (List.map
            (fun (_, _, (promise : Facts.promise)) -> promise.target)
            candidates))
  in
  List.filter_map
    (fun ((plan : Facts.plan), step, (promise : Facts.promise)) ->
      match Names.find_opt promise.target declared with
      | Some (first :: _) when not (held plan promise) ->
          let id = Facts.promise_id plan step promise in
          Some
            (Finding.make Finding_class.Promise_collision
               (Finding.Fact { id; ack_name = id })
               ~place:{ Finding.path = plan.path; span = promise.span }
               ~detail:
                 (Printf.sprintf "the base already declares %s"
                    (Facts.declaration_id first))
               ?mark:
                 (Finding.part promise.tag Tag_line.Target
                    "the base declares this slug")
               ())
      | Some _ | None -> None)
    candidates

let same_plan (old : Facts.plan) (plan : Facts.plan) =
  String.equal (Facts.full_form old) (Facts.full_form plan)
  || Option.is_none old.id
     && String.equal old.slug plan.slug
     && String.equal old.path plan.path

let base_step plans plan (step : Facts.step) =
  List.find_map
    (fun (old : Facts.plan) ->
      if same_plan old plan then
        List.find_opt
          (fun (other : Facts.step) -> String.equal other.slug step.slug)
          old.steps
      else None)
    plans

let adds_mark ~base_plans plan (step : Facts.step) =
  match Facts.mark step with
  | None -> false
  | Some (tag : Markdown.tag) -> (
      match base_step base_plans plan step with
      | None -> true
      | Some old -> (
          match Facts.mark old with
          | None -> true
          | Some (was : Markdown.tag) ->
              (not (Facts.delivered old)) && was.target <> tag.target))

let marks_without_change ~base ~same ~changed facts =
  let base_plans = Facts.plans base in
  let covering = lazy (Facts.covering facts) in
  List.concat_map
    (fun (plan : Facts.plan) ->
      if same plan.path then []
      else
        List.filter_map
          (fun (step : Facts.step) ->
            let id = Facts.step_id plan step in
            match Facts.mark step with
            | Some tag
              when adds_mark ~base_plans plan step
                   && not
                        (List.exists
                           (fun path ->
                             (not (String.equal path plan.path))
                             && List.mem id (Lazy.force covering path))
                           changed) ->
                Some
                  (Finding.make Finding_class.Mark_without_change
                     (Finding.Fact { id; ack_name = step.slug })
                     ~place:{ Finding.path = plan.path; span = tag.span }
                     ~detail:
                       (Printf.sprintf
                          "the diff adds the mark of %s, and it changes no \
                           file in the scope of the step"
                          id)
                     ?mark:(Finding.part tag Tag_line.Word "added here")
                     ())
            | Some _ | None -> None)
          plan.steps)
    (Facts.plans facts)

let met_in facts plan step =
  let standing = Facts.standing facts plan step in
  fun promise -> Option.is_some (standing promise).Facts.by

let met_in_base whole_base plan step (promise : Facts.promise) =
  Facts.met_within whole_base
    ~scope:(Facts.effective_scope plan step)
    ~word:promise.word ~target:promise.target

let unmarked_steps ~whole_base facts =
  let candidates =
    List.concat_map
      (fun (plan : Facts.plan) ->
        List.filter_map
          (fun (step : Facts.step) ->
            if
              step.promises <> []
              && Option.is_none (Facts.mark step)
              && List.for_all (met_in facts plan step) step.promises
            then Some (plan, step)
            else None)
          plan.steps)
      (Facts.plans facts)
  in
  List.filter_map
    (fun ((plan : Facts.plan), (step : Facts.step)) ->
      let met_before = met_in_base (Lazy.force whole_base) plan step in
      if List.for_all met_before step.promises then None
      else
        let id = Facts.step_id plan step in
        let fix =
          Option.map
            (fun document ->
              Fix.mark_line document ~block:step.block
                ~hash:(Facts.mark_hash step))
            (List.assoc_opt plan.path (Facts.files facts))
        in
        Some
          (Finding.make Finding_class.Unmarked_step
             (Finding.Fact { id; ack_name = step.slug })
             ~place:{ Finding.path = plan.path; span = step.span }
             ~detail:
               (Printf.sprintf
                  "the diff makes the promises of %s met, and the step has no \
                   mark"
                  id)
             ?fix ()))
    candidates

let renamed_steps ~base ~same ~whole_base facts =
  let plans = Facts.plans facts in
  List.concat_map
    (fun (old : Facts.plan) ->
      if same old.path then []
      else
        match List.find_opt (same_plan old) plans with
        | None -> []
        | Some (plan : Facts.plan) ->
            let lost =
              List.filter
                (fun (step : Facts.step) ->
                  not
                    (List.exists
                       (fun (other : Facts.step) ->
                         String.equal other.slug step.slug)
                       plan.steps))
                old.steps
            in
            let delivered (step : Facts.step) =
              Facts.delivered step
              || List.exists
                   (fun (promise : Facts.promise) ->
                     Facts.met_within (Lazy.force whole_base)
                       ~scope:(Facts.effective_scope old step)
                       ~word:promise.word ~target:promise.target)
                   step.promises
            in
            List.filter_map
              (fun (step : Facts.step) ->
                if delivered step then
                  let id = Facts.step_id old step in
                  Some
                    (Finding.make Finding_class.Renamed_step
                       (Finding.Fact { id; ack_name = step.slug })
                       ~place:{ Finding.path = plan.path; span = plan.span }
                       ~detail:
                         (Printf.sprintf
                            "the base delivers %s, and the plan has no step \
                             with the slug %s now"
                            id step.slug)
                       ())
                else None)
              lost)
    (Facts.plans base)

let renamed_to ?(same = fun _ -> false) ~base facts =
  let resolve = lazy (Facts.resolve facts)
  and successor =
    lazy (rename ~base ~same ~tombstones:(tombstones ~same ~base facts) facts)
  in
  fun target ->
    match Lazy.force resolve target with
    | Facts.Unresolved { dangling = true } ->
        Option.map snd (Lazy.force successor target)
    | Facts.Unresolved { dangling = false }
    | Facts.Declaration _ | Facts.External _ ->
        None

let historical facts (finding : Finding.t) =
  match finding.place with
  | Some place -> Manifest.is_historical (Facts.manifest facts) place.path
  | None -> false

let classes ?(same = fun _ -> false) ?(changed = []) ?whole_base
    ?(wanted = fun _ -> true) ~base facts findings =
  let whole_base = Option.value whole_base ~default:(lazy base) in
  let tombstones = tombstones ~same ~base facts in
  let renamed = renamed ~base ~same ~tombstones facts in
  let replaced =
    List.fold_left
      (fun ids (finding : Finding.t) ->
        Ids.add (Finding.subject_id finding.subject) ids)
      Ids.empty renamed
  in
  List.sort Finding.compare
    (List.filter
       (fun (finding : Finding.t) ->
         not
           (finding.finding_class = Finding_class.Dangling
           && Ids.mem (Finding.subject_id finding.subject) replaced))
       findings
    @ List.filter
        (fun finding -> not (historical facts finding))
        (unbumped ~base ~same facts @ renamed
        @ promise_collisions ~base ~same facts
        @ marks_without_change ~base ~same ~changed facts
        @ (if wanted Finding_class.Unmarked_step then
             unmarked_steps ~whole_base facts
           else [])
        @
        if wanted Finding_class.Renamed_step then
          renamed_steps ~base ~same ~whole_base facts
        else []))
