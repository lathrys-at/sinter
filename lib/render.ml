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

let tier_and_class ppf ~tier finding_class =
  let name = Finding_class.name finding_class in
  match tier with
  | Some tier ->
      Style.string
        (Style.of_tier (Some tier))
        ppf
        (Finding_class.tier_name tier ^ "[" ^ name ^ "]")
  | None -> Style.string Style.Headline ppf name

let headline ppf ~tier (finding : Finding.t) =
  tier_and_class ppf ~tier finding.finding_class;
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

type diff =
  | Added of { anchor : int; lines : string list }
  | Inserted of { anchor : int; line : string; marks : (int * int) list }
  | Replaced of { anchor : int; old : string; lines : string list }

let offset raw column =
  let rec walk offset column =
    if column <= 1 then Some offset
    else if offset >= String.length raw then None
    else
      walk
        (offset + Uchar.utf_decode_length (String.get_utf_8_uchar raw offset))
        (column - 1)
  in
  walk 0 column

let rec lines_of_pieces = function
  | [] -> []
  | [ last ] -> [ last ]
  | piece :: rest ->
      (if String.ends_with ~suffix:"\r" piece then
         String.sub piece 0 (String.length piece - 1)
       else piece)
      :: lines_of_pieces rest

let lines_of text = lines_of_pieces (String.split_on_char '\n' text)

let rec placed raw = function
  | [] -> Some []
  | (edit : Fix.edit) :: rest -> (
      match (offset raw edit.col, offset raw edit.ecol, placed raw rest) with
      | Some start, Some stop, Some others when start <= stop ->
          Some ((start, stop, edit) :: others)
      | _ -> None)

let applied raw edits =
  let buffer = Buffer.create (String.length raw + 32) in
  let stop, inserted =
    List.fold_left
      (fun (position, inserted) (start, stop, (edit : Fix.edit)) ->
        Buffer.add_substring buffer raw position (start - position);
        let at = Buffer.length buffer in
        Buffer.add_string buffer edit.text;
        (stop, (at, edit.text) :: inserted))
      (0, []) edits
  in
  Buffer.add_substring buffer raw stop (String.length raw - stop);
  (Buffer.contents buffer, List.rev inserted)

let rec ordered = function
  | (_, stop, _) :: ((start, _, _) :: _ as rest) ->
      stop <= start && ordered rest
  | [ _ ] | [] -> true

let insertions line inserted =
  List.map
    (fun (at, text) ->
      (Display.width (String.sub line 0 at), max 1 (Display.width text)))
    inserted

let diff source path = function
  | [] -> None
  | (first : Fix.edit) :: _ as edits ->
      let anchor = first.line in
      if
        List.exists
          (fun (edit : Fix.edit) -> edit.line <> anchor || edit.eline <> anchor)
          edits
      then None
      else
        Option.bind (Source.line source path anchor) (fun raw ->
            Option.bind (placed raw edits) (fun edits ->
                let edits =
                  List.stable_sort
                    (fun (a, _, _) (b, _, _) -> Int.compare a b)
                    edits
                in
                if not (ordered edits) then None
                else
                  let text, inserted = applied raw edits in
                  match lines_of text with
                  | first :: (_ :: _ as lines) when String.equal first raw ->
                      Some (Added { anchor; lines })
                  | [ line ]
                    when List.for_all
                           (fun (start, stop, _) -> start = stop)
                           edits ->
                      Some
                        (Inserted
                           { anchor; line; marks = insertions line inserted })
                  | lines -> Some (Replaced { anchor; old = raw; lines })))

let diffs source (finding : Finding.t) =
  match (finding.fix, finding.place) with
  | Some fix, Some { path; _ } ->
      let rec all = function
        | [] -> Some []
        | edits :: rest ->
            Option.bind (diff source path edits) (fun diff ->
                Option.map (fun diffs -> diff :: diffs) (all rest))
      in
      Some (fix, all (Fix.alternatives fix))
  | Some _, None | None, _ -> None

let last_number = function
  | Added { anchor; lines } -> anchor + List.length lines
  | Inserted { anchor; _ } -> anchor
  | Replaced { anchor; lines; _ } -> anchor + List.length lines - 1

let signed ppf width number sign style text =
  Style.string Style.Frame ppf (Printf.sprintf "%*d " width number);
  Style.string style ppf sign;
  let text = shown text in
  if text <> "" then (
    Fmt.string ppf " ";
    Style.string style ppf text);
  newline ppf

let diff_rows ppf width = function
  | Added { anchor; lines } ->
      List.iteri
        (fun index line ->
          signed ppf width (anchor + 1 + index) "+" Style.Inserted line)
        lines
  | Inserted { anchor; line; marks } ->
      source_row ppf width
        { number = anchor; text = shown line; marks = []; continues = false };
      spaces ppf (width + 1);
      Style.string Style.Frame ppf "|";
      Fmt.string ppf " ";
      ignore
        (List.fold_left
           (fun column (start, size) ->
             spaces ppf (start - column);
             Style.string Style.Inserted ppf (String.make size '+');
             start + size)
           0 marks);
      newline ppf
  | Replaced { anchor; old; lines } ->
      signed ppf width anchor "-" Style.Removed old;
      List.iteri
        (fun index line ->
          signed ppf width (anchor + index) "+" Style.Inserted line)
        lines

let help ppf fix =
  Style.string Style.Help ppf "help:";
  let text = shown (Fix.help fix) in
  if text <> "" then (
    Fmt.string ppf " ";
    Fmt.string ppf text);
  newline ppf

let fix_lines ppf width = function
  | None -> ()
  | Some (fix, Some diffs) ->
      help ppf fix;
      List.iter
        (fun diff ->
          empty_gutter ppf width;
          diff_rows ppf width diff)
        diffs;
      empty_gutter ppf width
  | Some (fix, None) ->
      help ppf fix;
      Fmt.string ppf "  ";
      Style.string Style.Help ppf "fix:";
      Fmt.string ppf " ";
      Fmt.string ppf (shown (Fix.text fix));
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
  let fix = diffs source finding in
  let width =
    digits
      (List.fold_left
         (fun top diff -> max top (last_number diff))
         (List.fold_left
            (fun top (_, rows) -> max top (top_number rows))
            (top_number main) blocks)
         (match fix with Some (_, Some diffs) -> diffs | _ -> []))
  in
  headline ppf ~tier finding;
  Option.iter (location ppf width "-->") finding.place;
  snippet ppf width main;
  List.iter
    (fun (first, rows) ->
      location ppf width ":::" first;
      snippet ppf width rows)
    blocks;
  List.iter (note ppf width) notes;
  fix_lines ppf width fix

let brief ppf ~tier (finding : Finding.t) =
  (match finding.place with
  | Some { path; span } ->
      Fmt.pf ppf "%s:%d:%d: " (Display.clean path) span.start.line
        span.start.column
  | None -> Fmt.string ppf "-:-:-: ");
  tier_and_class ppf ~tier finding.finding_class;
  Option.iter
    (fun detail ->
      let detail = shown detail in
      if detail <> "" then (
        Fmt.string ppf " ";
        Fmt.string ppf detail))
    finding.detail;
  newline ppf;
  Option.iter
    (fun fix ->
      Fmt.string ppf "  ";
      Style.string Style.Help ppf "fix:";
      let text = shown (Fix.text fix) in
      if text <> "" then (
        Fmt.string ppf " ";
        Fmt.string ppf text);
      newline ppf)
    finding.fix
