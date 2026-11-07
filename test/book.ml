(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(* @cites user-manual *)

type problem =
  | Nested_fence
  | Unclosed_fence
  | Unclosed_comment
  | Unknown_label of string
  | Console_without_label
  | Path_outside of string
  | No_command
  | Command_outside_block
  | Keeps_shell_state of string
  | Bad_note
  | Planned_without_note
  | Run_under_note
  | Differs of { command : string; expected : string; actual : string }
  | Wrong_exit of {
      command : string;
      expected : int;
      actual : int;
      output : string;
    }
  | Cannot_promote of { command : string; output : string }
  | Harness of Fixture.error
  | Empty_link
  | Rooted_link of string
  | Link_leaves_book of string
  | Missing_target of string
  | Missing_anchor of { target : string; anchor : string }
  | Undefined_reference of string
  | Not_in_summary
  | No_summary
  | Listing_without_page
  | Listing_for_two_pages of string list
  | Unreadable of string

type error = { file : string; line : int option; problem : problem }
type mode = Compare | Promote_into of string

let ( let* ) = Result.bind

let first_word command =
  let trimmed = String.trim command in
  let length = String.length trimmed in
  let rec stop index =
    if
      index < length
      && (not (trimmed.[index] = ' ' || trimmed.[index] = '\t'))
      && not (String.contains ";&|" trimmed.[index])
    then stop (index + 1)
    else index
  in
  String.sub trimmed 0 (stop 0)

let changes_folder command = String.equal (first_word command) "cd"

let describe = function
  | Nested_fence ->
      "a fence must start at the first column, outside lists and block quotes."
  | Unclosed_fence -> "the block has no closing fence."
  | Unclosed_comment -> "the HTML comment has no end."
  | Unknown_label label -> Printf.sprintf "the label %S is not known." label
  | Console_without_label ->
      "a console block must say run or planned: console,run or console,planned."
  | Path_outside path ->
      Printf.sprintf
        "the path %S is not a plain path inside the repository, outside .git."
        path
  | No_command -> "a run block must start with a line \"$ <command>\"."
  | Command_outside_block ->
      "a command must be in a block labeled console,run or console,planned."
  | Keeps_shell_state command when changes_folder command ->
      Printf.sprintf
        "the command %S only changes the folder of its own shell, and each \
         command runs in a new shell at the root of the repository. Give each \
         command its paths from the root."
        command
  | Keeps_shell_state command ->
      Printf.sprintf
        "the command %S only sets variables of its own shell, and each command \
         runs in a new shell. Put the variables in front of the command that \
         needs them."
        command
  | Bad_note ->
      "a note is exactly the two lines \"> [!NOTE]\" and \"> Sinter does not \
       have this <thing> yet.\", with a blank line below them."
  | Planned_without_note ->
      "a planned block needs a note above it, with only text between them."
  | Run_under_note ->
      "a run block cannot follow a note unless text lies between them."
  | Differs { command; expected; actual } ->
      Printf.sprintf
        "the output of %S differs.\n\
        \  expected: %S\n\
        \  actual:   %S\n\
         To accept the output, run the suite with SINTER_PROMOTE=1."
        command expected actual
  | Wrong_exit { command; expected; actual; output } ->
      Printf.sprintf
        "%S must exit with %d, and it exited with %d.\n  output: %S" command
        expected actual output
  | Cannot_promote { command; output } ->
      Printf.sprintf "the block cannot hold the output of %S: %S." command
        output
  | Harness error -> Fixture.message ~case:"the block" error
  | Empty_link -> "the link has an empty destination."
  | Rooted_link target ->
      Printf.sprintf "the link %S starts with /. Write a relative link." target
  | Link_leaves_book target ->
      Printf.sprintf "the link %S leads out of src/." target
  | Missing_target target -> Printf.sprintf "the link %S names no file." target
  | Missing_anchor { target; anchor } ->
      Printf.sprintf "the file %s has no heading with the id %S." target anchor
  | Undefined_reference label ->
      Printf.sprintf "the reference %S has no definition." label
  | Not_in_summary -> "no link of SUMMARY.md names this page."
  | No_summary -> "the book has no file src/SUMMARY.md."
  | Listing_without_page -> "no page has the stem of this folder of listings."
  | Listing_for_two_pages names ->
      Printf.sprintf "more than one page has the stem of this listing: %s."
        (String.concat ", " names)
  | Unreadable reason -> reason

let message { file; line; problem } =
  match line with
  | Some line -> Printf.sprintf "%s:%d: %s" file line (describe problem)
  | None -> Printf.sprintf "%s: %s" file (describe problem)

let mode_of_environment ~promote ~source_root =
  let* mode = Fixture.mode_of_environment ~promote ~source_root in
  match (mode, source_root) with
  | Fixture.Promote_into _, Some root ->
      Ok
        (Promote_into
           (List.fold_left Filename.concat root [ "docs"; "book"; "src" ]))
  | _ -> Ok Compare

let read_file path = In_channel.with_open_bin path In_channel.input_all

let write_file path text =
  Out_channel.with_open_bin path (fun channel ->
      Out_channel.output_string channel text)

let entries folder =
  List.sort String.compare (Array.to_list (Sys.readdir folder))

let is_space character = character = ' ' || character = '\t'
let is_digit character = character >= '0' && character <= '9'

let is_letter character =
  (character >= 'a' && character <= 'z')
  || (character >= 'A' && character <= 'Z')

let find_from text ~pattern start =
  let length = String.length text and size = String.length pattern in
  let rec scan index =
    if index + size > length then None
    else if String.equal (String.sub text index size) pattern then Some index
    else scan (index + 1)
  in
  scan start

let rest text start = String.sub text start (String.length text - start)

let run_end text start character =
  let length = String.length text in
  let rec scan index =
    if index < length && text.[index] = character then scan (index + 1)
    else index
  in
  scan start

let leading_spaces line = run_end line 0 ' '

let rec container_end line index =
  let length = String.length line in
  if index >= length then index
  else
    match line.[index] with
    | ' ' | '\t' | '>' -> container_end line (index + 1)
    | ('-' | '*' | '+') when index + 1 < length && is_space line.[index + 1] ->
        container_end line (index + 2)
    | character when is_digit character ->
        let rec digits at =
          if at < length && is_digit line.[at] then digits (at + 1) else at
        in
        let stop = digits index in
        if
          stop + 1 < length
          && (line.[stop] = '.' || line.[stop] = ')')
          && is_space line.[stop + 1]
        then container_end line (stop + 2)
        else index
    | _ -> index

let mask_code line =
  let masked = Bytes.of_string line in
  let length = String.length line in
  let rec closing index size =
    if index >= length then None
    else if line.[index] = '`' then
      let stop = run_end line index '`' in
      if stop - index = size then Some index else closing stop size
    else closing (index + 1) size
  in
  let rec scan index =
    if index < length then
      match line.[index] with
      | '\\' -> scan (index + 2)
      | '`' -> (
          let stop = run_end line index '`' in
          let size = stop - index in
          match closing stop size with
          | Some close ->
              Bytes.fill masked index (close + size - index) ' ';
              scan (close + size)
          | None -> scan stop)
      | _ -> scan (index + 1)
  in
  scan 0;
  Bytes.to_string masked

let rec remove_comments ~opened line =
  if opened then
    match find_from line ~pattern:"-->" 0 with
    | None -> ("", true)
    | Some at -> remove_comments ~opened:false (rest line (at + 3))
  else
    match find_from (mask_code line) ~pattern:"<!--" 0 with
    | None -> (line, false)
    | Some at ->
        let after, still = remove_comments ~opened:true (rest line (at + 4)) in
        (String.sub line 0 at ^ after, still)

type fence = { mark : char; size : int; info : string }

let fence_at line start =
  if start >= String.length line then None
  else
    match line.[start] with
    | ('`' | '~') as mark ->
        let stop = run_end line start mark in
        let info = String.trim (rest line stop) in
        if stop - start < 3 || (mark = '`' && String.contains info '`') then
          None
        else Some { mark; size = stop - start; info }
    | _ -> None

let closes { mark; size; _ } line =
  let start = min 3 (leading_spaces line) in
  let stop = run_end line start mark in
  stop - start >= size && String.equal (String.trim (rest line stop)) ""

type label = Shown | Writes of string | Runs of int | Planned

let allowed_path path =
  let allowed part =
    not (List.mem (String.lowercase_ascii part) [ ""; "."; ".."; ".git" ])
  in
  (not (String.starts_with ~prefix:"/" path))
  && List.for_all allowed (String.split_on_char '/' path)

let exit_code text =
  if
    String.length text >= 1
    && String.length text <= 3
    && String.for_all is_digit text
  then
    let code = int_of_string text in
    if code <= 255 then Some code else None
  else None

let has_space text = String.exists (fun c -> is_space c || c = '\r') text

let parse_label info =
  let unknown = Error (Unknown_label info) in
  let is_console name = String.equal (String.lowercase_ascii name) "console" in
  if String.equal info "" then Ok Shown
  else if has_space info then unknown
  else
    match String.split_on_char ',' info with
    | [ name ] when is_console name -> Error Console_without_label
    | [ name; "run" ] when is_console name -> Ok (Runs 0)
    | [ name; "planned" ] when is_console name -> Ok Planned
    | [ name; "run"; code ]
      when is_console name && String.starts_with ~prefix:"exit=" code -> (
        match exit_code (rest code 5) with
        | Some code -> Ok (Runs code)
        | None -> unknown)
    | name :: _ when is_console name -> unknown
    | [ "" ] | "" :: _ -> unknown
    | [ _ ] -> Ok Shown
    | [ _; file ] when String.starts_with ~prefix:"file=" file ->
        let path = rest file 5 in
        if String.equal path "" then unknown
        else if allowed_path path then Ok (Writes path)
        else Error (Path_outside path)
    | _ -> unknown

type block = { opening : int; fence : fence; label : label; body : string list }
type item = Text of int * string | Note of int * string | Block of block

let note_prefix = "> Sinter does not have this "
let note_suffix = " yet."

let is_note_text line =
  String.starts_with ~prefix:note_prefix line
  && String.ends_with ~suffix:note_suffix line
  &&
  let size = String.length note_prefix in
  let inner = String.length line - size - String.length note_suffix in
  inner > 0 && not (String.equal (String.trim (String.sub line size inner)) "")

let is_note_head line =
  let start = container_end line 0 in
  String.contains (String.sub line 0 start) '>'
  && String.starts_with ~prefix:"[!NOTE]"
       (String.uppercase_ascii (rest line start))

let is_command line = String.starts_with ~prefix:"$ " line

let scan text =
  let lines = Array.of_list (String.split_on_char '\n' text) in
  let count = Array.length lines in
  let fail index problem = Error (index + 1, problem) in
  let rec closing fence index =
    if index >= count then None
    else if closes fence lines.(index) then Some index
    else closing fence (index + 1)
  in
  let read_block index fence walk found =
    match parse_label fence.info with
    | Error problem -> fail index problem
    | Ok label -> (
        match closing fence (index + 1) with
        | None -> fail index Unclosed_fence
        | Some close -> (
            let body =
              Array.to_list (Array.sub lines (index + 1) (close - index - 1))
            in
            let offender =
              if label = Shown then List.find_index is_command body else None
            in
            match offender with
            | Some at -> fail (index + 1 + at) Command_outside_block
            | None ->
                walk (close + 1)
                  (Block { opening = index; fence; label; body } :: found)))
  in
  let rec walk ~opened ~comment index found =
    if index >= count then
      if opened then fail comment Unclosed_comment else Ok (List.rev found)
    else
      let line, still = remove_comments ~opened lines.(index) in
      let comment = if still && not opened then index else comment in
      let next = walk ~opened:still ~comment in
      let start = container_end line 0 in
      match fence_at line start with
      | Some _ when start > 0 -> fail index Nested_fence
      | Some fence -> read_block index fence (walk ~opened:still ~comment) found
      | None ->
          if is_note_head line then
            let below = index + 2 in
            if
              String.equal line "> [!NOTE]"
              && index + 1 < count
              && is_note_text lines.(index + 1)
              && (below >= count || String.equal (String.trim lines.(below)) "")
            then next below (Note (index + 1, lines.(index + 1)) :: found)
            else fail index Bad_note
          else if is_command (rest line start) then
            fail index Command_outside_block
          else if String.equal (String.trim line) "" then next (index + 1) found
          else next (index + 1) (Text (index, line) :: found)
  in
  walk ~opened:false ~comment:0 0 []

let check_notes items =
  let step state item =
    let* open_note, no_text = state in
    match item with
    | Note _ -> Ok (true, true)
    | Text _ -> Ok (open_note, false)
    | Block { opening; label = Planned; _ } ->
        if open_note then Ok (false, no_text)
        else Error (opening + 1, Planned_without_note)
    | Block { opening; label = Runs _; _ } ->
        if no_text then Error (opening + 1, Run_under_note)
        else Ok (false, false)
    | Block _ -> Ok (false, no_text)
  in
  let* _ = List.fold_left step (Ok (false, false)) items in
  Ok ()

let command_of line = rest line 2

let assignment_end command =
  let length = String.length command in
  let is_name_start c = is_letter c || c = '_' in
  let is_name c = is_name_start c || is_digit c in
  if length = 0 || not (is_name_start command.[0]) then None
  else
    let rec name index =
      if index < length && is_name command.[index] then name (index + 1)
      else index
    in
    let equals = name 0 in
    if equals >= length || command.[equals] <> '=' then None
    else
      let rec value index quote =
        if index >= length then index
        else
          match (command.[index], quote) with
          | c, Some q when c = q -> value (index + 1) None
          | _, Some _ -> value (index + 1) quote
          | '\\', None -> value (index + 2) None
          | (('"' | '\'') as c), None -> value (index + 1) (Some c)
          | c, None when is_space c || c = ';' || c = '&' -> index
          | _, None -> value (index + 1) None
      in
      Some (min length (value (equals + 1) None))

let only_sets_variables command =
  let trimmed = String.trim command in
  let rec assignments text ~seen =
    match assignment_end text with
    | None ->
        seen
        && (String.equal text ""
           || String.starts_with ~prefix:";" text
           || String.starts_with ~prefix:"&" text)
    | Some stop -> assignments (String.trim (rest text stop)) ~seen:true
  in
  assignments trimmed ~seen:false

let keeps_shell_state command =
  List.mem (first_word command) [ "cd"; "export" ]
  || only_sets_variables command

let check_commands items =
  let check_body opening body =
    match body with
    | first :: _ when is_command first ->
        List.fold_left
          (fun (checked, index) line ->
            let result =
              let* () = checked in
              if not (is_command line) then Ok ()
              else if String.equal (String.trim (command_of line)) "" then
                Error (index, No_command)
              else if keeps_shell_state (command_of line) then
                Error (index, Keeps_shell_state (command_of line))
              else Ok ()
            in
            (result, index + 1))
          (Ok (), opening + 2)
          body
        |> fst
    | _ -> Error (opening + 2, No_command)
  in
  List.fold_left
    (fun checked item ->
      let* () = checked in
      match item with
      | Block { opening; label = Runs _; body; _ } -> check_body opening body
      | _ -> Ok ())
    (Ok ()) items

let parse_page text =
  let* items = scan text in
  let* () = check_notes items in
  let* () = check_commands items in
  Ok items

let check_page text =
  let* _ = parse_page text in
  Ok ()

let entity_text name =
  match name with
  | "amp" -> "&"
  | "lt" -> "<"
  | "gt" -> ">"
  | "quot" -> "\""
  | "apos" -> "'"
  | "nbsp" -> " "
  | _ -> (
      let code =
        if String.length name > 1 && name.[0] = '#' then
          if name.[1] = 'x' || name.[1] = 'X' then
            int_of_string_opt ("0x" ^ String.sub name 2 (String.length name - 2))
          else int_of_string_opt (String.sub name 1 (String.length name - 1))
        else None
      in
      match code with
      | Some code when code >= 32 && code < 127 -> String.make 1 (Char.chr code)
      | _ -> "\x80")

let plain_text text =
  let length = String.length text in
  let buffer = Buffer.create length in
  let is_word c = is_letter c || is_digit c || Char.code c >= 128 in
  let rec closing_paren index depth =
    if index >= length then length
    else
      match text.[index] with
      | '(' -> closing_paren (index + 1) (depth + 1)
      | ')' when depth = 0 -> index + 1
      | ')' -> closing_paren (index + 1) (depth - 1)
      | _ -> closing_paren (index + 1) depth
  in
  let skip_to character index =
    match String.index_from_opt text index character with
    | Some at -> Some (at + 1)
    | None -> None
  in
  let rec scan index =
    if index < length then
      match text.[index] with
      | '\\' when index + 1 < length ->
          Buffer.add_char buffer text.[index + 1];
          scan (index + 2)
      | '`' -> (
          let stop = run_end text index '`' in
          let size = stop - index in
          let marker = String.make size '`' in
          match find_from text ~pattern:marker stop with
          | Some close ->
              Buffer.add_string buffer (String.sub text stop (close - stop));
              scan (close + size)
          | None -> scan stop)
      | '!' when index + 1 < length && text.[index + 1] = '[' -> (
          match find_from text ~pattern:"](" index with
          | Some close -> scan (closing_paren (close + 2) 0)
          | None -> scan (index + 1))
      | ']' when index + 1 < length && text.[index + 1] = '(' ->
          scan (closing_paren (index + 2) 0)
      | ']' when index + 1 < length && text.[index + 1] = '[' -> (
          match skip_to ']' (index + 2) with
          | Some after -> scan after
          | None -> scan (index + 1))
      | '<'
        when index + 1 < length
             && (is_letter text.[index + 1]
                || text.[index + 1] = '/'
                || text.[index + 1] = '!') -> (
          match skip_to '>' index with
          | Some after -> scan after
          | None -> scan (index + 1))
      | '&' -> (
          let rec entity at =
            if at >= length then None
            else if text.[at] = ';' then Some (at + 1)
            else if is_letter text.[at] || is_digit text.[at] || text.[at] = '#'
            then entity (at + 1)
            else None
          in
          match entity (index + 1) with
          | Some after when after > index + 2 ->
              Buffer.add_string buffer
                (entity_text (String.sub text (index + 1) (after - index - 2)));
              scan after
          | _ -> scan (index + 1))
      | '_' ->
          let stop = run_end text index '_' in
          let before = index > 0 && is_word text.[index - 1] in
          let after = stop < length && is_word text.[stop] in
          if before && after then
            Buffer.add_string buffer (String.sub text index (stop - index));
          scan stop
      | character ->
          Buffer.add_char buffer character;
          scan (index + 1)
  in
  scan 0;
  Buffer.contents buffer

let normalize text =
  let buffer = Buffer.create (String.length text) in
  String.iter
    (fun character ->
      if
        is_letter character || is_digit character || character = '_'
        || character = '-'
        || Char.code character >= 128
      then Buffer.add_char buffer (Char.lowercase_ascii character)
      else if is_space character || character = '\n' then
        Buffer.add_char buffer '-')
    (String.trim text);
  Buffer.contents buffer

let split_attributes text =
  let trimmed = String.trim text in
  match
    (String.ends_with ~suffix:"}" trimmed, String.rindex_opt trimmed '{')
  with
  | true, Some start ->
      let inner =
        String.sub trimmed (start + 1) (String.length trimmed - start - 2)
      in
      let custom =
        List.find_map
          (fun part ->
            if String.length part > 1 && part.[0] = '#' then Some (rest part 1)
            else None)
          (String.split_on_char ' ' inner)
      in
      (String.sub trimmed 0 start, custom)
  | _ -> (trimmed, None)

let atx_content line =
  let start = container_end line 0 in
  if leading_spaces line >= 4 then None
  else
    let stop = run_end line start '#' in
    let level = stop - start in
    if
      level < 1 || level > 6
      || (stop < String.length line && not (is_space line.[stop]))
    then None
    else
      let content = String.trim (rest line stop) in
      let closed =
        let size = String.length content in
        let rec back index =
          if index > 0 && content.[index - 1] = '#' then back (index - 1)
          else index
        in
        let first = back size in
        if first = size then content
        else if first = 0 then ""
        else if is_space content.[first - 1] then String.sub content 0 first
        else content
      in
      Some closed

let is_setext_underline line =
  let trimmed = String.trim line in
  leading_spaces line <= 3
  && String.length trimmed >= 1
  && (String.for_all (fun c -> c = '=') trimmed
     || String.for_all (fun c -> c = '-') trimmed)

let heading_ids_of items =
  let used = Hashtbl.create 16 in
  let unique id =
    let rec numbered counter =
      let candidate = Printf.sprintf "%s-%d" id counter in
      if Hashtbl.mem used candidate then numbered (counter + 1) else candidate
    in
    let chosen = if Hashtbl.mem used id then numbered 1 else id in
    Hashtbl.replace used chosen ();
    chosen
  in
  let id_of content =
    let text, custom = split_attributes content in
    match custom with
    | Some id -> id
    | None -> unique (normalize (plain_text text))
  in
  let step (ids, pending, last) item =
    match item with
    | Text (line, text) -> (
        match atx_content text with
        | Some content -> (id_of content :: ids, [], -1)
        | None ->
            let follows = last = line - 1 in
            if is_setext_underline text && pending <> [] && follows then
              (id_of (String.concat " " (List.rev pending)) :: ids, [], -1)
            else if
              container_end text 0 <> leading_spaces text
              || leading_spaces text > 3
            then (ids, [], -1)
            else
              (ids, String.trim text :: (if follows then pending else []), line)
        )
    | Note _ | Block _ -> (ids, [], -1)
  in
  let ids, _, _ = List.fold_left step ([], [], -1) items in
  List.rev ids

let heading_ids text =
  match scan text with Ok items -> heading_ids_of items | Error _ -> []

let percent_decode text =
  let length = String.length text in
  let buffer = Buffer.create length in
  let hex c =
    match c with
    | '0' .. '9' -> Some (Char.code c - 48)
    | 'a' .. 'f' -> Some (Char.code c - 87)
    | 'A' .. 'F' -> Some (Char.code c - 55)
    | _ -> None
  in
  let rec scan index =
    if index < length then
      if text.[index] = '%' && index + 2 < length then (
        match (hex text.[index + 1], hex text.[index + 2]) with
        | Some high, Some low ->
            Buffer.add_char buffer (Char.chr ((high * 16) + low));
            scan (index + 3)
        | _ ->
            Buffer.add_char buffer '%';
            scan (index + 1))
      else (
        Buffer.add_char buffer text.[index];
        scan (index + 1))
  in
  scan 0;
  Buffer.contents buffer

let has_scheme target =
  let length = String.length target in
  let rec scan index =
    if index >= length then false
    else
      let c = target.[index] in
      if c = ':' then index > 0
      else if
        is_letter c || (index > 0 && (is_digit c || String.contains "+-." c))
      then scan (index + 1)
      else false
  in
  scan 0

let destination text start =
  let length = String.length text in
  let rec skip index =
    if index < length && is_space text.[index] then skip (index + 1) else index
  in
  let first = skip start in
  if first < length && text.[first] = '<' then
    match String.index_from_opt text first '>' with
    | Some close -> String.sub text (first + 1) (close - first - 1)
    | None -> rest text first
  else
    let rec scan index depth =
      if index >= length then index
      else
        match text.[index] with
        | c when is_space c -> index
        | '\\' -> scan (index + 2) depth
        | '(' -> scan (index + 1) (depth + 1)
        | ')' when depth = 0 -> index
        | ')' -> scan (index + 1) (depth - 1)
        | _ -> scan (index + 1) depth
    in
    let stop = min length (scan first 0) in
    String.sub text first (stop - first)

let normalize_label text =
  String.lowercase_ascii
    (String.concat " "
       (List.filter
          (fun part -> not (String.equal part ""))
          (String.split_on_char ' ' (String.trim text))))

let definition text =
  let start = leading_spaces text in
  if start > 3 || start >= String.length text || text.[start] <> '[' then None
  else
    match find_from text ~pattern:"]:" start with
    | Some close
      when not (String.contains (String.sub text start (close - start)) ']') ->
        let label = String.sub text (start + 1) (close - start - 1) in
        if String.starts_with ~prefix:"^" label then None
        else Some (normalize_label label, destination text (close + 2))
    | _ -> None

let attribute_links text =
  List.concat_map
    (fun pattern ->
      let rec scan start found =
        match find_from text ~pattern start with
        | None -> List.rev found
        | Some at ->
            let first = at + String.length pattern in
            let quote = pattern.[String.length pattern - 1] in
            let stop =
              Option.value
                (String.index_from_opt text first quote)
                ~default:(String.length text)
            in
            scan stop (String.sub text first (stop - first) :: found)
      in
      if String.contains text '<' then scan 0 [] else [])
    [ " href=\""; " href='"; " src=\""; " src='" ]

let inline_links masked =
  let rec scan start found =
    match find_from masked ~pattern:"](" start with
    | None -> List.rev found
    | Some at when at > 0 && masked.[at - 1] = '\\' -> scan (at + 2) found
    | Some at -> scan (at + 2) (destination masked (at + 2) :: found)
  in
  scan 0 []

let references masked =
  let rec scan start found =
    match find_from masked ~pattern:"][" start with
    | None -> List.rev found
    | Some at when at > 0 && masked.[at - 1] = '\\' -> scan (at + 2) found
    | Some at -> (
        match String.index_from_opt masked (at + 2) ']' with
        | None -> List.rev found
        | Some close ->
            let label = String.sub masked (at + 2) (close - at - 2) in
            let label =
              if String.equal (String.trim label) "" then
                match String.rindex_from_opt masked at '[' with
                | Some open_at ->
                    String.sub masked (open_at + 1) (at - open_at - 1)
                | None -> label
              else label
            in
            scan (close + 1) (label :: found))
  in
  scan 0 []

let resolve ~folder path =
  let step stack part =
    match (stack, part) with
    | None, _ -> None
    | Some _, ("" | ".") -> stack
    | Some [], ".." -> None
    | Some (_ :: above), ".." -> Some above
    | Some stack, name -> Some (name :: stack)
  in
  Option.map List.rev
    (List.fold_left step
       (Some (List.rev folder))
       (String.split_on_char '/' path))

let exact_file ~src parts =
  let rec walk folder = function
    | [] -> false
    | name :: below -> (
        match Sys.readdir folder with
        | exception Sys_error _ -> false
        | names ->
            Array.mem name names
            &&
            let path = Filename.concat folder name in
            if below = [] then
              Sys.file_exists path && not (Sys.is_directory path)
            else walk path below)
  in
  walk src parts

let folder_parts page =
  match List.rev (String.split_on_char '/' page) with
  | [] -> []
  | _ :: above -> List.rev above

let is_ascii text = String.for_all (fun c -> Char.code c < 128) text

let split_anchor target =
  match String.index_opt target '#' with
  | None -> (percent_decode target, None)
  | Some at ->
      ( percent_decode (String.sub target 0 at),
        Some (percent_decode (rest target (at + 1))) )

let check_target ~src ~page target =
  if String.equal target "" then Some Empty_link
  else if has_scheme target || String.starts_with ~prefix:"//" target then None
  else
    let path, anchor = split_anchor target in
    if String.starts_with ~prefix:"/" path then Some (Rooted_link target)
    else
      let resolved =
        if String.equal path "" then Some (String.split_on_char '/' page)
        else resolve ~folder:(folder_parts page) path
      in
      match resolved with
      | None -> Some (Link_leaves_book target)
      | Some parts -> (
          let name = String.concat "/" parts in
          if String.equal path "" && anchor = None then Some Empty_link
          else if not (exact_file ~src parts) then Some (Missing_target target)
          else
            match anchor with
            | None -> None
            | Some anchor ->
                let ids =
                  if String.ends_with ~suffix:".md" name then
                    heading_ids (read_file (Filename.concat src name))
                  else []
                in
                if is_ascii anchor && List.mem anchor ids then None
                else Some (Missing_anchor { target = name; anchor }))

let text_lines items =
  List.filter_map
    (function
      | Text (line, text) | Note (line, text) -> Some (line, text)
      | Block _ -> None)
    items

let check_file_links ~src page =
  let file = Filename.concat "src" page in
  match scan (read_file (Filename.concat src page)) with
  | Error _ -> ([], [])
  | Ok items ->
      let lines = text_lines items in
      let definitions =
        List.filter_map
          (fun (_, text) -> Option.map fst (definition (mask_code text)))
          lines
      in
      let on_line (line, text) =
        let masked = mask_code text in
        let targets =
          match definition masked with
          | Some (_, target) -> [ target ]
          | None -> inline_links masked @ attribute_links masked
        in
        let located problem = { file; line = Some (line + 1); problem } in
        List.filter_map
          (fun target -> Option.map located (check_target ~src ~page target))
          targets
        @ List.filter_map
            (fun label ->
              if List.mem (normalize_label label) definitions then None
              else Some (located (Undefined_reference label)))
            (references masked)
      in
      let targets =
        List.concat_map
          (fun (_, text) ->
            let masked = mask_code text in
            match definition masked with
            | Some (_, target) -> [ target ]
            | None -> inline_links masked)
          lines
      in
      (List.concat_map on_line lines, targets)

let rec walk_pages folder prefix =
  List.concat_map
    (fun name ->
      let path = Filename.concat folder name
      and relative = if prefix = "" then name else prefix ^ "/" ^ name in
      if Sys.is_directory path then walk_pages path relative
      else if String.ends_with ~suffix:".md" name then [ relative ]
      else [])
    (entries folder)

let pages book =
  let src = Filename.concat book "src" in
  match walk_pages src "" with
  | names ->
      Ok
        (List.sort String.compare
           (List.filter
              (fun name -> not (String.equal name "SUMMARY.md"))
              names))
  | exception Sys_error reason ->
      Error { file = "src"; line = None; problem = Unreadable reason }

let summary_name = "SUMMARY.md"

let summary_entries targets =
  List.filter_map
    (fun target ->
      if has_scheme target || String.starts_with ~prefix:"//" target then None
      else
        let path, _ = split_anchor target in
        Option.map (String.concat "/") (resolve ~folder:[] path))
    targets

let check_links book =
  let src = Filename.concat book "src" in
  match pages book with
  | Error error -> [ error ]
  | Ok names ->
      let of_pages =
        List.concat_map (fun page -> fst (check_file_links ~src page)) names
      in
      let summary = Filename.concat src summary_name in
      if not (Sys.file_exists summary) then
        { file = "src/SUMMARY.md"; line = None; problem = No_summary }
        :: of_pages
      else
        let errors, targets = check_file_links ~src summary_name in
        let listed = summary_entries targets in
        errors @ of_pages
        @ List.filter_map
            (fun page ->
              if List.mem page listed then None
              else
                Some
                  {
                    file = Filename.concat "src" page;
                    line = None;
                    problem = Not_in_summary;
                  })
            names

let stem page = Filename.remove_extension (Filename.basename page)

let check_listings book =
  let listings = Filename.concat book "listings" in
  if not (Sys.file_exists listings) then []
  else
    match (pages book, entries listings) with
    | exception Sys_error reason ->
        [ { file = "listings"; line = None; problem = Unreadable reason } ]
    | Error error, _ -> [ error ]
    | Ok names, folders ->
        List.filter_map
          (fun folder ->
            let file = "listings/" ^ folder in
            let located problem = Some { file; line = None; problem } in
            if String.starts_with ~prefix:"." folder then None
            else if not (Sys.is_directory (Filename.concat listings folder))
            then located Listing_without_page
            else
              match
                List.filter (fun page -> String.equal (stem page) folder) names
              with
              | [] -> located Listing_without_page
              | [ _ ] -> None
              | several -> located (Listing_for_two_pages several))
          folders

let guarded f =
  try f () with
  | Sys_error reason -> Error (Harness (Fixture.System reason))
  | Unix.Unix_error (code, call, argument) ->
      Error
        (Harness
           (Fixture.System
              (Printf.sprintf "%s %s: %s" call argument
                 (Unix.error_message code))))
  | Fun.Finally_raised failure ->
      Error (Harness (Fixture.System (Printexc.to_string failure)))

let write_into ~root path text =
  let parts = String.split_on_char '/' path in
  let is_link target =
    match (Unix.lstat target).Unix.st_kind with
    | Unix.S_LNK -> true
    | _ -> false
    | exception Unix.Unix_error (Unix.ENOENT, _, _) -> false
  in
  let rec place folder = function
    | [] -> Ok ()
    | [ name ] ->
        let target = Filename.concat folder name in
        if is_link target then Error (Path_outside path)
        else (
          write_file target text;
          Ok ())
    | name :: below ->
        let target = Filename.concat folder name in
        if is_link target then Error (Path_outside path)
        else (
          if not (Sys.file_exists target) then Sys.mkdir target 0o755;
          place target below)
  in
  place root parts

let output_lines output =
  let length = String.length output in
  let rec split start found =
    if start >= length then List.rev found
    else
      match String.index_from_opt output start '\n' with
      | Some stop ->
          split (stop + 1) (String.sub output start (stop - start) :: found)
      | None -> List.rev (String.sub output start (length - start) :: found)
  in
  split 0 []

let representable fence output =
  (String.equal output "" || String.ends_with ~suffix:"\n" output)
  && List.for_all
       (fun line -> not (is_command line || closes fence line))
       (output_lines output)

let split_commands body =
  let rec take found current = function
    | [] -> List.rev (Option.to_list current @ found)
    | line :: below when is_command line ->
        take (Option.to_list current @ found) (Some (command_of line, [])) below
    | line :: below ->
        let current =
          Option.map (fun (command, lines) -> (command, line :: lines)) current
        in
        take found current below
  in
  List.map
    (fun (command, lines) ->
      (command, String.concat "" (List.rev_map (fun line -> line ^ "\n") lines)))
    (take [] None body)

let promoted_body results =
  List.concat_map
    (fun (command, output) -> ("$ " ^ command) :: output_lines output)
    results

let apply_replacements text replacements =
  let lines = Array.of_list (String.split_on_char '\n' text) in
  let buffer = ref [] in
  let index = ref 0 in
  List.iter
    (fun (first, count, body) ->
      for at = !index to first - 1 do
        buffer := lines.(at) :: !buffer
      done;
      buffer := List.rev_append body !buffer;
      index := first + count)
    replacements;
  for at = !index to Array.length lines - 1 do
    buffer := lines.(at) :: !buffer
  done;
  String.concat "\n" (List.rev !buffer)

let make_tool ~tools ~binary =
  Unix.symlink binary (Filename.concat tools "sinter")

let run_block ?bound ~tools repository mode block code =
  let commands = split_commands block.body in
  let last = List.length commands - 1 in
  let settled ~command ~expected actual =
    match mode with
    | Compare ->
        if String.equal expected actual then Ok ()
        else Error (Differs { command; expected; actual })
    | Promote_into _ ->
        if representable block.fence actual then Ok ()
        else Error (Cannot_promote { command; output = actual })
  in
  let rec go index offset results = function
    | [] -> Ok (List.rev results)
    | (command, expected) :: below -> (
        let height = 1 + List.length (output_lines expected) in
        let must = if index = last then code else 0 in
        let outcome =
          match
            Fixture.shell ?bound ~first_on_path:tools repository command
          with
          | Error error -> Error (Harness error)
          | Ok (actual, output) when actual <> must ->
              Error (Wrong_exit { command; expected = must; actual; output })
          | Ok (_, actual) ->
              Result.map (fun () -> actual) (settled ~command ~expected actual)
        in
        match outcome with
        | Error problem -> Error (offset, problem)
        | Ok actual ->
            go (index + 1) (offset + height)
              ((command, actual) :: results)
              below)
  in
  go 0 0 [] commands

let run_blocks ?bound ~tools repository mode items =
  let root = Fixture.root repository in
  let rec walk found = function
    | [] -> Ok (List.rev found)
    | Block ({ label = Writes path; opening; _ } as block) :: below -> (
        let text =
          String.concat "" (List.map (fun line -> line ^ "\n") block.body)
        in
        match write_into ~root path text with
        | Ok () -> walk found below
        | Error problem -> Error (opening + 1, problem))
    | Block ({ label = Runs code; opening; body; _ } as block) :: below -> (
        match run_block ?bound ~tools repository mode block code with
        | Ok results ->
            walk
              ((opening + 1, List.length body, promoted_body results) :: found)
              below
        | Error (offset, problem) -> Error (opening + 2 + offset, problem))
    | _ :: below -> walk found below
  in
  walk [] items

let run_page ?bound ?caller ~binary mode ~book page =
  if Filename.is_relative binary then
    invalid_arg "Book.run_page: the binary is not an absolute path";
  let file = Filename.concat "src" page in
  let located line problem = { file; line = Some line; problem } in
  let whole problem = { file; line = None; problem } in
  let path = Filename.concat (Filename.concat book "src") page in
  let wrapped =
    guarded (fun () ->
        let text = read_file path in
        match parse_page text with
        | Error (line, problem) -> Ok (Error (located line problem))
        | Ok items ->
            let listing =
              Filename.concat (Filename.concat book "listings") (stem page)
            in
            let tree =
              if Sys.file_exists listing && Sys.is_directory listing then
                Some listing
              else None
            in
            Fixture.with_temporary_folder (fun tools ->
                make_tool ~tools ~binary;
                match
                  Fixture.with_new_repository ?caller ?tree (fun repository ->
                      guarded (fun () ->
                          Ok (run_blocks ?bound ~tools repository mode items)))
                with
                | Error error -> Error (Harness error)
                | Ok (Error problem) -> Error problem
                | Ok (Ok (Error (line, problem))) ->
                    Ok (Error (located line problem))
                | Ok (Ok (Ok replacements)) -> (
                    match mode with
                    | Compare -> Ok (Ok [])
                    | Promote_into folder ->
                        let updated = apply_replacements text replacements in
                        if String.equal updated text then Ok (Ok [])
                        else
                          let target = Filename.concat folder page in
                          write_file target updated;
                          Ok (Ok [ target ]))))
  in
  match wrapped with
  | Ok result -> result
  | Error problem -> Error (whole problem)

let tests ~binary mode ~on_write book =
  match pages book with
  | Error error ->
      [
        Alcotest.test_case "pages" `Quick (fun () ->
            Alcotest.fail (message error));
      ]
  | Ok names ->
      let check_list name check =
        Alcotest.test_case name `Quick (fun () ->
            match check book with
            | [] -> ()
            | errors ->
                Alcotest.fail (String.concat "\n" (List.map message errors)))
      in
      check_list "links and the summary" check_links
      :: check_list "listings" check_listings
      :: List.map
           (fun page ->
             Alcotest.test_case page `Quick (fun () ->
                 match run_page ~binary mode ~book page with
                 | Ok written -> List.iter on_write written
                 | Error error -> Alcotest.fail (message error)))
           names
