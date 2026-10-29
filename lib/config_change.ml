(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

type value = String of string | Boolean of bool

type rule =
  | Neutral
  | Reads
  | Spares
  | Namespace
  | Demands
  | Toward of value
  | Strictest of value

type tier = { builtin : Finding_class.tier; written : Finding_class.tier }
type kind = Plain of rule | Tier of tier

type entry = {
  id : string;
  key : string list;
  value : value;
  kind : kind;
  span : Toml.span option;
}

module Ids = Map.Make (String)

type side = { entries : entry Ids.t; warn_only : bool }

let find name table =
  List.find_map
    (fun ((key : Toml.key), node) ->
      if String.equal key.name name then Some node else None)
    table

let as_table node =
  match Toml.value node with Toml.Table table -> Some table | _ -> None

let under names document =
  List.fold_left
    (fun found name ->
      Option.bind found (fun table -> Option.bind (find name table) as_table))
    (Some document) names
  |> Option.value ~default:[]

let one key kind node value =
  {
    id = Fact_id.setting key;
    key;
    value;
    kind;
    span =
      Some { Toml.start = Toml.key_start node; stop = (Toml.span node).stop };
  }

let text key rule ~valid node =
  match Toml.value node with
  | Toml.String value when valid value ->
      [ one key (Plain rule) node (String value) ]
  | _ -> []

let flag key rule node =
  match Toml.value node with
  | Toml.Boolean value -> [ one key (Plain rule) node (Boolean value) ]
  | _ -> []

let members key rule ~keep node =
  match Toml.value node with
  | Toml.Array nodes ->
      List.filter_map
        (fun member ->
          match Toml.value member with
          | Toml.String value when keep value ->
              Some
                {
                  id = Fact_id.member key value;
                  key;
                  value = String value;
                  kind = Plain rule;
                  span = Some (Toml.span member);
                }
          | _ -> None)
        nodes
  | _ -> []

let any _ = true
let one_of words value = List.mem value words

let at table name document read =
  match find name (under table document) with
  | Some node -> read node
  | None -> []

let named table read =
  List.concat_map
    (fun ((key : Toml.key), node) ->
      if Manifest.is_name key.name then read key node else [])
    table

let pack (key : Toml.key) node =
  let name = key.name in
  let path rest = "scan" :: "packs" :: name :: rest in
  let fields = Option.value (as_table node) ~default:[] in
  let files =
    match find "files" fields with
    | Some node -> members (path [ "files" ]) Reads ~keep:any node
    | None -> []
  in
  if String.equal name "markdown" then files
  else
    files
    @ (match find "version" fields with
      | Some node -> text (path [ "version" ]) Neutral ~valid:any node
      | None -> [])
    @
    match Option.bind (find "runners" fields) as_table with
    | Some runners ->
        named runners (fun (runner : Toml.key) node ->
            match as_table node with
            | Some _ ->
                let key = path [ "runners" ] in
                [
                  {
                    id = Fact_id.member key runner.name;
                    key;
                    value = String runner.name;
                    kind = Plain Neutral;
                    span = Some runner.at;
                  };
                ]
            | None -> [])
    | None -> []

let tiers document =
  List.concat_map
    (fun ((gate_key : Toml.key), node) ->
      match (Finding_class.gate_of_name gate_key.name, as_table node) with
      | Some gate, Some pairs ->
          List.concat_map
            (fun ((class_key : Toml.key), node) ->
              match (Finding_class.of_name class_key.name, Toml.value node) with
              | Some finding_class, Toml.String name
                when finding_class <> Finding_class.Config_changed -> (
                  match
                    ( Finding_class.builtin_tier finding_class gate,
                      Finding_class.tier_of_name name )
                  with
                  | Some builtin, Some written ->
                      let entry =
                        one
                          [ "check"; "tiers"; gate_key.name; class_key.name ]
                          (Tier { builtin; written })
                          node (String name)
                      in
                      [ { entry with id = Fact_id.gate gate finding_class } ]
                  | _ -> [])
              | _ -> [])
            pairs
      | _ -> [])
    (under [ "check"; "tiers" ] document)

let kinds kinds = List.map Manifest.kind_name kinds
let all_kinds = Manifest.[ Req; Design; Decision; Plan ]
let declaration = Manifest.approval_name Manifest.Declaration
let approval = Manifest.approval_name Manifest.Approval
let whole_run = Manifest.verifies_name Manifest.Whole_run
let each_test = Manifest.verifies_name Manifest.Each_test

let steps =
  List.map Manifest.step_name Manifest.[ Change; Step_approval; Promises ]

let change = Manifest.step_name Manifest.Change
let promises = Manifest.step_name Manifest.Promises

let read_entries ~plan_file ~location document =
  let exempt member =
    not
      (plan_file member
      || String.equal member location
      || String.equal member Manifest.lock_file)
  in
  List.concat
    [
      at [] "default-branch" document
        (text [ "default-branch" ] Neutral ~valid:any);
      named (under [ "scan"; "packs" ] document) pack;
      named
        (under [ "scan"; "namespaces" ] document)
        (fun key node ->
          text [ "scan"; "namespaces"; key.name ] Namespace ~valid:any node);
      at [ "paths" ] "exempt" document
        (members [ "paths"; "exempt" ] Spares ~keep:exempt);
      at [ "paths" ] "historical" document
        (members [ "paths"; "historical" ] Spares ~keep:(fun member ->
             not (String.equal member Manifest.builtin_historical)));
      List.concat_map
        (fun ((key : Toml.key), node) ->
          if List.mem key.name (kinds Manifest.[ Req; Design; Decision ]) then
            members [ "paths"; key.name ] Spares ~keep:any node
          else [])
        (under [ "paths" ] document);
      List.concat_map
        (fun ((key : Toml.key), node) ->
          if List.mem key.name (kinds all_kinds) then
            text [ "proof"; key.name ] (Toward (String approval))
              ~valid:(one_of [ declaration; approval ])
              node
          else [])
        (under [ "proof" ] document);
      at [ "proof" ] "agent-markers" document
        (members [ "proof"; "agent-markers" ] Demands ~keep:any);
      at [ "proof" ] "verifies" document
        (text [ "proof"; "verifies" ] (Toward (String each_test))
           ~valid:(one_of [ whole_run; each_test ]));
      at [ "proof" ] "step" document
        (text [ "proof"; "step" ] (Strictest (String promises))
           ~valid:(one_of steps));
      at [ "check" ] "warn-only" document
        (flag [ "check"; "warn-only" ] (Toward (Boolean false)));
      tiers document;
    ]

let defaults =
  [
    ([ "default-branch" ], String "main", Neutral);
    ([ "check"; "warn-only" ], Boolean false, Toward (Boolean false));
    ([ "proof"; "verifies" ], String whole_run, Toward (String each_test));
    ([ "proof"; "step" ], String change, Strictest (String promises));
  ]
  @ List.map
      (fun kind ->
        ( [ "proof"; Manifest.kind_name kind ],
          String declaration,
          Toward (String approval) ))
      all_kinds

let warn_only_id = Fact_id.setting [ "check"; "warn-only" ]

let side ~plan_file ~location document =
  let entries =
    List.fold_left
      (fun entries entry ->
        if Ids.mem entry.id entries then entries
        else Ids.add entry.id entry entries)
      Ids.empty
      (read_entries ~plan_file ~location document
      @ List.map
          (fun (key, value, rule) ->
            {
              id = Fact_id.setting key;
              key;
              value;
              kind = Plain rule;
              span = None;
            })
          defaults)
  in
  {
    entries;
    warn_only =
      (match Ids.find_opt warn_only_id entries with
      | Some { value = Boolean true; _ } -> true
      | _ -> false);
  }

let entries side =
  List.map (fun (id, entry) -> (id, entry.value)) (Ids.bindings side.entries)

type direction = Strengthens | Weakens | Changes

type form =
  | Changed of { old : value; now : value }
  | Added of value
  | Removed of value

type change = {
  id : string;
  key : string list;
  form : form;
  direction : direction;
  written : Toml.span option;
  was : Toml.span option;
  tombstone : bool;
}

let applies side { builtin; _ } = function
  | Some written -> written
  | None when side.warn_only && builtin = Finding_class.Block ->
      Finding_class.Warn
  | None -> builtin

let written_tier = function
  | Some { kind = Tier tier; _ } -> Some tier.written
  | Some { kind = Plain _; _ } | None -> None

let rank = function
  | Finding_class.Off -> 0
  | Finding_class.Warn -> 1
  | Finding_class.Block -> 2

let direction rule form =
  let grows = function Added _ -> true | Removed _ | Changed _ -> false in
  let member ~more = function
    | Added value | Removed value | Changed { old = value; _ } ->
        let plain =
          match value with
          | String glob -> not (String.starts_with ~prefix:"!" glob)
          | Boolean _ -> true
        in
        if more = plain then Strengthens else Weakens
  in
  let now = function Changed { now; _ } | Added now | Removed now -> now in
  match rule with
  | Neutral -> Changes
  | Reads -> member ~more:(grows form) form
  | Spares -> member ~more:(not (grows form)) form
  | Namespace -> (
      match form with
      | Added _ -> Weakens
      | Removed _ -> Strengthens
      | Changed _ -> Changes)
  | Demands -> if grows form then Strengthens else Weakens
  | Toward stricter -> if now form = stricter then Strengthens else Weakens
  | Strictest strictest -> (
      match form with
      | Changed { now; _ } when now = strictest -> Strengthens
      | Changed { old; _ } when old = strictest -> Weakens
      | Changed _ | Added _ | Removed _ -> Changes)

type pair = Gone of entry | Kept of entry option * entry

let changes ~base side =
  let pairs =
    Ids.fold
      (fun id now pairs ->
        Ids.add id (Kept (Ids.find_opt id base.entries, now)) pairs)
      side.entries
      (Ids.filter_map
         (fun id old ->
           if Ids.mem id side.entries then None else Some (Gone old))
         base.entries)
  in
  List.filter_map
    (fun (id, pair) ->
      let old, now, entry =
        match pair with
        | Gone old -> (Some old, None, old)
        | Kept (old, now) -> (old, Some now, now)
      in
      let value = Option.map (fun (entry : entry) -> entry.value) in
      if value old = value now then None
      else
        let form, direction =
          match (entry.kind, old, now) with
          | Tier tier, _, _ ->
              let before = applies base tier (written_tier old)
              and after = applies side tier (written_tier now) in
              ( Changed
                  {
                    old = String (Finding_class.tier_name before);
                    now = String (Finding_class.tier_name after);
                  },
                if rank after > rank before then Strengthens
                else if rank after < rank before then Weakens
                else Changes )
          | Plain rule, Some old, Some now ->
              let form = Changed { old = old.value; now = now.value } in
              (form, direction rule form)
          | Plain rule, None, Some now ->
              (Added now.value, direction rule (Added now.value))
          | Plain rule, _, None ->
              (Removed entry.value, direction rule (Removed entry.value))
        in
        Some
          {
            id;
            key = entry.key;
            form;
            direction;
            written = Option.bind now (fun (entry : entry) -> entry.span);
            was = Option.bind old (fun (entry : entry) -> entry.span);
            tombstone =
              (match (entry.kind, now) with
              | Plain _, None -> true
              | Tier _, _ | Plain _, Some _ -> false);
          })
    (Ids.bindings pairs)

let render = function
  | String text -> Toml.basic_string text
  | Boolean flag -> string_of_bool flag

let direction_name = function
  | Strengthens -> "strengthens"
  | Weakens -> "weakens"
  | Changes -> "changes"

let detail change =
  Printf.sprintf "%s: %s (%s)"
    (String.concat "." change.key)
    (match change.form with
    | Changed { old; now } -> render old ^ " -> " ^ render now
    | Added value -> "added " ^ render value
    | Removed value -> "removed " ^ render value)
    (direction_name change.direction)

let position (position : Toml.position) =
  { Markdown.line = position.line; column = position.column }

let place ~location ~hunks change =
  let span =
    match change.written with
    | Some span ->
        { Markdown.start = position span.start; stop = position span.stop }
    | None -> (
        let removes line (hunk : Git.hunk) =
          hunk.old_line <= line && line < hunk.old_line + hunk.removed
        in
        match
          Option.bind change.was (fun (span : Toml.span) ->
              List.find_opt (removes span.start.line) hunks)
        with
        | Some hunk ->
            {
              Markdown.start = { line = hunk.line; column = 1 };
              stop = { line = hunk.eline; column = hunk.ecol };
            }
        | None ->
            let first = { Markdown.line = 1; column = 1 } in
            { Markdown.start = first; stop = first })
  in
  { Finding.path = location; span }

let findings ~plan_file ~location ~hunks ~base document =
  let read = side ~plan_file ~location in
  let base, suffix =
    match base with
    | None -> (read [], "")
    | Some text -> (
        match Toml.parse text with
        | Ok table -> (read table, "")
        | Error _ -> (read [], "; the base manifest is not valid TOML"))
  in
  List.map
    (fun change ->
      let id =
        if change.tombstone then Fact_id.tombstone change.id else change.id
      in
      Finding.make Finding_class.Config_changed
        (Finding.Fact { id; ack_name = id })
        ~place:(place ~location ~hunks change)
        ~detail:(detail change ^ suffix)
        ())
    (changes ~base (read document))
