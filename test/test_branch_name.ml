(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

open Sinter_core
module Gen = QCheck2.Gen

(* Each verdict is that of "git check-ref-format refs/heads/<name>",
   from git 2.54.0, except the last entry: git accepts it, and the rule
   that a branch name does not start with "refs/" refuses it. *)
let verdicts =
  [
    ("main", true);
    ("feature/x", true);
    ("a.b", true);
    ("release/1.0", true);
    ("@", true);
    ("a@b", true);
    ("@@", true);
    ("{@", true);
    ("a@{b", false);
    ("@{", false);
    ("a/@{x}", false);
    ("a..b", false);
    ("a/..b", false);
    ("a/.b", false);
    (".a", false);
    ("a/b.lock", false);
    ("a.lock", false);
    ("a.lock/b", false);
    (".lock", false);
    ("a.locks", true);
    ("x.lock.y", true);
    ("a.", false);
    ("a./b", true);
    ("a.b.c", true);
    ("a/", false);
    ("/a", false);
    ("a//b", false);
    ("a b", false);
    ("a~1", false);
    ("a^b", false);
    ("a:b", false);
    ("a?b", false);
    ("a*b", false);
    ("a[b", false);
    ("a\\b", false);
    ("a]b", true);
    ("a{b}", true);
    ("a}b", true);
    ("-a", true);
    ("HEAD", true);
    ("a/refs/b", true);
    ("caf\xc3\xa9", true);
    ("a\x7fb", false);
    ("a\tb", false);
    ("a\000b", false);
    ("a/b/c", true);
    ("refs/heads/x", false);
  ]

let each_verdict_is_that_of_git () =
  List.iter
    (fun (name, expected) ->
      Alcotest.(check bool)
        (Printf.sprintf "%S is a branch name" name)
        expected
        (Result.is_ok (Branch_name.check name)))
    verdicts

let show = function
  | Branch_name.Empty -> "Empty"
  | Full_ref_name -> "Full_ref_name"
  | Bad_character { offset; character } ->
      Printf.sprintf "Bad_character (%d, %C)" offset character
  | Two_dots o -> Printf.sprintf "Two_dots %d" o
  | At_brace o -> Printf.sprintf "At_brace %d" o
  | Empty_component o -> Printf.sprintf "Empty_component %d" o
  | Component_starts_with_dot o ->
      Printf.sprintf "Component_starts_with_dot %d" o
  | Component_ends_with_lock o -> Printf.sprintf "Component_ends_with_lock %d" o
  | Ends_with_dot o -> Printf.sprintf "Ends_with_dot %d" o

let error =
  Alcotest.testable (fun f e -> Format.pp_print_string f (show e)) ( = )

let check_error name expected =
  match Branch_name.check name with
  | Ok () -> Alcotest.failf "%S is a branch name" name
  | Error found ->
      Alcotest.check error
        (Printf.sprintf "the error of %S" name)
        expected found

let each_rule_gives_its_error () =
  check_error "" Branch_name.Empty;
  check_error "refs/heads/main" Branch_name.Full_ref_name;
  check_error "refs/x" Branch_name.Full_ref_name;
  check_error "a~1" (Branch_name.Bad_character { offset = 1; character = '~' });
  check_error "ab c" (Branch_name.Bad_character { offset = 2; character = ' ' });
  check_error "a..b" (Branch_name.Two_dots 1);
  check_error "x/a@{b" (Branch_name.At_brace 3);
  check_error "a//b" (Branch_name.Empty_component 2);
  check_error "/a" (Branch_name.Empty_component 0);
  check_error "a/" (Branch_name.Empty_component 2);
  check_error "a/.b" (Branch_name.Component_starts_with_dot 2);
  check_error "a/b.lock" (Branch_name.Component_ends_with_lock 3);
  check_error "x.lock/b" (Branch_name.Component_ends_with_lock 1);
  check_error "a." (Branch_name.Ends_with_dot 1)

(* git reads the characters of a component before the component as a
   whole, and the components from the start. *)
let the_error_is_the_first_that_git_meets () =
  check_error ".a~" (Branch_name.Bad_character { offset = 2; character = '~' });
  check_error ".." (Branch_name.Two_dots 0);
  check_error "a.lock/~" (Branch_name.Component_ends_with_lock 1);
  check_error "a/.lock" (Branch_name.Component_starts_with_dot 2);
  check_error "refs/~" Branch_name.Full_ref_name

let a_component_of_one_dot_is_an_error () =
  check_error "." (Branch_name.Component_starts_with_dot 0);
  check_error "a/." (Branch_name.Component_starts_with_dot 2)

let error_offset_names_the_place () =
  Alcotest.(check (list int))
    "the offsets"
    [ 0; 0; 1; 1; 3; 2; 2; 3; 1 ]
    (List.map
       (fun name ->
         match Branch_name.check name with
         | Ok () -> Alcotest.failf "%S is a branch name" name
         | Error e -> Branch_name.error_offset e)
       [ ""; "refs/a"; "a~"; "a.."; "x/a@{"; "a//"; "a/.b"; "a/b.lock"; "a." ])

let message name expected =
  match Branch_name.check name with
  | Ok () -> Alcotest.failf "%S is a branch name" name
  | Error e ->
      Alcotest.(check string)
        (Printf.sprintf "the message for %S" name)
        expected (Branch_name.message e)

let each_error_has_its_message () =
  message "" "a branch name cannot be empty";
  message "refs/heads/main"
    "a branch name cannot start with 'refs/'; write the name of the branch \
     alone, such as 'main'";
  message "a b" "a branch name cannot hold a space";
  message "a\tb" "a branch name cannot hold a control character";
  message "a\x7fb" "a branch name cannot hold a control character";
  message "a~1" "a branch name cannot hold '~'";
  message "a..b" "a branch name cannot hold '..'";
  message "a@{b" "a branch name cannot hold '@{'";
  message "a//b"
    "a branch name cannot start or end with '/', or hold two '/' together";
  message "a/.b" "no part of a branch name between two '/' can start with '.'";
  message "a.lock"
    "no part of a branch name between two '/' can end with '.lock'";
  message "a." "a branch name cannot end with '.'"

(* A second reading of the rules, in another form, to compare with the
   module on generated names. *)
let contains text part =
  let n = String.length part in
  let rec from i =
    i + n <= String.length text && (String.sub text i n = part || from (i + 1))
  in
  from 0

let reference name =
  let bad c =
    Char.code c < 0x20 || Char.code c = 0x7f || String.contains " ~^:?*[\\" c
  in
  let component_ok c =
    c <> "" && c.[0] <> '.' && not (String.ends_with ~suffix:".lock" c)
  in
  name <> ""
  && (not (String.starts_with ~prefix:"refs/" name))
  && (not (String.exists bad name))
  && (not (contains name ".."))
  && (not (contains name "@{"))
  && List.for_all component_ok (String.split_on_char '/' name)
  && name.[String.length name - 1] <> '.'

let name =
  Gen.(
    oneof
      [
        string_size
          ~gen:
            (oneof_list
               [ 'a'; '.'; '/'; '@'; '{'; 'l'; 'o'; 'c'; 'k'; '~'; ' ' ])
          (0 -- 10);
        map2 ( ^ )
          (oneof_list [ "refs/"; "ref"; ""; "a/"; "."; "x.lock" ])
          (string_size ~gen:(oneof_list [ 'a'; '.'; '/'; 'k' ]) (0 -- 4));
      ])

let property ?(count = 1000) ~name:test_name ~print generator check =
  QCheck_alcotest.to_alcotest ~speed_level:`Quick
    (QCheck2.Test.make ~count ~name:test_name ~print generator check)

let check_agrees_with_a_second_reading =
  property ~name:"check agrees with a second reading of the rules"
    ~print:QCheck2.Print.string name (fun name ->
      Result.is_ok (Branch_name.check name) = reference name)

let check_answers_any_bytes =
  property ~name:"check answers any bytes, with an offset inside them"
    ~print:QCheck2.Print.string
    Gen.(string_size (0 -- 12))
    (fun name ->
      match Branch_name.check name with
      | Ok () -> reference name
      | Error e ->
          (not (reference name))
          && Branch_name.error_offset e >= 0
          && Branch_name.error_offset e <= String.length name
          && String.length (Branch_name.message e) > 0)

let case name test = Alcotest.test_case name `Quick test

let tests =
  [
    case "each verdict is that of git" each_verdict_is_that_of_git;
    case "each rule gives its error" each_rule_gives_its_error;
    case "the error is the first that git meets"
      the_error_is_the_first_that_git_meets;
    case "a component of one dot is an error" a_component_of_one_dot_is_an_error;
    case "error_offset names the place" error_offset_names_the_place;
    case "each error has its message" each_error_has_its_message;
    check_agrees_with_a_second_reading;
    check_answers_any_bytes;
  ]
