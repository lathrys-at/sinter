(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

type t = {
  main : (string * string) list;
  work : (string * string) list;
  uncommitted : (string * string) list;
  counts : (string * int) list;
}

let per_file = 25

let words =
  [|
    "alpha";
    "beta";
    "gamma";
    "delta";
    "lock";
    "token";
    "cache";
    "index";
    "scan";
    "check";
    "plan";
    "store";
    "queue";
    "retry";
    "limit";
    "route";
    "parse";
    "emit";
    "read";
    "write";
    "span";
    "hash";
    "tree";
    "diff";
    "merge";
    "base";
    "ledger";
    "audit";
    "trace";
    "grant";
    "deny";
  |]

let between state low high = low + Random.State.int state (high - low + 1)
let below state bound = Random.State.int state bound
let chance state probability = Random.State.float state 1.0 < probability
let pick state items = items.(below state (Array.length items))

let phrase state count =
  String.concat " " (List.init count (fun _ -> pick state words))

let prose state lines =
  String.concat "\n"
    (List.init lines (fun _ -> phrase state (between state 8 12) ^ "."))

let title state = String.capitalize_ascii (phrase state (between state 2 5))

let section state ~heading tags ~lines =
  let heading = Printf.sprintf "## %s %s\n" (title state) heading in
  heading ^ String.concat "\n" tags ^ "\n" ^ prose state lines ^ "\n"

let requirement_files state ~requirements =
  List.init
    ((requirements + per_file - 1) / per_file)
    (fun file ->
      let first = file * per_file in
      let last = min (first + per_file) requirements - 1 in
      let sections =
        List.init
          (last - first + 1)
          (fun offset ->
            let index = first + offset in
            let refines =
              if index > 0 && chance state 0.1 then
                [ Printf.sprintf "@refines req-%d" (below state index) ]
              else []
            in
            section state ~heading:(string_of_int index)
              (Printf.sprintf "@req req-%d" index :: refines)
              ~lines:(between state 2 5))
      in
      ( Printf.sprintf "spec/reqs/reqs-%04d.md" file,
        String.concat "\n"
          (Printf.sprintf "# Requirements %d\n" file :: sections) ))

let design_files state ~designs ~requirements =
  List.init
    ((designs + per_file - 1) / per_file)
    (fun file ->
      let first = file * per_file in
      let last = min (first + per_file) designs - 1 in
      let sections =
        List.init
          (last - first + 1)
          (fun offset ->
            let index = first + offset in
            let satisfies =
              List.init (between state 1 2) (fun _ ->
                  let draw = Random.State.float state 1.0 in
                  if draw < 0.01 then
                    Printf.sprintf "@satisfies req-missing-%d" index
                  else if draw < 0.3 then
                    Printf.sprintf "@satisfies req-%d v1"
                      (below state requirements)
                  else
                    Printf.sprintf "@satisfies req-%d"
                      (below state requirements))
            in
            section state ~heading:(string_of_int index)
              (Printf.sprintf "@design design-%d" index :: satisfies)
              ~lines:(between state 2 5))
      in
      ( Printf.sprintf "docs/design/design-%04d.md" file,
        String.concat "\n" (Printf.sprintf "# Design %d\n" file :: sections) ))

let status index =
  match index mod 50 with
  | 7 -> Some "@deprecated"
  | 17 -> Some "@rejected"
  | 27 -> Some "@deferred"
  | _ -> None

let decision_files state ~decisions =
  List.init decisions (fun index ->
      let supersedes =
        if index >= 2 && (index mod 30 = 1 || index mod 30 = 2) then
          [ Printf.sprintf "@supersedes dec-%d v1" (index - 1) ]
        else []
      in
      let cites =
        List.filter_map
          (fun _ ->
            if index > 0 then
              Some (Printf.sprintf "@cites dec-%d" (below state index))
            else None)
          (List.init (between state 0 2) Fun.id)
      in
      let refs =
        if chance state 0.2 then
          [ Printf.sprintf "@cites gh/%d" (between state 1 5000) ]
        else []
      in
      let heading = Printf.sprintf "# %s %d\n" (title state) index in
      let tags =
        String.concat "\n"
          (Printf.sprintf "@decision dec-%d" index
           :: Option.to_list (status index)
          @ supersedes @ cites @ refs)
      in
      let summary = prose state 1 in
      let context = prose state 4 in
      let decision = prose state 4 in
      ( Printf.sprintf "docs/decisions/dec-%05d.md" index,
        heading ^ tags ^ "\n" ^ summary ^ "\n\n## Context\n\n" ^ context
        ^ "\n\n## Decision\n\n" ^ decision ^ "\n" ))

let note_files state ~declarations ~requirements =
  let sections = max 1 (declarations / 50) in
  List.init
    ((sections + per_file - 1) / per_file)
    (fun file ->
      let first = file * per_file in
      let parts =
        List.init per_file (fun offset ->
            section state
              ~heading:(string_of_int (first + offset))
              [ Printf.sprintf "@cites req-%d" (below state requirements) ]
              ~lines:3)
      in
      ( Printf.sprintf "docs/notes/notes-%04d.md" file,
        String.concat "\n" (Printf.sprintf "# Notes %d\n" first :: parts) ))

let reader engine =
  match Sinter_core.Markdown.create engine with
  | Ok reader -> reader
  | Error _ -> failwith "the markdown grammar does not load"

let citation_hashes reader text =
  match Sinter_core.Markdown.read reader text with
  | Error _ -> failwith "a generated file does not parse"
  | Ok (document : Sinter_core.Markdown.t) ->
      List.filter_map
        (fun (tag : Sinter_core.Markdown.tag) ->
          if String.equal tag.word "cites" then
            Some document.blocks.(tag.block).hash
          else None)
        (Array.to_list document.tags)

let other_digit = function '0' -> '1' | _ -> '0'

let rec chunks items =
  match items with
  | [] -> []
  | _ ->
      let rec take count found rest =
        match (count, rest) with
        | 0, _ | _, [] -> (List.rev found, rest)
        | _, item :: rest -> take (count - 1) (item :: found) rest
      in
      let chunk, rest = take per_file [] items in
      chunk :: chunks rest

let ack_files state ~declarations ~decisions =
  let retired =
    Array.of_list
      (List.filter
         (fun index -> Option.is_some (status index))
         (List.init decisions Fun.id))
  in
  if Array.length retired = 0 then []
  else
    let citations = max 1 (declarations / 20) in
    let sections =
      List.init citations (fun index ->
          let target = Printf.sprintf "dec-%d" (pick state retired) in
          let kind = below state 4 in
          ( kind,
            target,
            Printf.sprintf "## %s %d\n@cites %s\n" (title state) index target,
            prose state 2 ^ "\n" ))
    in
    let engine = Sinter_bridge.create () in
    Fun.protect
      ~finally:(fun () -> Sinter_bridge.close engine)
      (fun () ->
        let reader = reader engine in
        Fun.protect
          ~finally:(fun () -> Sinter_core.Markdown.close reader)
          (fun () ->
            List.mapi
              (fun file sections ->
                let text heads =
                  String.concat "\n"
                    (Printf.sprintf "# Acks %d\n" file
                    :: List.map2
                         (fun head (_, _, tags, prose) -> tags ^ head ^ prose)
                         heads sections)
                in
                let hashes =
                  citation_hashes reader
                    (text (List.map (fun _ -> "") sections))
                in
                let ack target hash =
                  Printf.sprintf "@ack retired %s %s\n" target hash
                in
                let heads =
                  List.map2
                    (fun (kind, target, _, _) hash ->
                      let matching = String.sub hash 0 8 in
                      let wrong =
                        String.make 1 (other_digit hash.[0])
                        ^ String.sub hash 1 7
                      in
                      match kind with
                      | 0 -> ack target matching
                      | 1 -> ack target wrong
                      | 2 -> ""
                      | _ -> ack target wrong ^ ack target matching)
                    sections hashes
                in
                (Printf.sprintf "docs/acks/acks-%04d.md" file, text heads))
              (chunks sections)))

let scopes =
  [| "spec/reqs/**"; "docs/design/**"; "docs/decisions/**"; "docs/**" |]

let plan_files state ~plans ~requirements ~decisions =
  List.init plans (fun plan ->
      let head =
        Printf.sprintf "# Plan %d\n@plan plan-%d\n@scope spec/**, docs/**\n%s\n"
          plan plan (prose state 2)
      in
      let steps =
        List.init 20 (fun step ->
            let scope = Printf.sprintf "@scope %s" (pick state scopes) in
            let promises =
              if step = 19 then []
              else
                List.init (between state 2 4) (fun _ ->
                    let draw = Random.State.float state 1.0 in
                    if draw < 0.4 then
                      Printf.sprintf "@req req-%d" (below state requirements)
                    else if draw < 0.7 then
                      Printf.sprintf "@decision dec-%d" (below state decisions)
                    else if draw < 0.9 then
                      Printf.sprintf "@satisfies req-%d"
                        (below state requirements)
                    else Printf.sprintf "@cites dec-%d" (below state decisions))
            in
            Printf.sprintf "## Step %d %d %s\n%s\n%s\n" plan step (title state)
              (String.concat "\n" (scope :: promises))
              (prose state 2))
      in
      ( Printf.sprintf ".plans/plan-%03d.md" plan,
        String.concat "\n" (head :: steps) ))

let manifest =
  "[scan]\npacks.markdown.files = [\"**/*.md\"]\nrefs.gh = \"[1-9][0-9]*\"\n"

let sample state items count =
  let items = Array.of_list items in
  let length = Array.length items in
  for index = 0 to count - 1 do
    let other = index + below state (length - index) in
    let kept = items.(index) in
    items.(index) <- items.(other);
    items.(other) <- kept
  done;
  Array.to_list (Array.sub items 0 count)

let by_path files = List.sort (fun (a, _) (b, _) -> String.compare a b) files

let make ~seed ~declarations =
  if declarations < 2 then
    invalid_arg
      (Printf.sprintf "Generated_tree.make: %d declarations, below 2"
         declarations);
  let state = Random.State.make [| seed |] in
  let requirements = declarations * 5 / 10 in
  let designs = declarations * 3 / 10 in
  let decisions = declarations - requirements - designs in
  let plans = max 1 (declarations / 1000) in
  let markdown =
    List.concat
      [
        requirement_files state ~requirements;
        design_files state ~designs ~requirements;
        decision_files state ~decisions;
        note_files state ~declarations ~requirements;
        ack_files state ~declarations ~decisions;
        plan_files state ~plans ~requirements ~decisions;
        [ ("README.md", "# Generated tree\n\n" ^ prose state 3 ^ "\n") ];
      ]
  in
  let paths = List.map fst (by_path markdown) in
  let content = Hashtbl.create (List.length markdown) in
  List.iter (fun (path, text) -> Hashtbl.replace content path text) markdown;
  let append paths ~lines =
    List.map
      (fun path ->
        let text =
          Hashtbl.find content path ^ "\n" ^ prose state lines ^ "\n"
        in
        Hashtbl.replace content path text;
        (path, text))
      paths
  in
  let count = List.length paths in
  let work = append (sample state paths (max 1 (count / 100))) ~lines:2 in
  let uncommitted =
    append (sample state paths (max 1 (count / 1000))) ~lines:1
  in
  {
    main = by_path (("sinter.toml", manifest) :: markdown);
    work = by_path work;
    uncommitted = by_path uncommitted;
    counts =
      [
        ("req", requirements);
        ("design", designs);
        ("decision", decisions);
        ("plan", plans);
      ];
  }

let main tree = tree.main
let work tree = tree.work
let uncommitted tree = tree.uncommitted
let count tree kind = Option.value (List.assoc_opt kind tree.counts) ~default:0

let files changes =
  List.map (fun (path, text) -> Git_fixture.File (path, text)) changes

let time = 1700000000.

let write tree dir =
  let repo = Git_fixture.init_in dir in
  let set_time files =
    List.iter
      (fun (path, _) ->
        Unix.utimes (Filename.concat (Git_fixture.root repo) path) time time)
      files
  in
  Git_fixture.import repo
    [
      Git_fixture.commit ~ref:"refs/heads/main" ~mark:1 ~message:"main"
        (files tree.main);
      Git_fixture.commit ~parents:[ 1 ] ~ref:"refs/heads/work" ~mark:2
        ~message:"work" (files tree.work);
    ];
  ignore (Git_fixture.git repo [ "symbolic-ref"; "HEAD"; "refs/heads/work" ]);
  Git_fixture.checkout repo;
  set_time tree.main;
  ignore (Git_fixture.git repo [ "update-index"; "-q"; "--really-refresh" ]);
  List.iter
    (fun (path, text) -> Git_fixture.write repo path text)
    tree.uncommitted;
  set_time tree.uncommitted;
  repo
