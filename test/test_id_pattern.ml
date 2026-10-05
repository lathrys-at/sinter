(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

open Sinter_core
module Gen = QCheck2.Gen

let pattern text =
  match Id_pattern.of_string text with
  | Ok pattern -> pattern
  | Error error ->
      Alcotest.failf "%S is not an id pattern: %s" text
        (Id_pattern.message error)

let check_match text id expected =
  Alcotest.(check bool)
    (Printf.sprintf "%S against %S" text id)
    expected
    (Id_pattern.matches (pattern text) id)

let the_github_pattern_matches_issue_numbers () =
  check_match "[1-9][0-9]*" "42" true;
  check_match "[1-9][0-9]*" "1" true;
  check_match "[1-9][0-9]*" "0" false;
  check_match "[1-9][0-9]*" "042" false;
  check_match "[1-9][0-9]*" "4a" false;
  check_match "[1-9][0-9]*" "" false

let the_jira_pattern_matches_jira_keys () =
  check_match "[A-Z]+-[1-9][0-9]*" "PROJ-1" true;
  check_match "[A-Z]+-[1-9][0-9]*" "AB-120" true;
  check_match "[A-Z]+-[1-9][0-9]*" "proj-1" false;
  check_match "[A-Z]+-[1-9][0-9]*" "PROJ-" false

let a_pattern_matches_the_whole_id () =
  check_match "a" "ab" false;
  check_match "b" "ab" false;
  check_match "ab" "ab" true

let alternation_binds_loosest () =
  check_match "ab|c" "ab" true;
  check_match "ab|c" "c" true;
  check_match "ab|c" "ac" false;
  check_match "a(b|c)" "ac" true;
  check_match "x|y|z" "z" true

let quantifiers_count_their_part () =
  check_match "ab?" "a" true;
  check_match "ab?" "ab" true;
  check_match "ab?" "abb" false;
  check_match "ab*" "abbb" true;
  check_match "ab+" "a" false;
  check_match "ab+" "abb" true;
  check_match "a{2}" "aa" true;
  check_match "a{2}" "a" false;
  check_match "a{2}" "aaa" false;
  check_match "a{2,}" "aaaa" true;
  check_match "a{2,}" "a" false;
  check_match "a{1,2}" "aa" true;
  check_match "a{1,2}" "aaa" false;
  check_match "(ab){2}" "abab" true;
  check_match "[ab]{3}" "bab" true;
  check_match "xa{0}" "x" true;
  check_match "xa{0}" "xa" false

let a_part_that_can_match_nothing_still_counts () =
  check_match "x(a?){3}" "x" true;
  check_match "x(a?){3}" "xaaa" true;
  check_match "x(a?){3}" "xaaaa" false;
  check_match "x(a*){2,}" "x" true;
  check_match "x(a?){2,3}y" "xaaay" true;
  check_match "x(a?){2,3}y" "xaaaay" false

let classes_match_their_members () =
  check_match "[.]" "." true;
  check_match "[.]" "a" false;
  check_match "[-a]" "-" true;
  check_match "[a-]" "-" true;
  check_match "[-]" "-" true;
  check_match "[--]" "-" true;
  check_match "[a-c]" "b" true;
  check_match "[a-a]" "a" true;
  check_match "x[-]" "x-" true;
  check_match "[a-c]" "d" false;
  check_match "[A-F0-9]+" "C0FFEE" true;
  check_match "[+*?|$(){}]+" "+*?|$(){}" true

let case_always_matters () =
  check_match "[a-z]+" "ABC" false;
  check_match "abc" "ABC" false

let other_printable_characters_are_literals () =
  check_match "a-b_c/d:e!f#g%h&i'j,k;l<m=n>o@p`q~r\"s"
    "a-b_c/d:e!f#g%h&i'j,k;l<m=n>o@p`q~r\"s" true

let an_id_with_a_space_or_a_control_character_matches_nothing () =
  check_match "a(b|c)*" "a b" false;
  check_match "a(b|c)*" "ab\n" false;
  check_match "[a-z]+" "caf\xc3\xa9" false

let nested_quantifiers_answer_quickly () =
  let id = String.make 60 'a' ^ "c" in
  check_match "((a{0,255}){0,255}){0,255}b" id false;
  check_match "(a|aa)*b" id false;
  check_match "(a*)*b" (String.make 200 'a' ^ "c") false;
  check_match "(a*)*c" (String.make 200 'a' ^ "c") true

let deep_groups_answer_quickly () =
  let deep = String.make 20_000 '(' ^ "a" ^ String.make 20_000 ')' in
  check_match deep "a" true;
  check_match deep "b" false

let to_string_gives_the_text_back () =
  Alcotest.(check string)
    "as written" "[1-9][0-9]*"
    (Id_pattern.to_string (pattern "[1-9][0-9]*"))

let show_error = function
  | Id_pattern.Not_allowed { offset; character } ->
      Printf.sprintf "Not_allowed (%d, %S)" offset character
  | Unclosed_class o -> Printf.sprintf "Unclosed_class %d" o
  | Empty_class o -> Printf.sprintf "Empty_class %d" o
  | Bad_range o -> Printf.sprintf "Bad_range %d" o
  | Misplaced_hyphen o -> Printf.sprintf "Misplaced_hyphen %d" o
  | Unclosed_group o -> Printf.sprintf "Unclosed_group %d" o
  | Unopened_group o -> Printf.sprintf "Unopened_group %d" o
  | Empty_group o -> Printf.sprintf "Empty_group %d" o
  | Empty_alternative o -> Printf.sprintf "Empty_alternative %d" o
  | Quantifier_without_part o -> Printf.sprintf "Quantifier_without_part %d" o
  | Two_quantifiers o -> Printf.sprintf "Two_quantifiers %d" o
  | Bad_count o -> Printf.sprintf "Bad_count %d" o
  | Count_too_large o -> Printf.sprintf "Count_too_large %d" o
  | Counts_out_of_order o -> Printf.sprintf "Counts_out_of_order %d" o
  | Matches_empty -> "Matches_empty"

let error =
  Alcotest.testable (fun f e -> Format.pp_print_string f (show_error e)) ( = )

let check_error text expected =
  match Id_pattern.of_string text with
  | Ok _ -> Alcotest.failf "%S is an id pattern" text
  | Error found ->
      Alcotest.check error
        (Printf.sprintf "the error of %S" text)
        expected found

let not_allowed offset character = Id_pattern.Not_allowed { offset; character }

let characters_outside_the_language_are_errors () =
  check_error "a.b" (not_allowed 1 ".");
  check_error "^a" (not_allowed 0 "^");
  check_error "a$" (not_allowed 1 "$");
  check_error "a\\d" (not_allowed 1 "\\");
  check_error "a b" (not_allowed 1 " ");
  check_error "a\t" (not_allowed 1 "\t");
  check_error "a]" (not_allowed 1 "]");
  check_error "a}" (not_allowed 1 "}");
  check_error "a\xc3\xa9" (not_allowed 1 "\xc3\xa9");
  check_error "a\xff" (not_allowed 1 "\xff")

let characters_outside_a_class_are_errors_in_it () =
  check_error "[^a]" (not_allowed 1 "^");
  check_error "[[]" (not_allowed 1 "[");
  check_error "[a\\]" (not_allowed 2 "\\");
  check_error "[ ]" (not_allowed 1 " ")

let class_errors () =
  check_error "[a" (Id_pattern.Unclosed_class 0);
  check_error "x[" (Id_pattern.Unclosed_class 1);
  check_error "[a-" (Id_pattern.Unclosed_class 0);
  check_error "[a-z" (Id_pattern.Unclosed_class 0);
  check_error "[]" (Id_pattern.Empty_class 0);
  check_error "x[]" (Id_pattern.Empty_class 1)

let range_errors () =
  check_error "[a-Z]" (Id_pattern.Bad_range 1);
  check_error "[z-a]" (Id_pattern.Bad_range 1);
  check_error "[9-0]" (Id_pattern.Bad_range 1);
  check_error "[a-9]" (Id_pattern.Bad_range 1);
  check_error "[!-~]" (Id_pattern.Bad_range 1);
  check_error "[A-z]" (Id_pattern.Bad_range 1);
  check_error "[0-Z]" (Id_pattern.Bad_range 1);
  check_error "[0-z]" (Id_pattern.Bad_range 1);
  check_error "[a--]" (Id_pattern.Bad_range 1);
  check_error "[xa-\\]" (Id_pattern.Bad_range 2)

let a_hyphen_inside_a_class_is_an_error () =
  check_error "[a-c-e]" (Id_pattern.Misplaced_hyphen 4);
  check_error "[---]" (Id_pattern.Misplaced_hyphen 2)

let group_errors () =
  check_error "(a" (Id_pattern.Unclosed_group 0);
  check_error "x(a|b" (Id_pattern.Unclosed_group 1);
  check_error "a)" (Id_pattern.Unopened_group 1);
  check_error "()" (Id_pattern.Empty_group 0)

let empty_alternatives_are_errors () =
  check_error "" (Id_pattern.Empty_alternative 0);
  check_error "a|" (Id_pattern.Empty_alternative 2);
  check_error "|a" (Id_pattern.Empty_alternative 0);
  check_error "(|a)" (Id_pattern.Empty_alternative 1);
  check_error "a||b" (Id_pattern.Empty_alternative 2)

let quantifier_errors () =
  check_error "*a" (Id_pattern.Quantifier_without_part 0);
  check_error "a|+b" (Id_pattern.Quantifier_without_part 2);
  check_error "(?a)" (Id_pattern.Quantifier_without_part 1);
  check_error "{2}" (Id_pattern.Quantifier_without_part 0);
  check_error "a**" (Id_pattern.Two_quantifiers 2);
  check_error "a+?" (Id_pattern.Two_quantifiers 2);
  check_error "a{2}{3}" (Id_pattern.Two_quantifiers 4);
  check_error "a?{3}" (Id_pattern.Two_quantifiers 2)

let count_errors () =
  check_error "a{" (Id_pattern.Bad_count 1);
  check_error "a{}" (Id_pattern.Bad_count 1);
  check_error "a{,2}" (Id_pattern.Bad_count 1);
  check_error "a{2" (Id_pattern.Bad_count 1);
  check_error "a{2,3" (Id_pattern.Bad_count 1);
  check_error "a{2,x}" (Id_pattern.Bad_count 1);
  check_error "a{x}" (Id_pattern.Bad_count 1);
  check_error "a{ 1}" (Id_pattern.Bad_count 1);
  check_error "a{256}" (Id_pattern.Count_too_large 1);
  check_error "a{1,256}" (Id_pattern.Count_too_large 1);
  check_error "a{99999999999999999999}" (Id_pattern.Count_too_large 1);
  check_error "a{3,2}" (Id_pattern.Counts_out_of_order 1)

let counts_up_to_255_are_valid () =
  check_match "a{255}" (String.make 255 'a') true;
  check_match "a{0,255}b" (String.make 255 'a' ^ "b") true;
  check_match "a{0,255}b" (String.make 256 'a' ^ "b") false;
  check_match "a{2,2}" "aa" true

let a_pattern_that_matches_the_empty_id_is_an_error () =
  check_error "a*" Id_pattern.Matches_empty;
  check_error "[0-9]*" Id_pattern.Matches_empty;
  check_error "a?b?" Id_pattern.Matches_empty;
  check_error "a{0}" Id_pattern.Matches_empty;
  check_error "a|b*" Id_pattern.Matches_empty;
  check_error "(a*)+" Id_pattern.Matches_empty

let another_error_comes_before_matching_the_empty_id () =
  check_error "a*." (not_allowed 2 ".")

let error_offset_names_the_place () =
  let offset text =
    match Id_pattern.of_string text with
    | Ok _ -> Alcotest.failf "%S is a pattern" text
    | Error e -> Id_pattern.error_offset e
  in
  Alcotest.(check (list int))
    "the offsets"
    [ 0; 1; 2; 1; 2; 4; 2; 1; 0; 2; 0; 2; 3; 3; 3; 3 ]
    (List.map offset
       [
         "a*";
         "a.";
         "ab[c";
         "a[]";
         "a[c-a]";
         "[a-c-e]";
         "ab(c";
         "a)";
         "()";
         "a|";
         "?a";
         "a+*";
         "abc{";
         "abc{999}";
         "abc{3,1}";
         "abc{9";
       ])

let message text expected =
  match Id_pattern.of_string text with
  | Ok _ -> Alcotest.failf "%S is a pattern" text
  | Error e ->
      Alcotest.(check string)
        (Printf.sprintf "the message for %S" text)
        expected (Id_pattern.message e)

let each_error_has_its_message () =
  message "a.b"
    "'.' is not in the id pattern language; put it in a class, for example [.]";
  message "^a"
    "'^' is not in the id pattern language; a pattern always matches the whole \
     id, and a class cannot leave characters out";
  message "a$"
    "'$' is not in the id pattern language; a pattern always matches the whole \
     id";
  message "a]"
    "']' is not in the id pattern language, and no pattern matches it";
  message "a}"
    "'}' is not in the id pattern language; put it in a class, for example [}]";
  message "a b" "a space is not in the id pattern language, and no id holds one";
  message "a\\d"
    "'\\' is not in the id pattern language, and no pattern matches it";
  message "[^a]"
    "'^' is not in the id pattern language; a pattern always matches the whole \
     id, and a class cannot leave characters out";
  message "a\xc3\xa9" "'\xc3\xa9' is not printable ASCII, and no id holds it";
  message "a\t"
    "a control character is not in the id pattern language, and no id holds one";
  message "a\xc2\x85"
    "a control character is not in the id pattern language, and no id holds one";
  message "a\xc2\xa0" "'\xc2\xa0' is not printable ASCII, and no id holds it";
  Alcotest.(check string)
    "an empty character"
    "the pattern holds a character that is not in the id pattern language"
    (Id_pattern.message (Id_pattern.Not_allowed { offset = 0; character = "" }));
  message "a\x7f"
    "a control character is not in the id pattern language, and no id holds one";
  message "a\xff" "a byte that is not UTF-8 is not in the id pattern language";
  message "[a" "the class has no ']' at its end";
  message "[]" "a class holds one or more members";
  message "[a-Z]"
    "the two ends of a range are both digits, both upper-case letters, or both \
     lower-case letters, and the first end does not come after the second";
  message "[a-c-e]"
    "a '-' in a class stands first, last, or between the two ends of a range";
  message "(a" "the group has no ')' at its end";
  message "a)" "the ')' has no '(' before it";
  message "()" "a group holds a pattern";
  message "a|" "an alternative of the pattern is empty";
  message "*a" "a quantifier stands after a literal, a class, or a group";
  message "a**" "a part takes one quantifier at most";
  message "a{x}" "a '{' starts a quantifier {n}, {n,}, or {n,m}";
  message "a{256}" "a count of a quantifier is from 0 to 255";
  message "a{3,2}" "in the quantifier {n,m}, n is not greater than m";
  message "a*" "the pattern matches an empty id"

(* Patterns built as trees, printed, and matched by a second reading
   of the rules that backtracks. The trees are small, so the
   backtracking ends soon. *)
type tree =
  | Literal of char
  | Class of string list
  | Group of tree
  | Sequence of tree list
  | Alternation of tree list
  | Repeat of tree * int * int option * string

let rec print = function
  | Literal c -> String.make 1 c
  | Class members -> "[" ^ String.concat "" members ^ "]"
  | Group tree -> "(" ^ print tree ^ ")"
  | Sequence trees -> String.concat "" (List.map print_in_sequence trees)
  | Alternation trees -> String.concat "|" (List.map print trees)
  | Repeat (tree, _, _, quantifier) -> print_quantified tree ^ quantifier

and print_in_sequence = function
  | Alternation _ as tree -> "(" ^ print tree ^ ")"
  | tree -> print tree

and print_quantified = function
  | (Literal _ | Class _ | Group _) as tree -> print tree
  | tree -> "(" ^ print tree ^ ")"

let member_matches c member =
  if String.length member = 3 then c >= member.[0] && c <= member.[2]
  else c = member.[0]

let rec reference tree id i k =
  let length = String.length id in
  match tree with
  | Literal c -> i < length && id.[i] = c && k (i + 1)
  | Class members ->
      i < length && List.exists (member_matches id.[i]) members && k (i + 1)
  | Group tree -> reference tree id i k
  | Sequence [] -> k i
  | Sequence (tree :: rest) ->
      reference tree id i (fun j -> reference (Sequence rest) id j k)
  | Alternation trees -> List.exists (fun tree -> reference tree id i k) trees
  | Repeat (tree, low, high, _) -> repeat tree low high 0 id i k

and repeat tree low high count id i k =
  (count >= low && k i)
  || (match high with None -> true | Some high -> count < high)
     && reference tree id i (fun j ->
         (j > i || count < low) && repeat tree low high (count + 1) id j k)

let reference_matches tree id =
  reference tree id 0 (fun j -> j = String.length id)

let quantifier =
  Gen.oneof_list
    [
      (0, Some 1, "?");
      (0, None, "*");
      (1, None, "+");
      (2, Some 2, "{2}");
      (1, None, "{1,}");
      (0, Some 2, "{0,2}");
      (1, Some 3, "{1,3}");
      (0, Some 0, "{0}");
    ]

let tree =
  Gen.(
    sized_size (0 -- 6)
    @@ fix (fun self size ->
        let leaf =
          oneof
            [
              map (fun c -> Literal c) (oneof_list [ 'a'; 'b'; '0'; '-' ]);
              map
                (fun members -> Class members)
                (list_size (1 -- 3)
                   (oneof_list [ "a"; "b"; "0"; "."; "a-b"; "0-1" ]));
            ]
        in
        if size = 0 then leaf
        else
          let smaller = self (size / 2) in
          oneof
            [
              leaf;
              map (fun t -> Group t) smaller;
              map (fun ts -> Sequence ts) (list_size (2 -- 3) smaller);
              map (fun ts -> Alternation ts) (list_size (2 -- 3) smaller);
              map2
                (fun t (low, high, text) -> Repeat (t, low, high, text))
                smaller quantifier;
            ]))

let id =
  Gen.(string_size ~gen:(oneof_list [ 'a'; 'b'; '0'; '1'; '-'; '.' ]) (0 -- 6))

let property ?(count = 300) ~name ~print generator check =
  QCheck_alcotest.to_alcotest ~speed_level:`Quick
    (QCheck2.Test.make ~count ~name ~print generator check)

let print_case (tree, ids) =
  Printf.sprintf "pattern %S, ids [%s]" (print tree)
    (String.concat "; " (List.map (Printf.sprintf "%S") ids))

let matches_agrees_with_a_backtracking_reading =
  property ~name:"matches agrees with a backtracking reading of the rules"
    ~print:print_case
    Gen.(pair tree (list_size (1 -- 8) id))
    (fun (tree, ids) ->
      match Id_pattern.of_string (print tree) with
      | Error Id_pattern.Matches_empty -> reference_matches tree ""
      | Error _ -> false
      | Ok pattern ->
          (not (reference_matches tree ""))
          && List.for_all
               (fun id ->
                 Id_pattern.matches pattern id = reference_matches tree id)
               ids)

let any_pattern_text =
  Gen.(
    string_size
      ~gen:
        (oneof_list
           [
             'a';
             '0';
             '-';
             '[';
             ']';
             '(';
             ')';
             '|';
             '*';
             '+';
             '?';
             '{';
             '}';
             ',';
             '2';
             '^';
             '.';
             ' ';
           ])
      (0 -- 10))

let of_string_answers_any_text =
  property ~count:1000
    ~name:"of_string answers any text, with an offset inside it"
    ~print:QCheck2.Print.string any_pattern_text (fun text ->
      match Id_pattern.of_string text with
      | Ok pattern -> Id_pattern.to_string pattern = text
      | Error e ->
          let offset = Id_pattern.error_offset e in
          offset >= 0
          && offset <= String.length text
          && String.length (Id_pattern.message e) > 0)

let of_string_answers_any_bytes =
  property ~name:"of_string answers any bytes" ~print:QCheck2.Print.string
    Gen.(string_size (0 -- 12))
    (fun text -> match Id_pattern.of_string text with Ok _ | Error _ -> true)

let matches_answers_any_id =
  property ~name:"matches answers any id"
    ~print:QCheck2.Print.(pair string string)
    Gen.(
      pair
        (oneof_list [ "[1-9][0-9]*"; "(a|b)+"; "x{0,3}y" ])
        (string_size (0 -- 12)))
    (fun (text, id) ->
      match Id_pattern.matches (pattern text) id with _ -> true)

let case name test = Alcotest.test_case name `Quick test

let tests =
  [
    case "the GitHub pattern matches issue numbers"
      the_github_pattern_matches_issue_numbers;
    case "the Jira pattern matches Jira keys" the_jira_pattern_matches_jira_keys;
    case "a pattern matches the whole id" a_pattern_matches_the_whole_id;
    case "alternation binds loosest" alternation_binds_loosest;
    case "quantifiers count their part" quantifiers_count_their_part;
    case "a part that can match nothing still counts"
      a_part_that_can_match_nothing_still_counts;
    case "classes match their members" classes_match_their_members;
    case "case always matters" case_always_matters;
    case "other printable characters are literals"
      other_printable_characters_are_literals;
    case "an id with a space or a control character matches nothing"
      an_id_with_a_space_or_a_control_character_matches_nothing;
    case "nested quantifiers answer quickly" nested_quantifiers_answer_quickly;
    case "deep groups answer quickly" deep_groups_answer_quickly;
    case "to_string gives the text back" to_string_gives_the_text_back;
    case "characters outside the language are errors"
      characters_outside_the_language_are_errors;
    case "characters outside a class are errors in it"
      characters_outside_a_class_are_errors_in_it;
    case "class errors" class_errors;
    case "range errors" range_errors;
    case "a hyphen inside a class is an error"
      a_hyphen_inside_a_class_is_an_error;
    case "group errors" group_errors;
    case "empty alternatives are errors" empty_alternatives_are_errors;
    case "quantifier errors" quantifier_errors;
    case "count errors" count_errors;
    case "counts up to 255 are valid" counts_up_to_255_are_valid;
    case "a pattern that matches the empty id is an error"
      a_pattern_that_matches_the_empty_id_is_an_error;
    case "another error comes before matching the empty id"
      another_error_comes_before_matching_the_empty_id;
    case "error_offset names the place" error_offset_names_the_place;
    case "each error has its message" each_error_has_its_message;
    matches_agrees_with_a_backtracking_reading;
    of_string_answers_any_text;
    of_string_answers_any_bytes;
    matches_answers_any_id;
  ]
