(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

module Paths = Map.Make (String)
module Ids = Set.Make (String)

type moves = Gone | Runs of Git.hunk list
type t = moves Paths.t

let of_diff changes =
  List.fold_left
    (fun moves (path, change) ->
      let found =
        match change with
        | Git.Deleted _ | Git.Added Git.Binary | Git.Modified Git.Binary -> Gone
        | Git.Added (Git.Text runs) | Git.Modified (Git.Text runs) -> Runs runs
      in
      Paths.add path found moves)
    Paths.empty changes

let line moves ~path base_line =
  match Paths.find_opt path moves with
  | None -> Some base_line
  | Some Gone -> None
  | Some (Runs runs) ->
      let rec walk shift = function
        | [] -> Some (base_line + shift)
        | (run : Git.hunk) :: rest ->
            if run.old_line + run.removed <= base_line then
              walk (shift + run.added - run.removed) rest
            else if run.old_line <= base_line then None
            else walk shift rest
      in
      walk 0 runs

let subject moves = function
  | (Finding.Fact _ | Finding.File _) as subject -> Some subject
  | Finding.Error_node { path; position } ->
      Option.map
        (fun line ->
          Finding.Error_node { path; position = { position with line } })
        (line moves ~path position.line)
  | Finding.Line { path; line = base_line } ->
      Option.map
        (fun line -> Finding.Line { path; line })
        (line moves ~path base_line)
  | Finding.Tag { path; position } ->
      Option.map
        (fun line -> Finding.Tag { path; position = { position with line } })
        (line moves ~path position.line)

let subtract moves ~base findings =
  let ids =
    List.fold_left
      (fun ids (finding : Finding.t) ->
        match subject moves finding.subject with
        | Some moved -> Ids.add (Finding.id_of finding.finding_class moved) ids
        | None -> ids)
      Ids.empty base
  in
  List.filter (fun finding -> not (Ids.mem (Finding.id finding) ids)) findings
