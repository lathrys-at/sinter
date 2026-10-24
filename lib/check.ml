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

let exit_code ~strict entries =
  if List.exists blocks entries || (strict && entries <> []) then
    Exit_code.findings
  else Exit_code.clean

let quoted text =
  if String.exists (fun c -> c = ' ' || c = '\t') text then
    let escape = function
      | ('"' | '\\') as c -> "\\" ^ String.make 1 c
      | c -> String.make 1 c
    in
    "\""
    ^ String.concat "" (List.map escape (List.of_seq (String.to_seq text)))
    ^ "\""
  else text

let text { finding; tier } =
  let place =
    match finding.place with
    | Some { path; span } ->
        Printf.sprintf "%s:%d:%d:" (Finding.escape path) span.start.line
          span.start.column
    | None -> "-:-:-:"
  in
  let words =
    [ place ]
    @ Option.to_list
        (Option.map (fun (_, tier) -> Finding_class.tier_name tier) tier)
    @ [
        Finding_class.name finding.finding_class;
        Finding.escape (quoted (Finding.subject_id finding.subject));
      ]
    @ Option.to_list finding.detail
  in
  String.concat " " words
  :: Option.to_list (Option.map (fun fix -> "  fix: " ^ fix) finding.fix)

let record { finding; tier } =
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
    ("mode", Jsonl.string "tree");
  ]
  @ optional "detail" finding.detail
  @ optional "fix" finding.fix @ place @ gate

type format = Text | Json
type report = { messages : string list; lines : string list; code : int }

let run ~env ~dir ~manifest ~base ~gate ~strict ~format ~tool =
  let* tree = Scan.load ~env ~dir ~manifest ~base in
  let entries =
    select tree.manifest gate
      (Findings.tree tree.manifest tree.documents ~not_text:tree.not_text)
  in
  let code = exit_code ~strict entries in
  match format with
  | Text ->
      Ok
        {
          messages = Scan.base_message tree.base :: tree.warnings;
          lines = List.concat_map text entries;
          code;
        }
  | Json ->
      let* index = Scan.index tree ~tool in
      Ok
        {
          messages = tree.warnings;
          lines = List.map Jsonl.to_string (index :: List.map record entries);
          code;
        }
