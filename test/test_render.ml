(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

open Sinter_core

let case name f = Alcotest.test_case name `Quick f

let property ?(count = 300) name gen print f =
  QCheck_alcotest.to_alcotest ~speed_level:`Quick
    (QCheck2.Test.make ~count ~name ~print gen f)

let write folder name content =
  let path = Filename.concat folder name in
  (match Filename.dirname name with
  | "." -> ()
  | dir -> (
      try Unix.mkdir (Filename.concat folder dir) 0o755
      with Unix.Unix_error (Unix.EEXIST, _, _) -> ()));
  Out_channel.with_open_bin path (fun channel -> output_string channel content)

let print ?(renderer = `None) f =
  let buffer = Buffer.create 256 in
  let ppf = Format.formatter_of_buffer buffer in
  Style.prepare ppf renderer;
  f ppf;
  Format.pp_print_flush ppf ();
  Buffer.contents buffer

let rec printable text offset =
  offset >= String.length text
  ||
  let decoded = String.get_utf_8_uchar text offset in
  let code = Uchar.to_int (Uchar.utf_decode_uchar decoded) in
  Uchar.utf_decode_is_valid decoded
  && (code = 0x0a
     || not
          (code < 0x20
          || (code >= 0x7f && code <= 0x9f)
          || (code >= 0x202a && code <= 0x202e)
          || (code >= 0x2066 && code <= 0x2069)))
  && printable text (offset + Uchar.utf_decode_length decoded)

let strip styled =
  let buffer = Buffer.create 256 in
  let rec walk index =
    if index < String.length styled then
      if styled.[index] = '\x1b' then
        walk (String.index_from styled index 'm' + 1)
      else (
        Buffer.add_char buffer styled.[index];
        walk (index + 1))
  in
  walk 0;
  Buffer.contents buffer

let in_files files f =
  Fixture.with_temporary_folder (fun root ->
      List.iter (fun (name, content) -> write root name content) files;
      f (Source.create ~root))

let full ?renderer ?(files = [ ("a.md", "") ]) ?tier finding =
  in_files files (fun source ->
      print ?renderer (fun ppf -> Render.full ppf source ~tier finding))

let at line column = { Markdown.line; column }

let place ?(path = "a.md") (line, column) (eline, ecol) =
  {
    Finding.path;
    span = { Markdown.start = at line column; stop = at eline ecol };
  }

let subject = Finding.Line { path = "a.md"; line = 1 }

let untraced ?mark ?(detail = "nothing satisfies req:x") ~place () =
  Finding.make Finding_class.Untraced subject ~place ~detail ?mark ()

let lines text = String.split_on_char '\n' text

let check_lines name expected actual =
  Alcotest.(check (list string)) name expected (lines actual)

let doc = "# A\n\n@req x\n"

let a_block_shows_the_headline_the_location_and_the_mark () =
  check_lines "the block at a gate"
    [
      "warn[untraced]: nothing satisfies req:x";
      " --> a.md:3:1";
      "  |";
      "3 | @req x";
      "  |      ^ nothing satisfies it";
      "  |";
      "";
    ]
    (full
       ~files:[ ("a.md", doc) ]
       ~tier:Finding_class.Warn
       (untraced
          ~place:(place (3, 1) (3, 7))
          ~mark:{ Finding.start = 6; stop = 7; label = "nothing satisfies it" }
          ()));
  check_lines "the block with no gate, no mark, and no detail"
    [
      "dangling"; " --> a.md:3:1"; "  |"; "3 | @req x"; "  | ^^^^^^"; "  |"; "";
    ]
    (full
       ~files:[ ("a.md", doc) ]
       (Finding.make Finding_class.Dangling subject
          ~place:(place (3, 1) (3, 7))
          ()))

let the_headline_names_the_tier_and_the_class () =
  check_lines "a blocking finding with no place"
    [ "block[untraced]: d"; "" ]
    (full ~tier:Finding_class.Block
       (Finding.make Finding_class.Untraced subject ~detail:"d" ()))

let a_place_of_more_than_one_line_shows_its_first_line () =
  check_lines "the block"
    [
      "unplanned-change: d";
      " --> a.md:2:1";
      "  |";
      "2 | first";
      "  | ^^^^^";
      "...";
      "  |";
      "";
    ]
    (full
       ~files:[ ("a.md", "x\nfirst\nsecond\n") ]
       (Finding.make Finding_class.Unplanned_change subject ~detail:"d"
          ~place:(place (2, 1) (3, 7))
          ()))

let a_place_on_an_empty_line_has_a_mark_of_width_1 () =
  check_lines "the block"
    [ "unplanned-change"; " --> a.md:2:1"; "  |"; "2 |"; "  | ^"; "  |"; "" ]
    (full
       ~files:[ ("a.md", "a\n\nb\n") ]
       (Finding.make Finding_class.Unplanned_change subject
          ~place:(place (2, 1) (2, 1))
          ()))

let the_gutter_takes_the_width_of_the_line_number () =
  check_lines "the block"
    [
      "dangling";
      "  --> a.md:10:2";
      "   |";
      "10 | @cites y";
      "   |  ^^^^^^^";
      "   |";
      "";
    ]
    (full
       ~files:[ ("a.md", String.make 9 '\n' ^ "@cites y\n") ]
       (Finding.make Finding_class.Dangling subject
          ~place:(place (10, 2) (10, 9))
          ()))

let a_place_with_no_source_shows_no_snippet () =
  let finding ?mark path =
    Finding.make Finding_class.Dangling subject
      ~place:(place ~path (3, 1) (3, 6))
      ?mark ()
  in
  let shown files finding = full ~files finding in
  Alcotest.(check (list string))
    "a missing file, a line past the end, text that is not UTF-8, and a mark \
     past its line"
    [
      "dangling\n --> missing.md:3:1\n";
      "dangling\n --> a.md:3:1\n";
      "dangling\n --> b.md:3:1\n";
      "dangling\n --> c.md:3:1\n";
    ]
    [
      shown [] (finding "missing.md");
      shown [ ("a.md", "one\ntwo\n") ] (finding "a.md");
      shown [ ("b.md", "\n\n@x\xff\n") ] (finding "b.md");
      shown
        [ ("c.md", "\n\n@x\n") ]
        (finding "c.md" ~mark:{ Finding.start = 3; stop = 5; label = "l" });
    ]

let a_mark_stands_under_the_display_width_before_it () =
  check_lines "wide characters and an emoji"
    [
      "dangling";
      " --> a.md:1:6";
      "  |";
      "1 | \xe6\x97\xa5\xe6\x9c\xac\xe8\xaa\x9e \xf0\x9f\xa6\x80@cites \
       \xe6\x97\xa5\xe6\x9c\xac";
      "  |          ^^^^^^ l";
      "  |";
      "";
    ]
    (full
       ~files:
         [
           ( "a.md",
             "\xe6\x97\xa5\xe6\x9c\xac\xe8\xaa\x9e \xf0\x9f\xa6\x80@cites \
              \xe6\x97\xa5\xe6\x9c\xac\n" );
         ]
       (Finding.make Finding_class.Dangling subject
          ~place:(place (1, 6) (1, 15))
          ~mark:{ Finding.start = 6; stop = 12; label = "l" }
          ()));
  check_lines "a tab and a control character"
    [
      "dangling";
      " --> a.md:1:1";
      "  |";
      "1 |     \xef\xbf\xbd@cites x";
      "  |             ^ l";
      "  |";
      "";
    ]
    (full
       ~files:[ ("a.md", "\t\x1b@cites x\n") ]
       (Finding.make Finding_class.Dangling subject
          ~place:(place (1, 1) (1, 11))
          ~mark:{ Finding.start = 10; stop = 11; label = "l" }
          ()))

let no_line_ends_in_a_space () =
  check_lines "a source line and a label with spaces at their ends"
    [
      "dangling: d";
      " --> a.md:1:1";
      "  |";
      "1 | @cites x";
      "  | ^^^^^^^^^^ l";
      "  |";
      "";
    ]
    (full
       ~files:[ ("a.md", "@cites x  \n") ]
       (Finding.make Finding_class.Dangling subject ~detail:"d  "
          ~place:(place (1, 1) (1, 11))
          ~mark:{ Finding.start = 1; stop = 11; label = "l " }
          ()))

let related ?(path = "a.md") label start stop =
  { Finding.label; place = Some (place ~path start stop) }

let related_places_in_the_file_share_its_snippet () =
  check_lines "a place on an earlier line, and one on the line of the finding"
    [
      "duplicate: d";
      " --> a.md:6:1";
      "  |";
      "3 | @req x";
      "  | ------ first declared here";
      "...";
      "6 | @req x y";
      "  |      ^ declared again here";
      "  |        - here too";
      "7 | @req z";
      "  | ------ next";
      "  |";
      "";
    ]
    (full
       ~files:[ ("a.md", "# A\n\n@req x\n@req y\n\n@req x y\n@req z\n") ]
       (Finding.make Finding_class.Duplicate subject ~detail:"d"
          ~place:(place (6, 1) (6, 9))
          ~mark:{ Finding.start = 6; stop = 7; label = "declared again here" }
          ~related:
            [
              related "first declared here" (3, 1) (3, 7);
              related "here too" (6, 8) (6, 9);
              related "next" (7, 1) (7, 7);
            ]
          ()))

let related_places_in_other_files_get_their_own_blocks () =
  check_lines "two places in one file, a missing file, and a note"
    [
      "suspect: d";
      "  --> a.md:1:1";
      "   |";
      " 1 | @cites x v1";
      "   |          ^^ names v1";
      "   |";
      "  ::: b.md:5:1";
      "   |";
      " 5 | @req x v2";
      "   | --------- now at v2";
      "...";
      "10 | @req y";
      "   | ------ also";
      "...";
      "   |";
      "  ::: c.md:1:1";
      "   = note: on another branch";
      "";
    ]
    (full
       ~files:
         [
           ("a.md", "@cites x v1\n");
           ("b.md", "\n\n\n\n@req x v2\n\n\n\n\n@req y\nmore\n");
         ]
       (Finding.make Finding_class.Suspect subject ~detail:"d"
          ~place:(place (1, 1) (1, 12))
          ~mark:{ Finding.start = 10; stop = 12; label = "names v1" }
          ~related:
            [
              related ~path:"b.md" "now at v2" (5, 1) (5, 10);
              related ~path:"b.md" "also" (10, 1) (11, 5);
              related ~path:"c.md" "gone" (1, 1) (1, 3);
              { Finding.label = "on another branch"; place = None };
            ]
          ()))

let a_finding_with_no_place_shows_its_related_places () =
  check_lines "the block"
    [
      "cycle";
      " ::: a.md:1:1";
      "  |";
      "1 | @req x";
      "  | ------ part of the cycle";
      "  |";
      "";
    ]
    (full
       ~files:[ ("a.md", "@req x\n") ]
       (Finding.make Finding_class.Cycle subject
          ~related:[ related "part of the cycle" (1, 1) (1, 7) ]
          ()))

let fixed ?(path = "a.md") text ?(index = 0) fix =
  let tag = (Edits.document text).tags.(index) in
  Finding.make Finding_class.Suspect subject ~detail:"d"
    ~place:{ Finding.path; span = tag.span }
    ~fix:(fix (Edits.document text) tag)
    ()

let a_replacement_shows_the_old_and_the_new_line () =
  let text = "# A\n\n@cites x v1\n" in
  check_lines "the block"
    [
      "suspect: d";
      " --> a.md:3:1";
      "  |";
      "3 | @cites x v1";
      "  | ^^^^^^^^^^^";
      "  |";
      "help: check that the citation still holds, then pin it to the current \
       revision";
      "  |";
      "3 - @cites x v1";
      "3 + @cites x v2";
      "  |";
      "";
    ]
    (full ~files:[ ("a.md", text) ] (fixed text (fun _ tag -> Fix.pin tag 2)))

let an_insertion_marks_the_inserted_columns () =
  let text = "# A\n\n@satisfies \xe6\x97\xa5\xe6\x9c\xac\n" in
  check_lines "the block"
    [
      "suspect: d";
      " --> a.md:3:1";
      "  |";
      "3 | @satisfies \xe6\x97\xa5\xe6\x9c\xac";
      "  | ^^^^^^^^^^^^^^^";
      "  |";
      "help: pin the citation to the revision of the declaration";
      "  |";
      "3 | @satisfies \xe6\x97\xa5\xe6\x9c\xac v1";
      "  |                +++";
      "  |";
      "";
    ]
    (full ~files:[ ("a.md", text) ] (fixed text (fun _ tag -> Fix.pin tag 1)))

let an_ack_shows_an_inserted_line () =
  let text = "# A\n\n@cites x\n@cites y\n" in
  let hash = String.sub (Edits.document text).blocks.(0).hash 0 8 in
  check_lines "the block"
    [
      "suspect: d";
      " --> a.md:3:1";
      "  |";
      "3 | @cites x";
      "  | ^^^^^^^^";
      "  |";
      "help: if the citation still holds, accept the finding with an @ack line";
      "  |";
      "5 + @ack retired x " ^ hash;
      "  |";
      "";
    ]
    (full
       ~files:[ ("a.md", text) ]
       (fixed text (fun document _ -> Fix.ack document ~block:0 ~target:"x")))

let each_alternative_gets_a_diff () =
  let text = "# A\n\n@cites x v1\n" in
  check_lines "the block"
    [
      "suspect: d";
      " --> a.md:3:1";
      "  |";
      "3 | @cites x v1";
      "  | ^^^^^^^^^^^";
      "  |";
      "help: cite one of the successors in place of the retired item";
      "  |";
      "3 - @cites x v1";
      "3 + @cites b v2";
      "  |";
      "3 - @cites x v1";
      "3 + @cites c v1";
      "  |";
      "";
    ]
    (full
       ~files:[ ("a.md", text) ]
       (fixed text (fun _ tag -> Fix.successors tag ("b", 2) [ ("c", 1) ])))

let a_fix_without_its_line_shows_its_text () =
  let text = "# A\n\n@cites x v1\n" in
  check_lines "the block of a file that changed"
    [
      "suspect: d";
      " --> a.md:3:1";
      "help: check that the citation still holds, then pin it to the current \
       revision";
      "  fix: @cites x v2";
      "";
    ]
    (full
       ~files:[ ("a.md", "# A\n") ]
       (fixed text (fun _ tag -> Fix.pin tag 2)))

let fixes_of text =
  let document = Edits.document text in
  let tag = document.tags.(0) in
  [
    Fix.word tag "req";
    Fix.pin tag 2;
    Fix.bump tag 2;
    Fix.spelling tag "b";
    Fix.rename tag "b" 2;
    Fix.successors tag ("b", 2) [ ("c", 1) ];
    Fix.plan_id tag (Plan_target.derive ~base:"" ~path:"");
    Fix.ack document ~block:0 ~target:"a";
  ]

let lines_of text =
  List.map
    (fun line ->
      if String.ends_with ~suffix:"\r" line then
        String.sub line 0 (String.length line - 1)
      else line)
    (String.split_on_char '\n' text)

let printed text =
  let cleaned = Display.clean text in
  let rec stop n = if n > 0 && cleaned.[n - 1] = ' ' then stop (n - 1) else n in
  String.sub cleaned 0 (stop (String.length cleaned))

let rec sections = function
  | [] -> []
  | "  |" :: rest -> (
      let rec take taken = function
        | line :: rest when not (String.equal line "  |") ->
            take (line :: taken) rest
        | rest -> (List.rev taken, rest)
      in
      match take [] rest with
      | [], rest | _, ([] as rest) -> sections rest
      | section, rest -> section :: sections rest)
  | _ :: rest -> sections rest

let new_line row =
  if String.length row = 0 || row.[0] < '0' || row.[0] > '9' then None
  else if
    String.length row >= 4
    && (String.sub row 1 3 = " + " || String.sub row 1 3 = " | ")
  then Some (String.sub row 4 (String.length row - 4))
  else if
    String.length row = 3
    && (String.sub row 1 2 = " +" || String.sub row 1 2 = " |")
  then Some ""
  else None

let a_diff_shows_the_line_with_the_edits_applied =
  property "a diff shows the line with the edits of each alternative applied"
    Generators.tag_block String.escaped (fun text ->
      let tag = (Edits.document text).tags.(0) in
      List.for_all
        (fun fix ->
          let finding =
            Finding.make Finding_class.Suspect subject
              ~place:{ Finding.path = "a.md"; span = tag.span }
              ~fix ()
          in
          let block = full ~files:[ ("a.md", text) ] finding in
          let after_help =
            let rec drop = function
              | line :: rest when String.starts_with ~prefix:"help:" line ->
                  rest
              | _ :: rest -> drop rest
              | [] -> []
            in
            drop (lines block)
          in
          let shown_alternatives =
            List.map (List.filter_map new_line) (sections after_help)
          in
          let expected =
            List.map
              (fun (edits : Fix.edit list) ->
                let first = List.hd edits in
                let extra =
                  List.fold_left
                    (fun count (edit : Fix.edit) ->
                      count
                      + List.length (String.split_on_char '\n' edit.text)
                      - 1)
                    0 edits
                in
                let applied =
                  Array.of_list (lines_of (Edits.apply text edits))
                in
                let anchor = (Array.of_list (lines_of text)).(first.line - 1) in
                let fresh =
                  List.init (extra + 1) (fun k -> applied.(first.line - 1 + k))
                in
                List.map printed
                  (match fresh with
                  | first :: (_ :: _ as rest) when String.equal first anchor ->
                      rest
                  | lines -> lines))
              (Fix.alternatives fix)
          in
          let shown_marks =
            List.map
              (List.filter (String.starts_with ~prefix:"  | "))
              (sections after_help)
          in
          let expected_marks =
            List.map
              (fun (edits : Fix.edit list) ->
                let first = List.hd edits in
                let inserts =
                  List.for_all
                    (fun (edit : Fix.edit) ->
                      edit.col = edit.ecol
                      && not (String.contains edit.text '\n'))
                    edits
                in
                if not inserts then []
                else
                  let line =
                    (Array.of_list (lines_of (Edits.apply text edits))).(first
                                                                           .line
                                                                         - 1)
                  in
                  let prefix count =
                    let rec walk offset count =
                      if count <= 0 || offset >= String.length line then offset
                      else
                        walk
                          (offset
                          + Uchar.utf_decode_length
                              (String.get_utf_8_uchar line offset))
                          (count - 1)
                    in
                    String.sub line 0 (walk 0 count)
                  in
                  let row, _, _ =
                    List.fold_left
                      (fun (row, column, shift) (edit : Fix.edit) ->
                        let start =
                          Display.width (prefix (edit.col - 1 + shift))
                        in
                        let size = max 1 (Display.width edit.text) in
                        ( row
                          ^ String.make (start - column) ' '
                          ^ String.make size '+',
                          start + size,
                          shift + Display.length edit.text ))
                      ("  | ", 0, 0) edits
                  in
                  [ row ])
              (Fix.alternatives fix)
          in
          shown_alternatives = expected && shown_marks = expected_marks)
        (fixes_of text))

let brief ?renderer ?tier finding =
  print ?renderer (fun ppf -> Render.brief ppf ~tier finding)

let the_brief_form_is_one_line_and_a_fix_line () =
  let text = "# A\n\n@cites x v1\n" in
  Alcotest.(check (list string))
    "a finding at a gate with a fix, one with no gate and no detail, one with \
     no place, and a path with a control character"
    [
      "a.md:3:1: block[suspect] d\n  fix: @cites x v2\n";
      "a.md:3:1: dangling\n";
      "-:-:-: warn[untraced] nothing satisfies req:x\n";
      "a\xef\xbf\xbdb.md:1:2: dangling\n";
    ]
    [
      brief ~tier:Finding_class.Block (fixed text (fun _ tag -> Fix.pin tag 2));
      brief
        (Finding.make Finding_class.Dangling subject
           ~place:(place (3, 1) (3, 7))
           ());
      brief ~tier:Finding_class.Warn
        (Finding.make Finding_class.Untraced subject
           ~detail:"nothing satisfies req:x" ());
      brief
        (Finding.make Finding_class.Dangling subject
           ~place:(place ~path:"a\x1bb.md" (1, 2) (1, 3))
           ());
    ]

let a_folded_line_counts_the_findings_of_a_file () =
  let finding ?(path = "spec/ledger.md") () =
    Finding.make Finding_class.Untraced subject ~detail:"d"
      ~place:(place ~path (24, 1) (24, 20))
      ()
  in
  Alcotest.(check (list string))
    "the full form at a gate and without one, the brief form, and both with no \
     place"
    [
      "warn[untraced]: 24 findings in spec/ledger.md\n";
      "untraced: 3 findings in a\xef\xbf\xbdb.md\n";
      "spec/ledger.md:24:1: warn[untraced] 24 findings in this file\n";
      "spec/ledger.md:24:1: untraced 2 findings in this file\n";
      "untraced: 2 findings\n";
      "-:-:-: untraced 2 findings in this file\n";
    ]
    [
      print (fun ppf ->
          Render.folded_full ppf ~tier:(Some Finding_class.Warn) (finding ()) 24);
      print (fun ppf ->
          Render.folded_full ppf ~tier:None (finding ~path:"a\x1bb.md" ()) 3);
      print (fun ppf ->
          Render.folded_brief ppf ~tier:(Some Finding_class.Warn) (finding ())
            24);
      print (fun ppf -> Render.folded_brief ppf ~tier:None (finding ()) 2);
      print (fun ppf ->
          Render.folded_full ppf ~tier:None
            (Finding.make Finding_class.Untraced subject ())
            2);
      print (fun ppf ->
          Render.folded_brief ppf ~tier:None
            (Finding.make Finding_class.Untraced subject ())
            2);
    ]

let parse_location line =
  match String.index_opt line ' ' with
  | None -> None
  | Some space -> (
      let location = String.sub line 0 space in
      let rest = String.sub line (space + 1) (String.length line - space - 1) in
      let word =
        match String.index_opt rest ' ' with
        | Some space -> String.sub rest 0 space
        | None -> rest
      in
      let tier, name =
        match String.index_opt word '[' with
        | Some open_ when String.ends_with ~suffix:"]" word ->
            ( Some (String.sub word 0 open_),
              String.sub word (open_ + 1) (String.length word - open_ - 2) )
        | _ -> (None, word)
      in
      match List.rev (String.split_on_char ':' location) with
      | "" :: column :: line :: path ->
          Some (String.concat ":" (List.rev path), line, column, tier, name)
      | _ -> None)

let the_brief_form_parses_back =
  property "the brief form gives one line, one more for a fix, and parses back"
    Generators.rendered_finding Generators.print_rendered
    (fun (_, (finding : Finding.t), tier) ->
      let text = brief ?tier finding in
      let expected =
        match finding.place with
        | Some { path; span } ->
            ( path,
              string_of_int span.start.line,
              string_of_int span.start.column )
        | None -> ("-", "-", "-")
      in
      match lines text with
      | first :: rest ->
          let path, line, column = expected in
          parse_location first
          = Some
              ( path,
                line,
                column,
                Option.map Finding_class.tier_name tier,
                Finding_class.name finding.finding_class )
          && List.length rest
             = 1 + Option.fold ~none:0 ~some:(fun _ -> 1) finding.fix
          && List.for_all
               (fun line ->
                 line = "" || String.starts_with ~prefix:"  fix: " line)
               rest
          && printable text 0
          && List.for_all
               (fun line -> not (String.ends_with ~suffix:" " line))
               (lines text)
      | [] -> false)

let the_brief_form_with_styles_is_the_plain_form =
  property
    "the brief form, styled and without its escape codes, is the plain form"
    Generators.rendered_finding Generators.print_rendered
    (fun (_, finding, tier) ->
      strip (brief ~renderer:`Ansi_tty ?tier finding) = brief ?tier finding)

let render (content, finding, tier) =
  in_files
    [ ("a.md", content); ("b.md", content) ]
    (fun source -> print (fun ppf -> Render.full ppf source ~tier finding))

let rendering_never_raises_and_prints_no_control_character =
  property
    "the full form never raises, and prints no control character but the line \
     feed"
    Generators.rendered_finding Generators.print_rendered (fun input ->
      let text = render input in
      printable text 0
      && String.ends_with ~suffix:"\n" text
      && List.for_all
           (fun line -> not (String.ends_with ~suffix:" " line))
           (lines text))

let first_characters text count =
  let rec walk offset count =
    if count <= 0 || offset >= String.length text then offset
    else
      walk
        (offset + Uchar.utf_decode_length (String.get_utf_8_uchar text offset))
        (count - 1)
  in
  String.sub text 0 (walk 0 count)

let a_mark_starts_at_the_width_of_the_printed_text_before_it =
  property "a mark starts at the width of the printed text before it"
    Generators.rendered_finding Generators.print_rendered
    (fun ((content, (finding : Finding.t), _) as input) ->
      match (finding.place, finding.mark) with
      | Some { path = "a.md"; span }, Some mark -> (
          let source = Line_index.make content in
          let text = render input in
          let digits = String.length (string_of_int span.start.line) in
          let prefix = String.make (digits + 1) ' ' ^ "| " in
          let shown =
            String.is_valid_utf_8 content
            && span.start.line <= Line_index.count source
            &&
            let last =
              Display.length (Line_index.content source span.start.line) + 1
            in
            mark.start <= last && mark.stop <= last
          in
          match
            List.find_opt
              (fun line ->
                String.starts_with ~prefix line
                && String.contains line '^'
                && String.for_all
                     (fun c -> c = ' ')
                     (String.sub line (String.length prefix)
                        (String.index line '^' - String.length prefix)))
              (lines text)
          with
          | None -> not shown
          | Some line ->
              let raw = Line_index.content source span.start.line in
              let before =
                Display.width
                  (Display.clean (first_characters raw (mark.start - 1)))
              in
              let marks = String.index line '^' - String.length prefix in
              let rec run index =
                if index < String.length line && line.[index] = '^' then
                  run (index + 1)
                else index
              in
              shown && marks = before
              && run (String.index line '^') > String.index line '^')
      | _ -> true)

let styles_change_no_character =
  property "styled output, without its escape codes, is the plain output"
    Generators.rendered_finding Generators.print_rendered
    (fun (content, finding, tier) ->
      in_files
        [ ("a.md", content); ("b.md", content) ]
        (fun source ->
          let styled =
            print ~renderer:`Ansi_tty (fun ppf ->
                Render.full ppf source ~tier finding)
          in
          strip styled = print (fun ppf -> Render.full ppf source ~tier finding)))

let the_output_is_the_same_on_each_run =
  property "the full form is the same on each run" Generators.rendered_finding
    Generators.print_rendered (fun input -> render input = render input)

let a_warning_and_a_note_are_one_line_each () =
  Alcotest.(check (list string))
    "a warning, a cleaned warning, an empty warning, and a note"
    [
      "warning: no ledger\n";
      "warning: a\xef\xbf\xbdb    c\n";
      "warning:\n";
      "note: base abc\n";
    ]
    [
      print (fun ppf -> Render.warning ppf "no ledger");
      print (fun ppf -> Render.warning ppf "a\027b\tc ");
      print (fun ppf -> Render.warning ppf "");
      print (fun ppf -> Render.note ppf "base abc");
    ]

let a_warning_and_a_note_take_their_styles () =
  Alcotest.(check (list string))
    "the word in its style, and the text plain"
    [ "\x1b[1m\x1b[33mwarning:\x1b[0;1m\x1b[0m x\n"; "\x1b[1mnote:\x1b[0m x\n" ]
    [
      print ~renderer:`Ansi_tty (fun ppf -> Render.warning ppf "x");
      print ~renderer:`Ansi_tty (fun ppf -> Render.note ppf "x");
    ]

let tests =
  [
    case "a warning and a note are one line each"
      a_warning_and_a_note_are_one_line_each;
    case "a warning and a note take their styles"
      a_warning_and_a_note_take_their_styles;
    case "a block shows the headline, the location, and the mark"
      a_block_shows_the_headline_the_location_and_the_mark;
    case "the headline names the tier and the class"
      the_headline_names_the_tier_and_the_class;
    case "a place of more than one line shows its first line"
      a_place_of_more_than_one_line_shows_its_first_line;
    case "a place on an empty line has a mark of width 1"
      a_place_on_an_empty_line_has_a_mark_of_width_1;
    case "the gutter takes the width of the line number"
      the_gutter_takes_the_width_of_the_line_number;
    case "a place with no source shows no snippet"
      a_place_with_no_source_shows_no_snippet;
    case "a mark stands under the display width before it"
      a_mark_stands_under_the_display_width_before_it;
    case "no line ends in a space" no_line_ends_in_a_space;
    case "a replacement shows the old and the new line"
      a_replacement_shows_the_old_and_the_new_line;
    case "an insertion marks the inserted columns"
      an_insertion_marks_the_inserted_columns;
    case "an ack shows an inserted line" an_ack_shows_an_inserted_line;
    case "each alternative gets a diff" each_alternative_gets_a_diff;
    case "a fix without its line shows its text"
      a_fix_without_its_line_shows_its_text;
    a_diff_shows_the_line_with_the_edits_applied;
    case "the brief form is one line and a fix line"
      the_brief_form_is_one_line_and_a_fix_line;
    the_brief_form_parses_back;
    case "a folded line counts the findings of a file"
      a_folded_line_counts_the_findings_of_a_file;
    the_brief_form_with_styles_is_the_plain_form;
    case "related places in the file share its snippet"
      related_places_in_the_file_share_its_snippet;
    case "related places in other files get their own blocks"
      related_places_in_other_files_get_their_own_blocks;
    case "a finding with no place shows its related places"
      a_finding_with_no_place_shows_its_related_places;
    rendering_never_raises_and_prints_no_control_character;
    a_mark_starts_at_the_width_of_the_printed_text_before_it;
    styles_change_no_character;
    the_output_is_the_same_on_each_run;
  ]
