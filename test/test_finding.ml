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
  let bare = Finding.make Finding_class.Orphan fact () in
  Alcotest.(check bool) "no place" true (bare.place = None);
  Alcotest.(check (option string)) "no detail" None bare.detail;
  Alcotest.(check (option string)) "no fix" None bare.fix

let make_refuses_a_text_that_is_not_one_line () =
  let refuses name make =
    match make () with
    | (_ : Finding.t) -> Alcotest.failf "%s: no exception" name
    | exception Invalid_argument _ -> ()
  in
  refuses "an empty detail" (fun () ->
      Finding.make Finding_class.Orphan fact ~detail:"" ());
  refuses "a detail with a line feed" (fun () ->
      Finding.make Finding_class.Orphan fact ~detail:"a\nb" ());
  refuses "a detail with a carriage return" (fun () ->
      Finding.make Finding_class.Orphan fact ~detail:"a\rb" ());
  refuses "an empty fix" (fun () ->
      Finding.make Finding_class.Orphan fact ~fix:"" ());
  refuses "a fix with a line feed" (fun () ->
      Finding.make Finding_class.Orphan fact ~fix:"a\n" ());
  refuses "a fix with a carriage return" (fun () ->
      Finding.make Finding_class.Orphan fact ~fix:"\rb" ())

let the_id_names_the_class_and_the_subject () =
  Alcotest.(check string)
    "a fact" "finding:disendorsed:cites:req:a->b"
    (Finding.id (Finding.make Finding_class.Disendorsed fact ()));
  Alcotest.(check string)
    "a line" "finding:typo-tag:line:docs/a.md@L4"
    (Finding.id
       (Finding.make Finding_class.Typo_tag
          (Finding.Line { path = "docs/a.md"; line = 4 })
          ()))

(* The cell of the column A of each row of the table of built-in
   finding classes in algebra.md, as dune copies it beside the build
   copy of test/. *)
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

let ackable_follows_the_column_of_the_specification () =
  let cells = ack_cells () in
  Alcotest.(check int)
    "a cell for each class"
    (List.length Finding_class.all)
    (List.length cells);
  List.iter
    (fun (name, cell) ->
      match Finding_class.of_name name with
      | None -> Alcotest.failf "no class %s" name
      | Some finding_class ->
          let ackable = Finding.ackable (Finding.make finding_class fact ()) in
          (* A* is ackable only under a condition of the rule, which a
             finding of the class carries in no field yet. *)
          Alcotest.(check bool)
            ("ackable " ^ name) (String.equal cell "A") ackable)
    cells

(* {1 The order} *)

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

let property ?(count = 500) ~name ~print generator check =
  QCheck_alcotest.to_alcotest ~speed_level:`Quick
    (QCheck2.Test.make ~count ~name ~print generator check)

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

let case name test = Alcotest.test_case name `Quick test

let tests =
  [
    case "subject ids have the forms of the specification"
      subject_ids_have_the_forms_of_the_specification;
    case "the ack subject of a fact is its name"
      the_ack_subject_of_a_fact_is_its_name;
    case "make keeps each part" make_keeps_each_part;
    case "make refuses a text that is not one line"
      make_refuses_a_text_that_is_not_one_line;
    case "the id names the class and the subject"
      the_id_names_the_class_and_the_subject;
    case "ackable follows the column of the specification"
      ackable_follows_the_column_of_the_specification;
    case "compare orders by path, line, column, and id"
      compare_orders_by_path_line_column_and_id;
    compare_is_antisymmetric;
    compare_is_transitive;
    compare_is_zero_only_on_equal_keys;
    compare_puts_a_place_before_none;
  ]
