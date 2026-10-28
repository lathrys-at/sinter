(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

type mark = {
  start : int;
  width : int;
  label : string option;
  sign : char;
  style : Style.element;
}

type row = { number : int; text : string; marks : mark list; continues : bool }

let rec trimmed_length text length =
  if length > 0 && text.[length - 1] = ' ' then trimmed_length text (length - 1)
  else length

let trim text =
  let length = trimmed_length text (String.length text) in
  if length = String.length text then text else String.sub text 0 length

let shown text = trim (Display.clean text)
let top_number rows = List.fold_left (fun top row -> max top row.number) 0 rows
let rec digits number = if number < 10 then 1 else 1 + digits (number / 10)
let newline ppf = Format.pp_force_newline ppf ()
let spaces ppf count = if count > 0 then Fmt.string ppf (String.make count ' ')

let empty_gutter ppf width =
  spaces ppf (width + 1);
  Style.string Style.Frame ppf "|";
  newline ppf

let source_row ppf width { number; text; _ } =
  Style.string Style.Frame ppf (Printf.sprintf "%*d |" width number);
  if text <> "" then (
    Fmt.string ppf " ";
    Fmt.string ppf text);
  newline ppf

let mark_row ppf width mark =
  spaces ppf (width + 1);
  Style.string Style.Frame ppf "|";
  spaces ppf (mark.start + 1);
  Style.string mark.style ppf (String.make mark.width mark.sign);
  Option.iter
    (fun label ->
      if label <> "" then (
        Fmt.string ppf " ";
        Style.string mark.style ppf label))
    mark.label;
  newline ppf

let snippet ppf width rows =
  match rows with
  | [] -> ()
  | _ :: _ ->
      empty_gutter ppf width;
      let rec print = function
        | [] -> ()
        | row :: rest ->
            source_row ppf width row;
            List.iter (mark_row ppf width) row.marks;
            (match rest with
            | next :: _ when next.number > row.number + 1 ->
                Fmt.string ppf "...";
                newline ppf
            | [] when row.continues ->
                Fmt.string ppf "...";
                newline ppf
            | _ -> ());
            print rest
      in
      print rows;
      empty_gutter ppf width

let marked raw ~start ~stop =
  let last = Display.length raw + 1 in
  if start < 1 || start > last || stop > last then None
  else
    let from = Display.column_width raw start in
    Some (from, max 1 (Display.column_width raw stop - from))

type item = { at : int; raw : string; mark : mark; continues : bool }

let item source path (span : Markdown.span) ~columns ~label ~sign ~style =
  Option.bind (Source.line source path span.start.line) (fun raw ->
      let continues = span.stop.line > span.start.line in
      let start, stop =
        match columns with
        | Some columns -> columns
        | None ->
            ( span.start.column,
              if continues then Display.length raw + 1 else span.stop.column )
      in
      Option.map
        (fun (start, width) ->
          {
            at = span.start.line;
            raw;
            mark = { start; width; label; sign; style };
            continues;
          })
        (marked raw ~start ~stop))

let rec rows = function
  | [] -> []
  | first :: rest ->
      let same, others = List.partition (fun item -> item.at = first.at) rest in
      {
        number = first.at;
        text = shown first.raw;
        marks = first.mark :: List.map (fun item -> item.mark) same;
        continues = List.exists (fun item -> item.continues) (first :: same);
      }
      :: rows others

let sorted_rows items =
  rows (List.stable_sort (fun a b -> Int.compare a.at b.at) items)

let primary source ~tier (finding : Finding.t) =
  Option.bind finding.place (fun { Finding.path; span } ->
      let columns, label =
        match finding.mark with
        | Some { start; stop; label } -> (Some (start, stop), Some (shown label))
        | None -> (None, None)
      in
      item source path span ~columns ~label ~sign:'^'
        ~style:(Style.of_tier tier))

let related source path span label =
  item source path span ~columns:None
    ~label:(Some (shown label))
    ~sign:'-' ~style:Style.Frame

type group = { first : Finding.place; places : (Finding.place * string) list }

let rec groups = function
  | [] -> []
  | (({ Finding.path; _ } as first), label) :: rest ->
      let rec take taken = function
        | ((place : Finding.place), label) :: rest
          when String.equal place.path path ->
            take ((place, label) :: taken) rest
        | rest -> (List.rev taken, rest)
      in
      let places, rest = take [ (first, label) ] rest in
      { first; places } :: groups rest

let headline ppf ~tier (finding : Finding.t) =
  let name = Finding_class.name finding.finding_class in
  (match tier with
  | Some tier ->
      Style.string
        (Style.of_tier (Some tier))
        ppf
        (Finding_class.tier_name tier ^ "[" ^ name ^ "]")
  | None -> Style.string Style.Headline ppf name);
  Option.iter
    (fun detail ->
      let detail = shown detail in
      if detail <> "" then (
        Fmt.string ppf ": ";
        Fmt.string ppf detail))
    finding.detail;
  newline ppf

let location ppf width arrow { Finding.path; span } =
  spaces ppf width;
  Style.string Style.Frame ppf arrow;
  Fmt.pf ppf " %s:%d:%d" (Display.clean path) span.start.line span.start.column;
  newline ppf

let note ppf width label =
  spaces ppf (width + 1);
  Style.string Style.Frame ppf "=";
  Fmt.string ppf " ";
  Style.string Style.Note ppf "note:";
  let label = shown label in
  if label <> "" then (
    Fmt.string ppf " ";
    Fmt.string ppf label);
  newline ppf

let full ppf source ~tier (finding : Finding.t) =
  let here =
    Option.map (fun ({ path; _ } : Finding.place) -> path) finding.place
  in
  let same, elsewhere, notes =
    List.fold_right
      (fun ({ label; place } : Finding.related) (same, elsewhere, notes) ->
        match place with
        | None -> (same, elsewhere, label :: notes)
        | Some place when Some place.path = here ->
            ((place, label) :: same, elsewhere, notes)
        | Some place -> (same, (place, label) :: elsewhere, notes))
      finding.related ([], [], [])
  in
  let main =
    sorted_rows
      (Option.to_list (primary source ~tier finding)
      @ List.filter_map
          (fun (({ path; span } : Finding.place), label) ->
            related source path span label)
          same)
  in
  let blocks =
    List.map
      (fun group ->
        ( group.first,
          sorted_rows
            (List.filter_map
               (fun (({ path; span } : Finding.place), label) ->
                 related source path span label)
               group.places) ))
      (groups elsewhere)
  in
  let width =
    digits
      (List.fold_left
         (fun top (_, rows) -> max top (top_number rows))
         (top_number main) blocks)
  in
  headline ppf ~tier finding;
  Option.iter (location ppf width "-->") finding.place;
  snippet ppf width main;
  List.iter
    (fun (first, rows) ->
      location ppf width ":::" first;
      snippet ppf width rows)
    blocks;
  List.iter (note ppf width) notes
