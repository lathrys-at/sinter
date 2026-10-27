(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

open Sinter_core
module Gen = QCheck2.Gen

let at line column = { Markdown.line; column }

let place ?(path = "docs/a.md") ?(line = 3) ?(column = 1) ?(stop = 9) () =
  {
    Finding.path;
    span = { Markdown.start = at line column; stop = at line stop };
  }

let fact = Finding.Fact { id = "cites:req:a->b"; ack_name = "b" }

let property ?(count = 500) ~name ~print generator check =
  QCheck_alcotest.to_alcotest ~speed_level:`Quick
    (QCheck2.Test.make ~count ~name ~print generator check)

let subject_ids_have_the_forms_of_the_specification () =
  let check name expected subject =
    Alcotest.(check string) name expected (Finding.subject_id subject)
  in
  check "a fact" "cites:req:a->b" fact;
  check "a file" "file:docs/a.md" (Finding.File "docs/a.md");
  check "an error node" "file:docs/a.md@L3C7"
    (Finding.Error_node { path = "docs/a.md"; position = at 3 7 });
  check "a line" "line:docs/a.md@L12"
    (Finding.Line { path = "docs/a.md"; line = 12 });
  check "a tag" "tag:docs/a@b.md@L2C5"
    (Finding.Tag { path = "docs/a@b.md"; position = at 2 5 })

let the_ack_subject_of_a_fact_is_its_name () =
  Alcotest.(check string) "a fact" "b" (Finding.ack_subject fact);
  Alcotest.(check string)
    "a line" "line:docs/a.md@L12"
    (Finding.ack_subject (Finding.Line { path = "docs/a.md"; line = 12 }));
  Alcotest.(check string)
    "a file" "file:x.md"
    (Finding.ack_subject (Finding.File "x.md"));
  Alcotest.(check string)
    "an error node" "file:x.md@L1C2"
    (Finding.ack_subject
       (Finding.Error_node { path = "x.md"; position = at 1 2 }));
  Alcotest.(check string)
    "a tag" "tag:x.md@L4C3"
    (Finding.ack_subject (Finding.Tag { path = "x.md"; position = at 4 3 }))

let make_keeps_each_part () =
  let finding =
    Finding.make Finding_class.Suspect fact ~place:(place ()) ~detail:"d"
      ~fix:"f" ()
  in
  Alcotest.(check bool)
    "the class" true
    (finding.finding_class = Finding_class.Suspect);
  Alcotest.(check bool) "the subject" true (finding.subject = fact);
  Alcotest.(check bool) "the place" true (finding.place = Some (place ()));
  Alcotest.(check (option string)) "the detail" (Some "d") finding.detail;
  Alcotest.(check (option string)) "the fix" (Some "f") finding.fix;
  let bare = Finding.make Finding_class.Wrong_source fact () in
  Alcotest.(check bool) "no place" true (bare.place = None);
  Alcotest.(check (option string)) "no detail" None bare.detail;
  Alcotest.(check (option string)) "no fix" None bare.fix

let make_refuses_an_empty_text () =
  let refuses name make =
    match make () with
    | (_ : Finding.t) -> Alcotest.failf "%s: no exception" name
    | exception Invalid_argument _ -> ()
  in
  refuses "an empty detail" (fun () ->
      Finding.make Finding_class.Wrong_source fact ~detail:"" ());
  refuses "an empty fix" (fun () ->
      Finding.make Finding_class.Wrong_source fact ~fix:"" ())

let make_escapes_a_detail_and_a_fix () =
  let finding =
    Finding.make Finding_class.Wrong_source fact ~detail:"a\nb" ~fix:"c\rd" ()
  in
  Alcotest.(check (option string)) "the detail" (Some "a\\nb") finding.detail;
  Alcotest.(check (option string)) "the fix" (Some "c\\rd") finding.fix

let escape_writes_each_control_character () =
  Alcotest.(check string)
    "the text" "a\\rb\\nc\\x00d\\x1fe\\x7ff\tg h\xc3\xa9\\x08 ~"
    (Finding.escape "a\rb\nc\x00d\x1fe\x7ff\tg h\xc3\xa9\x08 ~")

let control c = (c < ' ' && c <> '\t') || c = '\x7f'
let any_text = Gen.string_size ~gen:Gen.char (Gen.int_range 0 12)

let escape_leaves_no_control_character_but_the_tab =
  property ~name:"escape leaves no control character but the tab"
    ~print:String.escaped any_text (fun text ->
      not (String.exists control (Finding.escape text)))

let escape_keeps_a_text_with_no_control_character =
  property ~name:"escape keeps a text with no control character"
    ~print:String.escaped any_text (fun text ->
      String.exists control text || String.equal (Finding.escape text) text)

let make_takes_any_text_that_is_not_empty =
  property ~name:"make takes any text that is not empty, as one line"
    ~print:String.escaped any_text (fun text ->
      String.equal text ""
      ||
      let finding =
        Finding.make Finding_class.Wrong_source fact ~detail:text ()
      in
      finding.detail = Some (Finding.escape text))

let the_id_names_the_class_and_the_subject () =
  Alcotest.(check string)
    "a fact" "finding:retired:cites:req:a->b"
    (Finding.id (Finding.make Finding_class.Retired fact ()));
  Alcotest.(check string)
    "a line" "finding:typo-tag:line:docs/a.md@L4"
    (Finding.id
       (Finding.make Finding_class.Typo_tag
          (Finding.Line { path = "docs/a.md"; line = 4 })
          ()))

let ack_cells () =
  let text =
    In_channel.with_open_bin "../spec/algebra.md" In_channel.input_all
  in
  List.filter_map
    (fun line ->
      if String.starts_with ~prefix:"| `" line then
        match
          String.split_on_char '|' line
          |> List.map String.trim
          |> List.filter (fun cell -> cell <> "")
        with
        | name :: _ :: _ :: _ :: ack :: _ ->
            Some (String.sub name 1 (String.length name - 2), ack)
        | _ -> None
      else None)
    (String.split_on_char '\n' text)

let ack_classes () =
  let cells = ack_cells () in
  Alcotest.(check int)
    "a cell for each class"
    (List.length Finding_class.all)
    (List.length cells);
  List.map
    (fun (name, cell) ->
      match Finding_class.of_name name with
      | None -> Alcotest.failf "no class %s" name
      | Some finding_class -> (name, finding_class, cell))
    cells

let ackable_follows_the_column_of_the_specification () =
  List.iter
    (fun (name, finding_class, cell) ->
      let finding = Finding.make finding_class fact () in
      Alcotest.(check bool)
        ("ackable " ^ name) (String.equal cell "A") finding.ackable)
    (ack_classes ())

let only_a_class_of_a_star_takes_ackable () =
  List.iter
    (fun (name, finding_class, cell) ->
      let ackable given =
        match Finding.make finding_class fact ~ackable:given () with
        | finding -> Some finding.ackable
        | exception Invalid_argument _ -> None
      in
      Alcotest.(check (list (option bool)))
        ("ackable " ^ name)
        (if String.equal cell "A*" then [ Some true; Some false ]
         else [ None; None ])
        [ ackable true; ackable false ])
    (ack_classes ())

let subject =
  Gen.oneof
    [
      Gen.map
        (fun id -> Finding.Fact { id; ack_name = id })
        (Gen.oneof_list [ "req:a"; "req:b"; "cites:req:a->b" ]);
      Gen.map
        (fun (line, column) ->
          Finding.Tag { path = "docs/a.md"; position = at line column })
        (Gen.pair (Gen.int_range 1 3) (Gen.int_range 1 3));
    ]

let finding =
  Gen.map
    (fun (finding_class, subject, place) ->
      Finding.make finding_class subject ?place ())
    (Gen.triple
       (Gen.oneof_list Finding_class.all)
       subject
       (Gen.option
          (Gen.map
             (fun (path, line, column) -> place ~path ~line ~column ())
             (Gen.triple
                (Gen.oneof_list [ "a.md"; "b.md"; "a/b.md" ])
                (Gen.int_range 1 3) (Gen.int_range 1 3)))))

let print (finding : Finding.t) =
  Printf.sprintf "%s at %s" (Finding.id finding)
    (match finding.place with
    | None -> "-"
    | Some { path; span } ->
        Printf.sprintf "%s:%d:%d" path span.start.line span.start.column)

let sign n = Int.compare n 0

let compare_is_antisymmetric =
  property ~name:"compare is antisymmetric"
    ~print:(fun (a, b) -> print a ^ " / " ^ print b)
    (Gen.pair finding finding)
    (fun (a, b) -> sign (Finding.compare a b) = -sign (Finding.compare b a))

let compare_is_transitive =
  property ~name:"compare is transitive"
    ~print:(fun (a, b, c) -> String.concat " / " [ print a; print b; print c ])
    (Gen.triple finding finding finding)
    (fun (a, b, c) ->
      (not (Finding.compare a b <= 0 && Finding.compare b c <= 0))
      || Finding.compare a c <= 0)

let start (finding : Finding.t) =
  Option.map
    (fun ({ path; span } : Finding.place) ->
      (path, span.start.line, span.start.column))
    finding.place

let compare_is_zero_only_on_equal_keys =
  property ~name:"compare is zero only on an equal place and id"
    ~print:(fun (a, b) -> print a ^ " / " ^ print b)
    (Gen.pair finding finding)
    (fun (a, b) ->
      Finding.compare a b = 0
      = (start a = start b && String.equal (Finding.id a) (Finding.id b)))

let compare_puts_a_place_before_none =
  property ~name:"compare puts a finding with a place first"
    ~print:(fun (a, b) -> print a ^ " / " ^ print b)
    (Gen.pair finding finding)
    (fun (a, b) ->
      match (a.place, b.place) with
      | Some _, None -> Finding.compare a b < 0
      | None, Some _ -> Finding.compare a b > 0
      | _ -> true)

let compare_orders_by_path_line_column_and_id () =
  let make ?place id =
    Finding.make Finding_class.Dangling
      (Finding.Fact { id; ack_name = id })
      ?place ()
  in
  let findings =
    [
      make "z" ~place:(place ~path:"a.md" ~line:1 ~column:1 ());
      make "a" ~place:(place ~path:"a.md" ~line:1 ~column:2 ());
      make "a" ~place:(place ~path:"a.md" ~line:2 ~column:1 ());
      make "a" ~place:(place ~path:"a.md" ~line:10 ~column:1 ());
      make "a" ~place:(place ~path:"a/b.md" ~line:1 ~column:1 ());
      make "b" ~place:(place ~path:"a/b.md" ~line:1 ~column:1 ());
      make "b.md" ~place:(place ~path:"b.md" ~line:1 ~column:1 ());
      make "a";
      make "b";
    ]
  in
  let sorted = List.sort Finding.compare (List.rev findings) in
  Alcotest.(check (list string))
    "the order" (List.map print findings) (List.map print sorted)

let mark ?(label = "here") start stop = { Finding.start; stop; label }
let related ?place label = { Finding.label; place }

let make_with ?place ?mark ?related () =
  Finding.make Finding_class.Suspect fact ?place ?mark ?related ()

let refuses name message make =
  Alcotest.check_raises name (Invalid_argument message) (fun () ->
      ignore (make () : Finding.t))

let make_keeps_the_mark_and_the_related_places () =
  let finding =
    make_with ~place:(place ())
      ~mark:(mark ~label:"a\tb\nc" 2 4)
      ~related:[ related "x"; related ~place:(place ()) "y\r" ]
      ()
  in
  Alcotest.(check (option (triple int int string)))
    "the mark"
    (Some (2, 4, "a\tb\\nc"))
    (Option.map
       (fun ({ start; stop; label } : Finding.mark) -> (start, stop, label))
       finding.mark);
  Alcotest.(check (list (pair string bool)))
    "the related places"
    [ ("y\\r", true); ("x", false) ]
    (List.map
       (fun ({ label; place } : Finding.related) ->
         (label, Option.is_some place))
       finding.related);
  let bare = make_with () in
  Alcotest.(check bool) "no mark" true (Option.is_none bare.mark);
  Alcotest.(check int) "no related place" 0 (List.length bare.related)

let make_takes_a_mark_at_the_ends_of_the_place () =
  let at_ends =
    make_with ~place:(place ~column:3 ~stop:9 ()) ~mark:(mark 3 9) ()
  in
  Alcotest.(check bool)
    "a mark of the whole line" true
    (Option.is_some at_ends.mark);
  let longer =
    {
      Finding.path = "docs/a.md";
      span = { Markdown.start = at 3 5; stop = at 4 2 };
    }
  in
  let past = make_with ~place:longer ~mark:(mark 5 40) () in
  Alcotest.(check bool)
    "a mark past the stop column of a longer place" true
    (Option.is_some past.mark)

let make_refuses_a_bad_mark () =
  refuses "a mark with no place" "Finding.make: the mark has no place"
    (fun () -> make_with ~mark:(mark 1 2) ());
  refuses "a mark before the place"
    "Finding.make: the mark starts before the place" (fun () ->
      make_with ~place:(place ~column:3 ()) ~mark:(mark 2 4) ());
  refuses "a mark after the place"
    "Finding.make: the mark stops after the place" (fun () ->
      make_with ~place:(place ~stop:9 ()) ~mark:(mark 2 10) ());
  refuses "a mark of no character" "Finding.make: the mark holds no character"
    (fun () -> make_with ~place:(place ()) ~mark:(mark 4 4) ());
  refuses "a mark that stops before it starts"
    "Finding.make: the mark holds no character" (fun () ->
      make_with ~place:(place ()) ~mark:(mark 5 4) ());
  refuses "a mark with an empty label"
    "Finding.make: the label of the mark is empty" (fun () ->
      make_with ~place:(place ()) ~mark:(mark ~label:"" 2 4) ())

let make_refuses_a_bad_related_place () =
  refuses "an empty label" "Finding.make: the label of a related place is empty"
    (fun () ->
      make_with ~related:[ related "a"; related ~place:(place ()) "" ] ());
  refuses "two equal places" "Finding.make: the related place \"a\" comes twice"
    (fun () ->
      make_with
        ~related:
          [
            related ~place:(place ()) "a";
            related "b";
            related ~place:(place ()) "a";
          ]
        ());
  refuses "two equal places in no file"
    "Finding.make: the related place \"a\" comes twice" (fun () ->
      make_with ~related:[ related "a"; related "a" ] ());
  refuses "two labels that are equal once escaped"
    "Finding.make: the related place \"a\\\\nb\" comes twice" (fun () ->
      make_with ~related:[ related "a\nb"; related "a\\nb" ] ())

let make_sorts_the_related_places () =
  let at_place ?path ?line ?column ?stop label =
    related ~place:(place ?path ?line ?column ?stop ()) label
  in
  let expected =
    [
      at_place ~path:"a.md" ~line:1 ~column:1 ~stop:2 "b";
      at_place ~path:"a.md" ~line:1 ~column:1 ~stop:3 "a";
      at_place ~path:"a.md" ~line:1 ~column:2 ~stop:3 "a";
      at_place ~path:"a.md" ~line:2 ~column:1 ~stop:2 "a";
      at_place ~path:"a.md" ~line:10 ~column:1 ~stop:2 "a";
      at_place ~path:"a/b.md" ~line:1 ~column:1 ~stop:2 "a";
      at_place ~path:"a/b.md" ~line:1 ~column:1 ~stop:2 "b";
      at_place ~path:"b.md" ~line:1 ~column:1 ~stop:2 "a";
      related "A";
      related "a";
      related "b";
    ]
  in
  let print ({ label; place } : Finding.related) =
    match place with
    | None -> label
    | Some { path; span } ->
        Printf.sprintf "%s:%d:%d-%d:%d %s" path span.start.line
          span.start.column span.stop.line span.stop.column label
  in
  Alcotest.(check (list string))
    "the order" (List.map print expected)
    (List.map print (make_with ~related:(List.rev expected) ()).related)

let related_place =
  Gen.map2
    (fun label place -> { Finding.label; place })
    (Gen.oneof_list [ "a"; "b"; "a\nb"; "a\\nb"; "\xc3\xa9"; "\x00" ])
    (Gen.option
       (Gen.map
          (fun (path, line, (column, stop)) ->
            place ~path ~line ~column ~stop ())
          (Gen.triple
             (Gen.oneof_list [ "a.md"; "a/b.md"; "b.md" ])
             (Gen.int_range 1 2)
             (Gen.pair (Gen.int_range 1 2) (Gen.int_range 3 4)))))

let print_related related =
  String.concat "; "
    (List.map
       (fun ({ label; place } : Finding.related) ->
         Printf.sprintf "%S%s" label
           (match place with
           | None -> ""
           | Some { path; span } ->
               Printf.sprintf " %s:%d:%d-%d" path span.start.line
                 span.start.column span.stop.column))
       related)

let key ({ label; place } : Finding.related) =
  ( Option.is_none place,
    Option.map
      (fun ({ path; span } : Finding.place) ->
        ( path,
          span.start.line,
          span.start.column,
          span.stop.line,
          span.stop.column ))
      place,
    label )

let escaped ({ label; place } : Finding.related) =
  { Finding.label = Finding.escape label; place }

let make_gives_the_related_places_sorted_and_once =
  property ~name:"make gives the related places sorted, each once, or raises"
    ~print:print_related
    (Gen.list_size (Gen.int_range 0 6) related_place)
    (fun related ->
      let keys = List.map (fun r -> key (escaped r)) related in
      let distinct = List.sort_uniq compare keys in
      match make_with ~related () with
      | finding ->
          let given = List.map key finding.related in
          List.length distinct = List.length keys && given = distinct
      | exception Invalid_argument _ -> List.length distinct < List.length keys)

let neither_the_id_nor_the_order_reads_the_related_places =
  property ~name:"the id and compare do not read the mark or the related places"
    ~print:print_related
    (Gen.list_size (Gen.int_range 0 4) related_place)
    (fun related ->
      let plain = make_with ~place:(place ()) () in
      match make_with ~place:(place ()) ~mark:(mark 2 4) ~related () with
      | finding ->
          String.equal (Finding.id finding) (Finding.id plain)
          && Finding.compare finding plain = 0
      | exception Invalid_argument _ -> true)

let every_label_is_one_line =
  property ~name:"every label is one line with no control character but the tab"
    ~print:String.escaped any_text (fun text ->
      String.equal text ""
      ||
      let finding =
        make_with ~place:(place ()) ~mark:(mark ~label:text 2 4)
          ~related:[ related text; related ~place:(place ()) text ]
          ()
      in
      List.for_all
        (fun label -> not (String.exists control label))
        (Option.fold ~none:[]
           ~some:(fun (m : Finding.mark) -> [ m.label ])
           finding.mark
        @ List.map (fun (r : Finding.related) -> r.label) finding.related))

let first_tag text =
  match Markdown.create (Sinter_bridge.create ()) with
  | Error _ -> Alcotest.fail "the reader does not start"
  | Ok reader ->
      Fun.protect
        ~finally:(fun () -> Markdown.close reader)
        (fun () ->
          match Markdown.read reader text with
          | Ok document -> document.tags.(0)
          | Error _ -> Alcotest.fail "the text gives no document")

let part_marks_a_part_of_a_tag () =
  let tag = first_tag "- @cites \xc3\xa9t\xc3\xa9 v2\n" in
  let show =
    Option.map (fun ({ start; stop; label } : Finding.mark) ->
        (start, stop, label))
  in
  Alcotest.(check (option (triple int int string)))
    "the word"
    (Some (3, 9, "w"))
    (show (Finding.part tag Tag_line.Word "w"));
  Alcotest.(check (option (triple int int string)))
    "the target"
    (Some (10, 13, "t"))
    (show (Finding.part tag Tag_line.Target "t"));
  Alcotest.(check (option (triple int int string)))
    "the revision"
    (Some (14, 16, "r"))
    (show (Finding.part tag Tag_line.Revision "r"));
  Alcotest.(check (option (triple int int string)))
    "no revision" None
    (show (Finding.part (first_tag "@req a\n") Tag_line.Revision "r"))

let case name test = Alcotest.test_case name `Quick test

let tests =
  [
    case "subject ids have the forms of the specification"
      subject_ids_have_the_forms_of_the_specification;
    case "the ack subject of a fact is its name"
      the_ack_subject_of_a_fact_is_its_name;
    case "make keeps each part" make_keeps_each_part;
    case "make refuses an empty text" make_refuses_an_empty_text;
    case "make escapes a detail and a fix" make_escapes_a_detail_and_a_fix;
    case "escape writes each control character"
      escape_writes_each_control_character;
    escape_leaves_no_control_character_but_the_tab;
    escape_keeps_a_text_with_no_control_character;
    make_takes_any_text_that_is_not_empty;
    case "the id names the class and the subject"
      the_id_names_the_class_and_the_subject;
    case "ackable follows the column of the specification"
      ackable_follows_the_column_of_the_specification;
    case "only a class of A* takes ackable" only_a_class_of_a_star_takes_ackable;
    case "compare orders by path, line, column, and id"
      compare_orders_by_path_line_column_and_id;
    compare_is_antisymmetric;
    compare_is_transitive;
    compare_is_zero_only_on_equal_keys;
    compare_puts_a_place_before_none;
    case "part marks a part of a tag" part_marks_a_part_of_a_tag;
    case "make keeps the mark and the related places"
      make_keeps_the_mark_and_the_related_places;
    case "make takes a mark at the ends of the place"
      make_takes_a_mark_at_the_ends_of_the_place;
    case "make refuses a bad mark" make_refuses_a_bad_mark;
    case "make refuses a bad related place" make_refuses_a_bad_related_place;
    case "make sorts the related places" make_sorts_the_related_places;
    make_gives_the_related_places_sorted_and_once;
    neither_the_id_nor_the_order_reads_the_related_places;
    every_label_is_one_line;
  ]
