(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

let ( let* ) = Result.bind

let tier manifest gate (finding : Finding.t) =
  let applies = Manifest.tier manifest gate finding.finding_class in
  match (finding.finding_class, finding.subject, applies) with
  | Finding_class.Parse_error, Finding.Error_node _, Some Finding_class.Block ->
      Some Finding_class.Warn
  | _ -> applies

type entry = {
  finding : Finding.t;
  tier : (Finding_class.gate * Finding_class.tier) option;
}

let select manifest gate findings =
  match gate with
  | None -> List.map (fun finding -> { finding; tier = None }) findings
  | Some gate ->
      List.filter_map
        (fun finding ->
          match tier manifest gate finding with
          | Some ((Finding_class.Warn | Finding_class.Block) as tier) ->
              Some { finding; tier = Some (gate, tier) }
          | Some Finding_class.Off | None -> None)
        findings

let blocks entry =
  match entry.tier with Some (_, Finding_class.Block) -> true | _ -> false

let counts_under_strict entry =
  entry.finding.finding_class <> Finding_class.Config_changed

let exit_code ~strict entries =
  if
    List.exists blocks entries
    || (strict && List.exists counts_under_strict entries)
  then Exit_code.findings
  else Exit_code.clean

let record ~mode { finding; tier } =
  let optional name = function
    | None -> []
    | Some text -> [ (name, Jsonl.string text) ]
  in
  let place =
    match finding.place with
    | None -> []
    | Some { path; span } ->
        [
          ("path", Jsonl.string path);
          ("line", Jsonl.int span.start.line);
          ("col", Jsonl.int span.start.column);
          ("eline", Jsonl.int span.stop.line);
          ("ecol", Jsonl.int span.stop.column);
        ]
  in
  let mark =
    match finding.mark with
    | None -> []
    | Some { start; stop; label } ->
        [
          ("mcol", Jsonl.int start);
          ("mecol", Jsonl.int stop);
          ("label", Jsonl.string label);
        ]
  in
  let related =
    match finding.related with
    | [] -> []
    | related ->
        [
          ( "related",
            Jsonl.objects
              (List.map
                 (fun ({ label; place } : Finding.related) ->
                   ("label", Jsonl.String label)
                   ::
                   (match place with
                   | None -> []
                   | Some { path; span } ->
                       [
                         ("path", Jsonl.String path);
                         ("line", Jsonl.Int span.start.line);
                         ("col", Jsonl.Int span.start.column);
                         ("eline", Jsonl.Int span.stop.line);
                         ("ecol", Jsonl.Int span.stop.column);
                       ]))
                 related) );
        ]
  in
  let fix =
    match (finding.fix, finding.place) with
    | Some fix, Some { path; _ } ->
        [
          ("help", Jsonl.string (Fix.help fix));
          ( "edits",
            Jsonl.objects
              (List.concat
                 (List.mapi
                    (fun index edits ->
                      List.map
                        (fun ({ line; col; eline; ecol; text } : Fix.edit) ->
                          [
                            ("alt", Jsonl.Int (index + 1));
                            ("path", Jsonl.String path);
                            ("line", Jsonl.Int line);
                            ("col", Jsonl.Int col);
                            ("eline", Jsonl.Int eline);
                            ("ecol", Jsonl.Int ecol);
                            ("text", Jsonl.String text);
                          ])
                        edits)
                    (Fix.alternatives fix))) );
        ]
    | Some _, None | None, _ -> []
  in
  let gate =
    match tier with
    | None -> []
    | Some (gate, tier) ->
        [
          ("gate", Jsonl.string (Finding_class.gate_name gate));
          ("tier", Jsonl.string (Finding_class.tier_name tier));
        ]
  in
  [
    ("v", Jsonl.int 1);
    ("kind", Jsonl.string "finding");
    ("id", Jsonl.string (Finding.id finding));
    ("class", Jsonl.string (Finding_class.name finding.finding_class));
    ("subject", Jsonl.string (Finding.subject_id finding.subject));
    ("ack_subject", Jsonl.string (Finding.ack_subject finding.subject));
    ("ackable", Jsonl.bool finding.ackable);
    ("mode", Jsonl.string (Mode.name mode));
  ]
  @ optional "detail" finding.detail
  @ fix @ place @ mark @ related @ gate

type form =
  | Full
  | Brief
  | Json
  | Porcelain of { nul : bool; headers : Porcelain.header_lines }

type notice = Line of string | Warning of string | Note of string

module Names = Set.Make (String)

let plural count one many = if count = 1 then one else many

let summary ~documents entries =
  match entries with
  | [] ->
      Printf.sprintf "no findings in %d %s" documents
        (plural documents "file" "files")
  | _ :: _ ->
      let count = List.length entries in
      let files =
        Names.cardinal
          (Names.of_list
             (List.filter_map
                (fun entry ->
                  Option.map
                    (fun ({ path; _ } : Finding.place) -> path)
                    entry.finding.place)
                entries))
      in
      let tiers tier =
        List.length
          (List.filter
             (fun entry ->
               match entry.tier with
               | Some (_, found) -> found = tier
               | None -> false)
             entries)
      in
      let counted =
        List.filter_map
          (fun (tier, name) ->
            match tiers tier with
            | 0 -> None
            | found -> Some (Printf.sprintf "%d %s" found name))
          [ (Finding_class.Block, "block"); (Finding_class.Warn, "warn") ]
      in
      let fixes =
        List.length
          (List.filter (fun entry -> Option.is_some entry.finding.fix) entries)
      in
      String.concat ""
        ([
           Printf.sprintf "%d %s in %d %s" count
             (plural count "finding" "findings")
             files
             (plural files "file" "files");
         ]
        @ (match counted with
          | [] -> []
          | _ :: _ -> [ ": "; String.concat ", " counted ])
        @
        if fixes = 0 then []
        else
          [
            Printf.sprintf "; %d %s" fixes
              (plural fixes "has a fix" "have a fix");
          ])

type item = Single of entry | Folded of { first : entry; count : int }

let folds = function
  | Finding_class.Untraced | Finding_class.Unmet_promise
  | Finding_class.Awaiting_approval ->
      true
  | _ -> false

let group entry =
  match entry.finding.place with
  | Some { path; _ }
    when folds entry.finding.finding_class && not (blocks entry) ->
      Some (Finding_class.name entry.finding.finding_class, path)
  | Some _ | None -> None

let fold ~strict ~verbose entries =
  if strict || verbose then List.map (fun entry -> Single entry) entries
  else
    let sizes = Hashtbl.create 16 in
    List.iter
      (fun entry ->
        Option.iter
          (fun key ->
            Hashtbl.replace sizes key
              (1 + Option.value (Hashtbl.find_opt sizes key) ~default:0))
          (group entry))
      entries;
    let seen = Hashtbl.create 16 in
    List.filter_map
      (fun entry ->
        match group entry with
        | Some key -> (
            match Hashtbl.find_opt sizes key with
            | Some count when count >= 2 ->
                if Hashtbl.mem seen key then None
                else (
                  Hashtbl.add seen key ();
                  Some (Folded { first = entry; count }))
            | Some _ | None -> Some (Single entry))
        | None -> Some (Single entry))
      entries

let fold_note items =
  let lines, findings =
    List.fold_left
      (fun (lines, findings) -> function
        | Single _ -> (lines, findings)
        | Folded { count; _ } -> (lines + 1, findings + count))
      (0, 0) items
  in
  if lines = 0 then None
  else
    Some
      (Printf.sprintf
         "%d findings are folded into %d %s; use -v to list each one" findings
         lines
         (plural lines "line" "lines"))

type output =
  | Blocks of item list
  | Lines of item list
  | Records of Jsonl.record * entry list
  | Fields of { nul : bool; headers : string; entries : entry list }

type report = {
  notices : notice list;
  code : int;
  output : output;
  root : string;
  mode : Mode.t;
}

let messages report =
  List.map
    (function
      | Line line -> line
      | Warning warning -> "warning: " ^ warning
      | Note note -> "note: " ^ note)
    report.notices

let notices ppf report =
  List.iter
    (fun notice ->
      match notice with
      | Line line ->
          Fmt.string ppf line;
          Format.pp_force_newline ppf ()
      | Warning warning -> Render.warning ppf warning
      | Note note -> Render.note ppf note)
    report.notices;
  Format.pp_print_flush ppf ()

let code report = report.code
let tier_of entry = Option.map snd entry.tier

let write ?phases ppf report =
  Allocation.measure phases "output" (fun () ->
      (match report.output with
      | Blocks items ->
          let source = Source.create ~root:report.root in
          List.iteri
            (fun index item ->
              if index > 0 then Format.pp_force_newline ppf ();
              match item with
              | Single entry ->
                  Render.full ppf source ~tier:(tier_of entry) entry.finding
              | Folded { first; count } ->
                  Render.folded_full ppf ~tier:(tier_of first) first.finding
                    count)
            items
      | Lines items ->
          List.iter
            (function
              | Single entry ->
                  Render.brief ppf ~tier:(tier_of entry) entry.finding
              | Folded { first; count } ->
                  Render.folded_brief ppf ~tier:(tier_of first) first.finding
                    count)
            items
      | Records (index, entries) ->
          let line record =
            Format.pp_print_string ppf (Jsonl.to_string record);
            Format.pp_force_newline ppf ()
          in
          line index;
          List.iter (fun entry -> line (record ~mode:report.mode entry)) entries
      | Fields { nul; headers; entries } ->
          let buffer = Buffer.create 256 in
          let print () =
            Format.pp_print_string ppf (Buffer.contents buffer);
            Buffer.clear buffer
          in
          Format.pp_print_string ppf headers;
          List.iter
            (fun entry ->
              Porcelain.add_finding buffer ~nul ~tier:(tier_of entry)
                entry.finding;
              print ())
            entries);
      Format.pp_print_flush ppf ())

module Paths = Map.Make (String)

let configuration (tree : Scan.tree) (compared : Scan.compared) facts =
  let read base =
    let plan_files = Facts.plan_files facts in
    Config_change.findings
      ~plan_file:(fun path -> List.mem path plan_files)
      ~location:tree.location
      ~hunks:
        (match List.assoc_opt tree.location compared.diff with
        | Some change -> Git.hunks change
        | None -> [])
      ~base
      (Manifest.document tree.manifest)
  in
  match compared.base_manifest with
  | Scan.Outside | Scan.Unchanged -> []
  | Scan.Absent -> read None
  | Scan.Changed text -> read (Some text)

let compare_with_base ?phases ~mode (tree : Scan.tree)
    (compared : Scan.compared) facts findings =
  let held = Paths.of_list tree.documents
  and earlier = Paths.of_list compared.base_documents in
  let same path =
    match (Paths.find_opt path held, Paths.find_opt path earlier) with
    | Some document, Some other -> document == other
    | _ -> false
  in
  let base =
    match mode with
    | Mode.Diff ->
        Allocation.measure phases "base-facts" (fun () ->
            Facts.make tree.manifest compared.base_documents)
    | Mode.Tree ->
        Allocation.measure phases "findings" (fun () ->
            Facts.make tree.manifest
              (List.filter
                 (fun (path, _) -> not (same path))
                 compared.base_documents))
  in
  let findings =
    match mode with
    | Mode.Tree -> findings
    | Mode.Diff ->
        let base_findings =
          Allocation.measure phases "base-findings" (fun () ->
              Findings.of_facts base
                ~base:(Scan.base_commit tree.base)
                ~not_text:compared.base_not_text)
        in
        Allocation.measure phases "findings" (fun () ->
            Baseline.subtract
              (Baseline.of_diff compared.diff)
              ~base:base_findings findings)
  in
  Allocation.measure phases "findings" (fun () ->
      List.merge Finding.compare
        (Adjudicator.classes ~same
           ~changed:
             (List.filter_map
                (fun (path, change) ->
                  if Git.hunks change = [] then None else Some path)
                compared.diff)
           ~base facts
           (findings
           @ Unplanned.findings ~same ~base
               ~manifest:
                 (if Filename.is_relative tree.location then Some tree.location
                  else None)
               facts compared.diff))
        (List.sort Finding.compare (configuration tree compared facts)))

let run ?phases ~env ~dir ~manifest ~base ~mode ~gate ~strict ~form ~verbose
    ~quiet ~tool () =
  let* tree, compared =
    Scan.load_with_base ?phases ~env ~dir ~manifest ~base ()
  in
  let facts =
    Allocation.measure phases "facts" (fun () ->
        Facts.make tree.manifest tree.documents)
  in
  let findings =
    Allocation.measure phases "findings" (fun () ->
        Findings.of_facts facts
          ~base:(Scan.base_commit tree.base)
          ~not_text:tree.not_text)
  in
  let findings = compare_with_base ?phases ~mode tree compared facts findings in
  let entries =
    Allocation.measure phases "findings" (fun () ->
        select tree.manifest gate findings)
  in
  let code = exit_code ~strict entries in
  let report notices output =
    { notices; code; output; root = Git.root tree.repo; mode }
  in
  let warnings =
    List.map
      (fun warning -> Warning warning)
      (tree.warnings @ Option.to_list (Scan.ledger_warning tree facts))
  in
  let text output =
    let items = fold ~strict ~verbose entries in
    Ok
      (report
         ((if quiet then []
           else
             [ Line (summary ~documents:(List.length tree.documents) entries) ])
         @ warnings
         @ (if quiet then []
            else
              Option.to_list
                (Option.map (fun note -> Note note) (fold_note items)))
         @
         if verbose && not quiet then [ Note (Scan.base_note tree.base) ]
         else [])
         (output items))
  in
  match form with
  | Full -> text (fun items -> Blocks items)
  | Brief -> text (fun items -> Lines items)
  | Json ->
      let* index =
        Allocation.measure phases "repository" (fun () ->
            Scan.index ~mode tree ~tool)
      in
      Ok (report warnings (Records (index, entries)))
  | Porcelain { nul; headers } ->
      let* headers =
        match headers with
        | Porcelain.No_headers -> Ok ""
        | Porcelain.Headers named ->
            Allocation.measure phases "repository" (fun () ->
                let value = function
                  | Porcelain.Base -> Ok (Scan.base_commit tree.base)
                  | Porcelain.Ledger ->
                      Result.map
                        (Option.value ~default:"none")
                        (Scan.ledger_commit tree)
                  | Porcelain.Gate ->
                      Ok
                        (Option.fold ~none:"none" ~some:Finding_class.gate_name
                           gate)
                  | Porcelain.Mode -> Ok (Mode.name mode)
                  | Porcelain.Tool -> Ok tool
                in
                let buffer = Buffer.create 128 in
                Porcelain.add_header buffer ~nul "porcelain"
                  (Int.to_string Porcelain.version);
                let* () =
                  List.fold_left
                    (fun result header ->
                      let* () = result in
                      if List.mem header named then
                        let* found = value header in
                        Ok
                          (Porcelain.add_header buffer ~nul
                             (Porcelain.header_name header)
                             found)
                      else Ok ())
                    (Ok ()) Porcelain.headers
                in
                Ok (Buffer.contents buffer))
      in
      Ok (report warnings (Fields { nul; headers; entries }))
