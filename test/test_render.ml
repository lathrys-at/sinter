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

let render (content, finding, tier) =
  in_files
    [ ("a.md", content); ("b.md", content) ]
    (fun source -> print (fun ppf -> Render.full ppf source ~tier finding))

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
          let rec strip index buffer =
            if index >= String.length styled then Buffer.contents buffer
            else if styled.[index] = '\x1b' then
              strip (String.index_from styled index 'm' + 1) buffer
            else (
              Buffer.add_char buffer styled.[index];
              strip (index + 1) buffer)
          in
          strip 0 (Buffer.create 256)
          = print (fun ppf -> Render.full ppf source ~tier finding)))

let the_output_is_the_same_on_each_run =
  property "the full form is the same on each run" Generators.rendered_finding
    Generators.print_rendered (fun input -> render input = render input)

let tests =
  [
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
