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
                  "the extent differs from the base, and the revision is not \
                   above v%d"
                  highest.rev
            | None ->
                Printf.sprintf
                  "the base declares %s v%d, and a change of kind needs a \
                   higher revision"
                  (Facts.declaration_id highest)
                  highest.rev
          in
          Some
            (Finding.make Finding_class.Unbumped (subject declaration)
               ~place:(place declaration) ~detail
               ~fix:
                 (Printf.sprintf "@%s %s v%d" declaration.kind declaration.slug
                    (highest.rev + 1))
               ())
      | Some _ | None -> None)
    candidates

let renamed ~base ~same ~tombstones facts =
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
                ~fix:
                  (Printf.sprintf "@%s %s%s" edge.word next.slug
                     (Option.fold ~none:""
                        ~some:(fun _ -> Printf.sprintf " v%d" next.rev)
                        edge.rev))
                ())
            (successor edge.target_text)
      | Facts.Unresolved { dangling = false }
      | Facts.Declaration _ | Facts.External _ ->
          None)
    (Facts.edges facts)

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
                    Some (plan, promise, Facts.promise_id plan step promise)
                  else None)
                step.promises)
            plan.steps
        else [])
      (Facts.plans facts)
  in
  let wanted = Ids.of_list (List.map (fun (_, _, id) -> id) candidates) in
  let promised = ref Ids.empty in
  List.iter
    (fun (plan : Facts.plan) ->
      List.iter
        (fun (step : Facts.step) ->
          List.iter
            (fun (promise : Facts.promise) ->
              let id = Facts.promise_id plan step promise in
              if Ids.mem id wanted then promised := Ids.add id !promised)
            step.promises)
        plan.steps)
    (Facts.plans base
    @ List.filter
        (fun (plan : Facts.plan) -> same plan.path)
        (Facts.plans facts));
  let declared =
    by_slug ~same ~base facts
      (Ids.of_list
         (List.map
            (fun (_, (promise : Facts.promise), _) -> promise.target)
            candidates))
  in
  List.filter_map
    (fun ((plan : Facts.plan), (promise : Facts.promise), id) ->
      match Names.find_opt promise.target declared with
      | Some (first :: _) when not (Ids.mem id !promised) ->
          Some
            (Finding.make Finding_class.Promise_collision
               (Finding.Fact { id; ack_name = id })
               ~place:{ Finding.path = plan.path; span = promise.span }
               ~detail:
                 (Printf.sprintf "the base already declares %s"
                    (Facts.declaration_id first))
               ())
      | Some _ | None -> None)
    candidates

let historical facts (finding : Finding.t) =
  match finding.place with
  | Some place -> Manifest.is_historical (Facts.manifest facts) place.path
  | None -> false

let classes ?(same = fun _ -> false) ~base facts findings =
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
        @ promise_collisions ~base ~same facts))
