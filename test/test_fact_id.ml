(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

open Sinter_core
module Gen = QCheck2.Gen

let property ?(count = 500) ~name ~print generator check =
  QCheck_alcotest.to_alcotest ~speed_level:`Quick
    (QCheck2.Test.make ~count ~name ~print generator check)

let a_setting_id_joins_the_key_path_with_dots () =
  Alcotest.(check string)
    "one name" "setting:default-branch"
    (Fact_id.setting [ "default-branch" ]);
  Alcotest.(check string)
    "a path" "setting:check.warn-only"
    (Fact_id.setting [ "check"; "warn-only" ])

let a_member_id_adds_the_member_after_an_equals_sign () =
  Alcotest.(check string)
    "a glob" "setting:check.historical=docs/devlog/"
    (Fact_id.member [ "check"; "historical" ] "docs/devlog/");
  Alcotest.(check string)
    "a member that holds = and ." "setting:plan.exempt=a=b.c"
    (Fact_id.member [ "plan"; "exempt" ] "a=b.c")

let a_gate_id_names_the_gate_and_the_class () =
  Alcotest.(check string)
    "a pair" "gate:review/dangling"
    (Fact_id.gate Finding_class.Review Finding_class.Dangling);
  Alcotest.(check string)
    "another pair" "gate:merged/parse-error"
    (Fact_id.gate Finding_class.Merged Finding_class.Parse_error)

let a_tombstone_id_names_the_fact_of_the_base () =
  Alcotest.(check string)
    "a setting" "tombstone:setting:scan.namespaces.jira"
    (Fact_id.tombstone "setting:scan.namespaces.jira")

let a_key_path_that_does_not_parse_is_refused () =
  List.iter
    (fun key ->
      Alcotest.check_raises
        ("setting " ^ String.concat "|" key)
        (Invalid_argument "Fact_id: a key path needs names without '.' and '='")
        (fun () -> ignore (Fact_id.setting key));
      Alcotest.check_raises
        ("member " ^ String.concat "|" key)
        (Invalid_argument "Fact_id: a key path needs names without '.' and '='")
        (fun () -> ignore (Fact_id.member key "x")))
    [ []; [ "" ]; [ "check"; "" ]; [ "a.b" ]; [ "scan"; "a=b" ] ]

let name =
  Gen.string_size
    ~gen:(Gen.oneof_list [ 'a'; 'z'; '-'; '0'; ' ' ])
    (Gen.int_range 1 6)

let a_member_id_parses_from_the_left () =
  property ~name:"a member id parses from the left"
    ~print:(fun (key, value) -> String.concat "." key ^ " = " ^ value)
    Gen.(pair (list_size (int_range 1 5) name) string_printable)
    (fun (key, value) ->
      let id = Fact_id.member key value in
      match String.index_opt id '=' with
      | None -> false
      | Some cut ->
          String.sub id 0 cut = Fact_id.setting key
          && String.sub id (cut + 1) (String.length id - cut - 1) = value)

let tests =
  [
    Alcotest.test_case "a setting id joins the key path with dots" `Quick
      a_setting_id_joins_the_key_path_with_dots;
    Alcotest.test_case "a member id adds the member after an equals sign" `Quick
      a_member_id_adds_the_member_after_an_equals_sign;
    Alcotest.test_case "a gate id names the gate and the class" `Quick
      a_gate_id_names_the_gate_and_the_class;
    Alcotest.test_case "a tombstone id names the fact of the base" `Quick
      a_tombstone_id_names_the_fact_of_the_base;
    Alcotest.test_case "a key path that does not parse is refused" `Quick
      a_key_path_that_does_not_parse_is_refused;
    a_member_id_parses_from_the_left ();
  ]
