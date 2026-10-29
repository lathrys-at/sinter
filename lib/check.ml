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

type form = Full | Brief | Json

type report = {
  messages : string list;
  code : int;
  form : form;
  entries : entry list;
  root : string;
  mode : Mode.t;
  index : Jsonl.record option;
}

let messages report = report.messages
let code report = report.code
let tier_of entry = Option.map snd entry.tier

let write ?phases ppf report =
  Allocation.measure phases "output" (fun () ->
      (match report.form with
      | Full ->
          let source = Source.create ~root:report.root in
          List.iteri
            (fun index entry ->
              if index > 0 then Format.pp_force_newline ppf ();
              Render.full ppf source ~tier:(tier_of entry) entry.finding)
            report.entries
      | Brief ->
          List.iter
            (fun entry -> Render.brief ppf ~tier:(tier_of entry) entry.finding)
            report.entries
      | Json ->
          let line record =
            Format.pp_print_string ppf (Jsonl.to_string record);
            Format.pp_force_newline ppf ()
          in
          Option.iter line report.index;
          List.iter
            (fun entry -> line (record ~mode:report.mode entry))
            report.entries);
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
        (Adjudicator.classes ~same ~base facts
           (findings
           @ Unplanned.findings ~same ~base
               ~manifest:
                 (if Filename.is_relative tree.location then Some tree.location
                  else None)
               facts compared.diff))
        (List.sort Finding.compare (configuration tree compared facts)))

let run ?phases ~env ~dir ~manifest ~base ~mode ~gate ~strict ~form ~tool () =
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
  let report messages index =
    { messages; code; form; entries; root = Git.root tree.repo; mode; index }
  in
  match form with
  | Full | Brief ->
      Ok (report (Scan.base_message tree.base :: tree.warnings) None)
  | Json ->
      let* index =
        Allocation.measure phases "repository" (fun () ->
            Scan.index ~mode tree ~tool)
      in
      Ok (report tree.warnings (Some index))
