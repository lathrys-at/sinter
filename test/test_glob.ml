(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

open Sinter_core
module Gen = QCheck2.Gen

let glob text =
  match Glob.of_string text with
  | Ok glob -> glob
  | Error error ->
      Alcotest.failf "%S is not a glob: %s" text (Glob.message error)

let matches text path = Glob.matches (glob text) path

let check_match text path expected =
  Alcotest.(check bool)
    (Printf.sprintf "%S against %S" text path)
    expected (matches text path)

let a_glob_matches_from_the_root () =
  check_match "Cargo.lock" "Cargo.lock" true;
  check_match "Cargo.lock" "a/Cargo.lock" false

let a_glob_matches_the_whole_path () =
  check_match "src" "src/a.ts" false;
  check_match "a.ts" "a.ts.orig" false

let a_leading_double_star_matches_at_any_depth () =
  check_match "**/Cargo.lock" "Cargo.lock" true;
  check_match "**/Cargo.lock" "a/b/Cargo.lock" true;
  check_match "**/x.md" "x.md" true;
  check_match "**/x.md" "a/b/x.md" true;
  check_match "**/x.md" "a/b/y.md" false

let a_star_stays_inside_one_name () =
  check_match "src/*.ts" "src/a.ts" true;
  check_match "src/*.ts" "src/a/b.ts" false;
  check_match "*" "a/b" false

let a_star_matches_the_empty_sequence () =
  check_match "a*" "a" true;
  check_match "*a*" "a" true;
  check_match "a*b*c" "abc" true;
  check_match "a*b*c" "axxbyyc" true;
  check_match "a*b*c" "axxbyy" false

let pieces_between_stars_do_not_overlap () =
  check_match "a*a" "a" false;
  check_match "a*a" "aa" true;
  check_match "*b*b" "b" false;
  check_match "*b*b" "bb" true;
  check_match "*ab*b*" "ab" false;
  check_match "*ab*b*" "abb" true;
  check_match "a*b*a" "aba" true;
  check_match "a*b*a" "aa" false;
  check_match "ab*ba" "aba" false;
  check_match "ab*ba" "abba" true

let a_star_goes_back_after_a_false_start () =
  check_match "*ab" "aab" true;
  check_match "*ab" "abab" true;
  check_match "*ab" "abba" false

let a_double_star_in_the_middle_matches_zero_or_more_folders () =
  check_match "a/**/b" "a/b" true;
  check_match "a/**/b" "a/x/b" true;
  check_match "a/**/b" "a/x/y/b" true;
  check_match "a/**/b" "a/x/y/c" false;
  check_match "a/**/**/b" "a/b" true

let a_final_double_star_matches_one_or_more_names () =
  check_match "docs/**" "docs/a.md" true;
  check_match "docs/**" "docs/a/b.md" true;
  check_match "docs/**" "docs" false;
  check_match "**" "a" true;
  check_match "**" "a/b/c" true

let a_final_slash_means_a_final_double_star () =
  check_match "docs/" "docs/a.md" true;
  check_match "docs/" "docs/a/b.md" true;
  check_match "docs/" "docs" false;
  check_match "docs/" "other/a.md" false

let stars_match_names_that_start_with_a_dot () =
  check_match "*" ".gitignore" true;
  check_match "**/*.md" ".plans/a.md" true;
  check_match ".plans/**/*.log.md" ".plans/x/a.log.md" true;
  check_match ".plans/**/*.log.md" ".plans/a.md" false

let case_always_matters () =
  check_match "README.md" "readme.md" false;
  check_match "*.MD" "a.md" false

let every_other_character_matches_itself () =
  check_match "a-b_c+d!e" "a-b_c+d!e" true;
  check_match "a-b_c+d!e" "a-b_c+d!f" false;
  (* "\xc3\xa9" is U+00E9. *)
  check_match "*\xc3\xa9" "caf\xc3\xa9" true

let to_string_gives_the_text_back () =
  Alcotest.(check string)
    "docs/ as written" "docs/"
    (Glob.to_string (glob "docs/"))

let error =
  Alcotest.testable (fun f _ -> Format.pp_print_string f "<error>") ( = )

let check_error text expected =
  match Glob.of_string text with
  | Ok _ -> Alcotest.failf "%S is a glob" text
  | Error found ->
      Alcotest.check error
        (Printf.sprintf "the error of %S" text)
        expected found

let an_empty_glob_is_an_error () = check_error "" Glob.Empty

let a_leading_slash_is_an_error () =
  check_error "/a" Glob.Leading_slash;
  check_error "/" Glob.Leading_slash

let two_slashes_together_are_an_error () =
  check_error "a//b" (Glob.Empty_segment 2);
  check_error "a//" (Glob.Empty_segment 2)

let a_dot_segment_is_an_error () =
  check_error "a/./b" (Glob.Dot_segment { offset = 2; segment = "." });
  check_error "a/../b" (Glob.Dot_segment { offset = 2; segment = ".." });
  check_error "./a" (Glob.Dot_segment { offset = 0; segment = "." })

let a_name_with_dots_is_no_dot_segment () =
  check_match "a/.../b" "a/.../b" true;
  check_match "a/.x" "a/.x" true

let a_double_star_with_other_characters_is_an_error () =
  check_error "src/**.ts"
    (Glob.Double_star_in_segment { offset = 4; segment = "**.ts" });
  check_error "a**"
    (Glob.Double_star_in_segment { offset = 0; segment = "a**" });
  check_error "***"
    (Glob.Double_star_in_segment { offset = 0; segment = "***" })

let forbidden_characters_are_errors () =
  List.iter
    (fun c ->
      check_error (Printf.sprintf "ab%c" c)
        (Glob.Forbidden_character { offset = 2; character = c }))
    [ '?'; '['; ']'; '{'; '}'; '\\' ]

let the_error_is_the_one_at_the_smallest_offset () =
  check_error "a?/[" (Glob.Forbidden_character { offset = 1; character = '?' });
  check_error "x/../?" (Glob.Dot_segment { offset = 2; segment = ".." });
  check_error "?**"
    (Glob.Double_star_in_segment { offset = 0; segment = "?**" })

let a_final_slash_is_no_error () =
  ignore (glob "docs/");
  ignore (glob "**/")

let error_offset_names_the_place () =
  let offset text =
    match Glob.of_string text with
    | Ok _ -> Alcotest.failf "%S is a glob" text
    | Error e -> Glob.error_offset e
  in
  Alcotest.(check (list int))
    "the offsets" [ 0; 0; 2; 2; 4; 3 ]
    (List.map offset [ ""; "/a"; "a//b"; "a/./b"; "src/**.ts"; "abc?" ])

let message text expected =
  match Glob.of_string text with
  | Ok _ -> Alcotest.failf "%S is a glob" text
  | Error e ->
      Alcotest.(check string)
        (Printf.sprintf "the message for %S" text)
        expected (Glob.message e)

let each_error_has_its_message () =
  message "" "a glob cannot be empty";
  message "/a"
    "a glob cannot start with '/'; a glob always matches from the repository \
     root";
  message "a//b" "a glob cannot hold two '/' together";
  message "a/../b" "a glob cannot hold the segment '..'";
  message "a/**x"
    "the segment '**x' holds '**' and other characters; write '**/*x'";
  message "a/**\n"
    "the segment \"**\\n\" holds '**' and other characters; write \"**/*\\n\"";
  message "** x"
    "the segment '** x' holds '**' and other characters; write '**/* x'";
  message "**\127"
    "the segment \"**\\u007F\" holds '**' and other characters; write \
     \"**/*\\u007F\"";
  message "\t**"
    "the segment \"\\t**\" holds '**' and other characters; '**' must be a \
     whole segment, and '*' matches characters inside one name";
  message "src/**.ts"
    "the segment '**.ts' holds '**' and other characters; write '**/*.ts'";
  message "a**"
    "the segment 'a**' holds '**' and other characters; '**' must be a whole \
     segment, and '*' matches characters inside one name";
  message "***"
    "the segment '***' holds '**' and other characters; '**' must be a whole \
     segment, and '*' matches characters inside one name";
  message "**a**"
    "the segment '**a**' holds '**' and other characters; '**' must be a whole \
     segment, and '*' matches characters inside one name";
  message "a?"
    "a glob cannot hold '?'; '*' matches any characters inside one name";
  message "a[" "a glob cannot hold '['; write one glob for each name";
  message "a]" "a glob cannot hold ']'; write one glob for each name";
  message "a{" "a glob cannot hold '{'; write one glob for each choice";
  message "a}" "a glob cannot hold '}'; write one glob for each choice";
  message "a\\" "a glob cannot hold '\\'";
  List.iter
    (fun segment ->
      Alcotest.(check string)
        ("the message for the segment " ^ segment)
        (Printf.sprintf
           "the segment '%s' holds '**' and other characters; '**' must be a \
            whole segment, and '*' matches characters inside one name"
           segment)
        (Glob.message (Glob.Double_star_in_segment { offset = 0; segment })))
    [ "**"; "*"; ""; "a*b" ]

(* A second reading of the rules, written for the test, to compare
   with the module on generated globs and paths. *)
let rec star_match pattern i name j =
  if i = String.length pattern then j = String.length name
  else if pattern.[i] = '*' then
    star_match pattern (i + 1) name j
    || (j < String.length name && star_match pattern i name (j + 1))
  else
    j < String.length name
    && pattern.[i] = name.[j]
    && star_match pattern (i + 1) name (j + 1)

let reference_matches text path =
  let segments = String.split_on_char '/' text in
  let segments =
    match List.rev segments with
    | "" :: rest -> List.rev ("**" :: rest)
    | _ -> segments
  in
  let rec go segments names =
    match (segments, names) with
    | [], [] -> true
    | [], _ :: _ -> false
    | [ "**" ], names -> names <> []
    | "**" :: rest, names -> (
        go rest names
        || match names with [] -> false | _ :: tail -> go segments tail)
    | segment :: rest, name :: tail ->
        star_match segment 0 name 0 && go rest tail
    | _ :: _, [] -> false
  in
  go segments (String.split_on_char '/' path)

let valid_glob =
  Gen.(
    let segment =
      oneof_list
        [
          "**";
          "*";
          "a";
          "b";
          "a*";
          "*b";
          ".a";
          "*a*";
          "ab";
          "a*a";
          "*a*a";
          "*ab*b*";
          "a*b*a";
          "*b*b";
        ]
    in
    map2
      (fun segments final ->
        String.concat "/" segments ^ if final then "/" else "")
      (list_size (1 -- 4) segment)
      bool)

let path =
  Gen.(
    map (String.concat "/")
      (list_size (1 -- 4)
         (oneof_list
            [
              "a";
              "b";
              "ab";
              ".a";
              "ba";
              "aab";
              "bab";
              "aa";
              "aba";
              "abab";
              "abba";
            ])))

let property ?(count = 500) ~name ~print generator check =
  QCheck_alcotest.to_alcotest ~speed_level:`Quick
    (QCheck2.Test.make ~count ~name ~print generator check)

let matches_agrees_with_a_second_reading =
  property ~name:"matches agrees with a second reading of the rules"
    ~print:QCheck2.Print.(pair string string)
    Gen.(pair valid_glob path)
    (fun (text, path) -> matches text path = reference_matches text path)

(* The errors of a string by the rules, each with its offset. On one
   offset, an error of the whole segment comes before an error of one
   character. *)
let reference_error text =
  if text = "" then Some Glob.Empty
  else if text.[0] = '/' then Some Glob.Leading_slash
  else
    let segments = String.split_on_char '/' text in
    let count = List.length segments in
    let errors, _ =
      List.fold_left
        (fun (errors, (index, offset)) segment ->
          let last_empty = index = count - 1 && segment = "" in
          let whole =
            if last_empty then []
            else if segment = "" then [ Glob.Empty_segment offset ]
            else if segment = "." || segment = ".." then
              [ Glob.Dot_segment { offset; segment } ]
            else if
              segment <> "**"
              && List.exists
                   (fun i -> segment.[i] = '*' && segment.[i + 1] = '*')
                   (List.init (max 0 (String.length segment - 1)) Fun.id)
            then [ Glob.Double_star_in_segment { offset; segment } ]
            else []
          in
          let characters =
            List.filter_map
              (fun i ->
                match segment.[i] with
                | ('?' | '[' | ']' | '{' | '}' | '\\') as c ->
                    Some
                      (Glob.Forbidden_character
                         { offset = offset + i; character = c })
                | _ -> None)
              (List.init (String.length segment) Fun.id)
          in
          ( errors @ whole @ characters,
            (index + 1, offset + String.length segment + 1) ))
        ([], (0, 0))
        segments
    in
    match
      List.stable_sort
        (fun a b -> compare (Glob.error_offset a) (Glob.error_offset b))
        errors
    with
    | [] -> None
    | first :: _ -> Some first

let any_glob_text =
  Gen.(
    string_size
      ~gen:(oneof_list [ 'a'; '*'; '/'; '.'; '?'; '{'; '\\'; '!'; '\n' ])
      (0 -- 8))

let of_string_agrees_with_the_rules =
  property ~name:"of_string gives the error at the smallest offset, or a glob"
    ~print:QCheck2.Print.string any_glob_text (fun text ->
      match (Glob.of_string text, reference_error text) with
      | Ok glob, None -> Glob.to_string glob = text
      | Error found, Some expected -> found = expected
      | _ -> false)

let of_string_answers_any_bytes =
  property ~name:"of_string answers any bytes, with an offset inside them"
    ~print:QCheck2.Print.string
    Gen.(string_size (0 -- 20))
    (fun text ->
      match Glob.of_string text with
      | Ok _ -> true
      | Error e ->
          let offset = Glob.error_offset e in
          offset >= 0
          && (offset < String.length text || text = "")
          && String.length (Glob.message e) > 0)

let a_message_is_one_line =
  property ~name:"a message is one line" ~print:QCheck2.Print.string
    any_glob_text (fun text ->
      match Glob.of_string text with
      | Ok _ -> true
      | Error e ->
          let message = Glob.message e in
          not (String.contains message '\n' || String.contains message '\r'))

let matches_answers_any_path =
  property ~name:"matches answers any string as a path"
    ~print:QCheck2.Print.(pair string string)
    Gen.(pair valid_glob (string_size (0 -- 12)))
    (fun (text, path) -> matches text path || true)

(* Path sets. *)

let path_set members =
  match Path_set.of_strings members with
  | Ok set -> set
  | Error _ ->
      Alcotest.failf "not a path set: [%s]" (String.concat "; " members)

let a_path_in_a_plain_glob_is_in_the_set () =
  let set = path_set [ "**/*.md"; "!test/fixtures/" ] in
  Alcotest.(check bool) "a.md" true (Path_set.mem set "a.md");
  Alcotest.(check bool) "docs/a.md" true (Path_set.mem set "docs/a.md")

let an_excluded_glob_takes_paths_out () =
  let set = path_set [ "**/*.md"; "!test/fixtures/" ] in
  Alcotest.(check bool)
    "test/fixtures/a.md" false
    (Path_set.mem set "test/fixtures/a.md")

let a_path_in_no_plain_glob_is_not_in_the_set () =
  let set = path_set [ "**/*.md"; "!test/fixtures/" ] in
  Alcotest.(check bool) "a.ts" false (Path_set.mem set "a.ts")

let the_empty_list_is_the_empty_set () =
  let set = path_set [] in
  Alcotest.(check bool) "is empty" true (Path_set.is_empty set);
  Alcotest.(check bool) "holds no path" false (Path_set.mem set "a");
  Alcotest.(check bool) "empty is empty" true (Path_set.is_empty Path_set.empty);
  Alcotest.(check bool)
    "empty holds no path" false
    (Path_set.mem Path_set.empty "a")

let a_set_with_members_is_not_empty () =
  Alcotest.(check bool) "not empty" false (Path_set.is_empty (path_set [ "a" ]))

let members_keep_their_order_and_form () =
  Alcotest.(check (list string))
    "the members as written" [ "b/"; "!b/c"; "a" ]
    (List.map Path_set.member_to_string
       (Path_set.members (path_set [ "b/"; "!b/c"; "a" ])))

let members_are_plain_or_excluded () =
  match Path_set.members (path_set [ "a"; "!b" ]) with
  | [ Path_set.Plain a; Path_set.Excluded b ] ->
      Alcotest.(check (pair string string))
        "the two globs" ("a", "b")
        (Glob.to_string a, Glob.to_string b)
  | _ -> Alcotest.fail "the members are not one plain and one excluded glob"

let path_set_error =
  Alcotest.testable (fun f _ -> Format.pp_print_string f "<error>") ( = )

let check_errors members expected =
  match Path_set.of_strings members with
  | Ok _ -> Alcotest.failf "[%s] is a path set" (String.concat "; " members)
  | Error found ->
      Alcotest.(check (list path_set_error)) "the errors" expected found

let a_bad_glob_names_its_member_and_start () =
  check_errors [ "a"; "b?"; "!/c" ]
    [
      Path_set.Bad_glob
        {
          index = 1;
          start = 0;
          error = Glob.Forbidden_character { offset = 1; character = '?' };
        };
      Path_set.Bad_glob { index = 2; start = 1; error = Glob.Leading_slash };
    ]

let an_empty_member_is_an_empty_glob () =
  check_errors [ "" ]
    [ Path_set.Bad_glob { index = 0; start = 0; error = Glob.Empty } ]

let a_lone_exclamation_mark_is_an_empty_glob () =
  check_errors [ "a"; "!" ]
    [ Path_set.Bad_glob { index = 1; start = 1; error = Glob.Empty } ]

let a_repeated_member_is_an_error () =
  check_errors [ "a"; "!b"; "a"; "!b" ]
    [
      Path_set.Repeated { index = 2; member = "a" };
      Path_set.Repeated { index = 3; member = "!b" };
    ]

let two_spellings_of_one_glob_are_not_repeated () =
  ignore (path_set [ "docs/"; "docs/**" ])

let only_excluded_globs_is_an_error () =
  check_errors [ "!a"; "!b" ] [ Path_set.No_plain_glob ]

let only_excluded_globs_with_a_bad_one_gives_the_bad_one () =
  check_errors [ "!a"; "!b?" ]
    [
      Path_set.Bad_glob
        {
          index = 1;
          start = 1;
          error = Glob.Forbidden_character { offset = 1; character = '?' };
        };
    ]

let members_gen =
  Gen.(
    list_size (1 -- 4)
      (map2
         (fun bang glob -> if bang then "!" ^ glob else glob)
         bool valid_glob))

let shuffle list =
  List.map (fun x -> (Hashtbl.hash x, x)) list
  |> List.sort compare |> List.map snd

let mem_is_a_plain_match_and_no_excluded_match =
  property ~name:"mem is a match of a plain glob and of no excluded glob"
    ~print:QCheck2.Print.(pair (list string) string)
    Gen.(pair members_gen path)
    (fun (members, path) ->
      match Path_set.of_strings members with
      | Error _ -> true
      | Ok set ->
          let plain, excluded =
            List.partition
              (fun m -> m.[0] <> '!')
              (List.sort_uniq compare members)
          in
          let excluded =
            List.map (fun m -> String.sub m 1 (String.length m - 1)) excluded
          in
          Path_set.mem set path
          = (List.exists (fun g -> reference_matches g path) plain
            && not (List.exists (fun g -> reference_matches g path) excluded)))

let the_order_of_members_does_not_change_the_set =
  property ~name:"the order of the members does not change the set"
    ~print:QCheck2.Print.(pair (list string) string)
    Gen.(pair members_gen path)
    (fun (members, path) ->
      match
        (Path_set.of_strings members, Path_set.of_strings (shuffle members))
      with
      | Ok a, Ok b -> Path_set.mem a path = Path_set.mem b path
      | Error _, Error _ -> true
      | _ -> false)

let of_strings_answers_any_list =
  property ~name:"of_strings answers any list of strings"
    ~print:QCheck2.Print.(list string)
    Gen.(list_size (0 -- 5) any_glob_text)
    (fun members ->
      match Path_set.of_strings members with
      | Ok set -> List.length (Path_set.members set) = List.length members
      | Error errors -> errors <> [])

let case name test = Alcotest.test_case name `Quick test

let tests =
  [
    case "a glob matches from the root" a_glob_matches_from_the_root;
    case "a glob matches the whole path" a_glob_matches_the_whole_path;
    case "a leading double star matches at any depth"
      a_leading_double_star_matches_at_any_depth;
    case "a star stays inside one name" a_star_stays_inside_one_name;
    case "a star matches the empty sequence" a_star_matches_the_empty_sequence;
    case "a star goes back after a false start"
      a_star_goes_back_after_a_false_start;
    case "pieces between stars do not overlap"
      pieces_between_stars_do_not_overlap;
    case "a double star in the middle matches zero or more folders"
      a_double_star_in_the_middle_matches_zero_or_more_folders;
    case "a final double star matches one or more names"
      a_final_double_star_matches_one_or_more_names;
    case "a final slash means a final double star"
      a_final_slash_means_a_final_double_star;
    case "stars match names that start with a dot"
      stars_match_names_that_start_with_a_dot;
    case "case always matters" case_always_matters;
    case "every other character matches itself"
      every_other_character_matches_itself;
    case "to_string gives the text back" to_string_gives_the_text_back;
    case "an empty glob is an error" an_empty_glob_is_an_error;
    case "a leading slash is an error" a_leading_slash_is_an_error;
    case "two slashes together are an error" two_slashes_together_are_an_error;
    case "a dot segment is an error" a_dot_segment_is_an_error;
    case "a name with dots is no dot segment" a_name_with_dots_is_no_dot_segment;
    case "a double star with other characters is an error"
      a_double_star_with_other_characters_is_an_error;
    case "forbidden characters are errors" forbidden_characters_are_errors;
    case "the error is the one at the smallest offset"
      the_error_is_the_one_at_the_smallest_offset;
    case "a final slash is no error" a_final_slash_is_no_error;
    case "error_offset names the place" error_offset_names_the_place;
    case "each error has its message" each_error_has_its_message;
    matches_agrees_with_a_second_reading;
    of_string_agrees_with_the_rules;
    of_string_answers_any_bytes;
    a_message_is_one_line;
    matches_answers_any_path;
    case "a path in a plain glob is in the set"
      a_path_in_a_plain_glob_is_in_the_set;
    case "an excluded glob takes paths out" an_excluded_glob_takes_paths_out;
    case "a path in no plain glob is not in the set"
      a_path_in_no_plain_glob_is_not_in_the_set;
    case "the empty list is the empty set" the_empty_list_is_the_empty_set;
    case "a set with members is not empty" a_set_with_members_is_not_empty;
    case "members keep their order and form" members_keep_their_order_and_form;
    case "members are plain or excluded" members_are_plain_or_excluded;
    case "a bad glob names its member and start"
      a_bad_glob_names_its_member_and_start;
    case "an empty member is an empty glob" an_empty_member_is_an_empty_glob;
    case "a lone exclamation mark is an empty glob"
      a_lone_exclamation_mark_is_an_empty_glob;
    case "a repeated member is an error" a_repeated_member_is_an_error;
    case "two spellings of one glob are not repeated"
      two_spellings_of_one_glob_are_not_repeated;
    case "only excluded globs is an error" only_excluded_globs_is_an_error;
    case "only excluded globs with a bad one gives the bad one"
      only_excluded_globs_with_a_bad_one_gives_the_bad_one;
    mem_is_a_plain_match_and_no_excluded_match;
    the_order_of_members_does_not_change_the_set;
    of_strings_answers_any_list;
  ]
