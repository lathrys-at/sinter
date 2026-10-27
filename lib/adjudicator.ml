(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

module Ids = Set.Make (String)
module Slugs = Map.Make (String)

type declared = { slug : string; rev : int; xh : string }

type tombstone = {
  kind : string;
  was : string;
  place : (string * Markdown.span) option;
  declared : declared option;
}

let declaration_kinds = [ "req"; "design"; "decision" ]

let by_id facts =
  List.fold_left
    (fun found (declaration : Facts.declaration) ->
      let id = Facts.declaration_id declaration in
      if Slugs.mem id found then found else Slugs.add id declaration found)
    Slugs.empty (Facts.declarations facts)

let tombstones ~base facts =
  let present =
    List.fold_left
      (fun ids (identity : Facts.identity) -> Ids.add identity.id ids)
      Ids.empty (Facts.identities facts)
  in
  let declarations = by_id base in
  List.rev
    (snd
       (List.fold_left
          (fun (seen, found) (identity : Facts.identity) ->
            if Ids.mem identity.id present || Ids.mem identity.id seen then
              (seen, found)
            else
              ( Ids.add identity.id seen,
                {
                  kind = identity.kind;
                  was = identity.id;
                  place = identity.place;
                  declared =
                    Option.map
                      (fun (d : Facts.declaration) ->
                        { slug = d.slug; rev = d.rev; xh = d.extent.hash })
                      (Slugs.find_opt identity.id declarations);
                }
                :: found ))
          (Ids.empty, []) (Facts.identities base)))

let first_by_slug facts =
  List.fold_left
    (fun found (declaration : Facts.declaration) ->
      if
        List.mem declaration.kind declaration_kinds
        && not (Slugs.mem declaration.slug found)
      then Slugs.add declaration.slug declaration found
      else found)
    Slugs.empty (Facts.declarations facts)

let place (declaration : Facts.declaration) =
  { Finding.path = declaration.path; span = declaration.span }

let subject (declaration : Facts.declaration) =
  Finding.Fact
    { id = Facts.declaration_id declaration; ack_name = declaration.slug }

let unbumped ~base facts =
  let earlier = first_by_slug base in
  List.filter_map
    (fun (declaration : Facts.declaration) ->
      match Slugs.find_opt declaration.slug earlier with
      | Some (old : Facts.declaration)
        when List.mem declaration.kind declaration_kinds
             && declaration.rev <= old.rev
             && not
                  (String.equal old.kind declaration.kind
                  && String.equal old.extent.hash declaration.extent.hash) ->
          let detail =
            if String.equal old.kind declaration.kind then
              Printf.sprintf
                "the extent differs from the base, and the revision is not \
                 above v%d"
                old.rev
            else
              Printf.sprintf
                "the base declares %s v%d, and a change of kind needs a higher \
                 revision"
                (Facts.declaration_id old) old.rev
          in
          Some
            (Finding.make Finding_class.Unbumped (subject declaration)
               ~place:(place declaration) ~detail
               ~fix:
                 (Printf.sprintf "@%s %s v%d" declaration.kind declaration.slug
                    (old.rev + 1))
               ())
      | Some _ | None -> None)
    (Facts.declarations facts)

let historical facts (finding : Finding.t) =
  match finding.place with
  | Some place -> Manifest.is_historical (Facts.manifest facts) place.path
  | None -> false

let classes ~base facts findings =
  List.sort Finding.compare
    (findings
    @ List.filter
        (fun finding -> not (historical facts finding))
        (unbumped ~base facts))
