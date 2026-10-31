(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

type t =
  | Word of { tag : Markdown.tag; word : string }
  | Pin of { tag : Markdown.tag; rev : int }
  | Bump of { tag : Markdown.tag; rev : int }
  | Spelling of { tag : Markdown.tag; target : string }
  | Rename of { tag : Markdown.tag; target : string; rev : int }
  | Successors of {
      tag : Markdown.tag;
      first : string * int;
      others : (string * int) list;
    }
  | Plan_id of { tag : Markdown.tag; id : Plan_target.id }
  | Ack of { last : Markdown.tag; block : Markdown.block; target : string }
  | Mark_hash of { tag : Markdown.tag; hash : string }

let fail reason = invalid_arg ("Fix: " ^ reason)

let targeted (tag : Markdown.tag) =
  if Option.is_none tag.target then fail "the tag has no target"

let word tag word = Word { tag; word }

let pin (tag : Markdown.tag) rev =
  targeted tag;
  if tag.rev = Some rev then fail "the tag has the revision already";
  Pin { tag; rev }

let bump (tag : Markdown.tag) rev =
  targeted tag;
  if rev <= Option.value tag.rev ~default:1 then
    fail "the revision is not above the revision of the tag";
  Bump { tag; rev }

let spelling tag target =
  targeted tag;
  Spelling { tag; target }

let rename tag target rev =
  targeted tag;
  Rename { tag; target; rev }

let successors tag first others =
  targeted tag;
  Successors { tag; first; others }

let plan_id tag id =
  targeted tag;
  Plan_id { tag; id }

let mark_hash tag hash =
  targeted tag;
  Mark_hash { tag; hash }

let ack (document : Markdown.t) ~block ~target =
  let block = document.blocks.(block) in
  let last = List.nth block.tags (List.length block.tags - 1) in
  Ack { last = document.tags.(last); block; target }

type edit = { line : int; col : int; eline : int; ecol : int; text : string }

let columns (tag : Markdown.tag) part =
  Option.value
    (Markdown.columns tag part)
    ~default:
      ((0, 0)
      [@mutaml.skip
        "every function that makes a fix refuses a tag with no target, and a \
         tag with a revision has its columns, so the columns are never None"])

let target (tag : Markdown.tag) = Option.value tag.target ~default:""

let replace (tag : Markdown.tag) part text =
  let col, ecol = columns tag part in
  let line = tag.span.start.line in
  { line; col; eline = line; ecol; text }

let revision (tag : Markdown.tag) rev =
  match tag.rev with
  | Some _ -> replace tag Tag_line.Revision (Printf.sprintf "v%d" rev)
  | None ->
      let _, ecol = columns tag Tag_line.Target in
      let line = tag.span.start.line in
      { line; col = ecol; eline = line; ecol; text = Printf.sprintf " v%d" rev }

let retarget (tag : Markdown.tag) (slug, rev) =
  replace tag Tag_line.Target slug
  ::
  (match tag.rev with
  | Some old when old <> rev ->
      [ replace tag Tag_line.Revision (Printf.sprintf "v%d" rev) ]
  | Some _ | None -> [])

let ack_line target (block : Markdown.block) =
  Printf.sprintf "@ack retired %s %s" target (String.sub block.hash 0 8)

let alternatives = function
  | Word { tag; word } -> [ [ replace tag Tag_line.Word ("@" ^ word) ] ]
  | Pin { tag; rev } | Bump { tag; rev } -> [ [ revision tag rev ] ]
  | Spelling { tag; target } | Mark_hash { tag; hash = target } ->
      [ [ replace tag Tag_line.Target target ] ]
  | Plan_id { tag; id } ->
      let _, ecol = columns tag Tag_line.Target in
      let line = tag.span.start.line in
      [
        [
          { line; col = ecol; eline = line; ecol; text = "@" ^ (id :> string) };
        ];
      ]
  | Rename { tag; target; rev } -> [ retarget tag (target, rev) ]
  | Successors { tag; first; others } ->
      List.map (retarget tag) (first :: others)
  | Ack { last; block; target } ->
      let stop = last.span.stop in
      [
        [
          {
            line = stop.line;
            col = stop.column;
            eline = stop.line;
            ecol = stop.column;
            text = block.new_line ^ ack_line target block;
          };
        ];
      ]

let help = function
  | Word _ -> "replace the tag word with the nearest tag word that Sinter knows"
  | Pin { tag = { Markdown.rev = None; _ }; _ } ->
      "pin the citation to the revision of the declaration"
  | Pin { tag = { Markdown.rev = Some _; _ }; _ } ->
      "check that the citation still holds, then pin it to the current revision"
  | Bump _ -> "raise the revision above every revision in the base"
  | Spelling _ -> "write the slug as the declaration spells it"
  | Plan_id _ -> "give the plan an id after its slug"
  | Rename _ -> "cite the declaration by its new slug"
  | Successors { others = []; _ } ->
      "cite the successor in place of the retired item"
  | Successors { others = _ :: _; _ } ->
      "cite one of the successors in place of the retired item"
  | Ack _ -> "if the citation still holds, accept the finding with an @ack line"
  | Mark_hash _ ->
      "check that the step is still delivered, then write its current hash"

let head (tag : Markdown.tag) target rev =
  Printf.sprintf "@%s %s%s" tag.word target
    (Option.fold ~none:"" ~some:(Printf.sprintf " v%d") rev)

let text = function
  | Word { word; _ } -> "@" ^ word
  | Pin { tag; rev } | Bump { tag; rev } -> head tag (target tag) (Some rev)
  | Spelling { tag; target } -> head tag target tag.rev
  | Plan_id { tag; id } -> head tag (target tag ^ "@" ^ (id :> string)) tag.rev
  | Rename { tag; target; rev } ->
      head tag target (Option.map (fun _ -> rev) tag.rev)
  | Successors { tag; first; others } ->
      String.concat " or "
        (List.map
           (fun (slug, rev) ->
             head tag slug (Option.map (fun _ -> rev) tag.rev))
           (first :: others))
  | Ack { block; target; _ } -> ack_line target block
  | Mark_hash { tag; hash } -> head tag hash None
