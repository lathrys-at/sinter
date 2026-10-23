(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

open Sinter_core
module Gen = QCheck2.Gen

let distance = Alcotest.(check int)

let equal_strings_are_at_distance_zero () =
  distance "the same name" 0 (Edit_distance.distance "historical" "historical")

let each_insertion_is_one_edit () =
  distance "tier to tiers" 1 (Edit_distance.distance "tier" "tiers");
  distance "historic to historical" 2
    (Edit_distance.distance "historic" "historical")

let one_swap_of_neighbours_is_one_edit () =
  distance "tiers to teirs" 1 (Edit_distance.distance "tiers" "teirs")

(* The restricted distance of optimal string alignment gives 3 here,
   because it cannot insert between the two characters it swapped. *)
let a_swap_and_an_insertion_between_are_two_edits () =
  distance "ca to abc" 2 (Edit_distance.distance "ca" "abc")

let a_code_point_of_two_bytes_is_one_character () =
  (* "\xc3\xa9" is U+00E9. *)
  distance "e to U+00E9" 1 (Edit_distance.distance "e" "\xc3\xa9");
  distance "U+00E9 to the empty string" 1 (Edit_distance.distance "\xc3\xa9" "")

let a_byte_outside_utf_8_is_one_character () =
  distance "two stray bytes to the empty string" 2
    (Edit_distance.distance "\xff\xfe" "");
  distance "a stray byte to the code point of its value" 1
    (Edit_distance.distance "\xe9" "\xc3\xa9")

(* Every string of at most [n] characters over [alphabet]. *)
let strings alphabet n =
  let rec grow length =
    if length = 0 then [ "" ]
    else
      let shorter = grow (length - 1) in
      shorter
      @ List.concat_map
          (fun s ->
            if String.length s = length - 1 then
              List.map (fun c -> s ^ String.make 1 c) alphabet
            else [])
          shorter
  in
  List.sort_uniq compare (grow n)

(* The smallest number of edits from each string of at most three
   characters of the alphabet, found by a breadth-first search over
   every string of at most four. *)
let edits_by_search alphabet =
  let neighbours s =
    let n = String.length s in
    let cut i j = String.sub s i (j - i) in
    let deletions = List.init n (fun i -> cut 0 i ^ cut (i + 1) n) in
    let insertions =
      List.concat_map
        (fun i ->
          List.map (fun c -> cut 0 i ^ String.make 1 c ^ cut i n) alphabet)
        (List.init (n + 1) Fun.id)
    in
    let substitutions =
      List.concat_map
        (fun i ->
          List.map (fun c -> cut 0 i ^ String.make 1 c ^ cut (i + 1) n) alphabet)
        (List.init n Fun.id)
    in
    let swaps =
      List.init
        (max 0 (n - 1))
        (fun i ->
          cut 0 i
          ^ String.make 1 s.[i + 1]
          ^ String.make 1 s.[i]
          ^ cut (i + 2) n)
    in
    List.filter
      (fun t -> String.length t <= 4)
      (deletions @ insertions @ substitutions @ swaps)
  in
  let table = Hashtbl.create 512 in
  List.iter
    (fun source ->
      let seen = Hashtbl.create 512 in
      Hashtbl.replace seen source 0;
      let queue = Queue.create () in
      Queue.add source queue;
      while not (Queue.is_empty queue) do
        let s = Queue.pop queue in
        let d = Hashtbl.find seen s in
        List.iter
          (fun t ->
            if not (Hashtbl.mem seen t) then begin
              Hashtbl.replace seen t (d + 1);
              Queue.add t queue
            end)
          (neighbours s)
      done;
      Hashtbl.iter
        (fun target d -> Hashtbl.replace table (source, target) d)
        seen)
    (strings alphabet 3);
  table

let the_distance_is_the_smallest_number_of_edits () =
  let alphabet = [ 'a'; 'b'; 'c' ] in
  let table = edits_by_search alphabet in
  let words = strings alphabet 3 in
  List.iter
    (fun a ->
      List.iter
        (fun b ->
          let expected = Hashtbl.find table (a, b) in
          let found = Edit_distance.distance a b in
          if found <> expected then
            Alcotest.failf "distance %S %S is %d; the search finds %d" a b found
              expected)
        words)
    words

let nearest = Alcotest.(check (option string))

let nearest_finds_the_closest_name () =
  nearest "historic finds historical" (Some "historical")
    (Edit_distance.nearest "historic" [ "rollout-cap"; "historical"; "tiers" ])

let nearest_finds_nothing_beyond_two_edits () =
  nearest "abc is three edits from xyz" None
    (Edit_distance.nearest "abc" [ "xyz" ])

let nearest_takes_a_name_at_two_edits () =
  nearest "abcd is two edits from abxy" (Some "abxy")
    (Edit_distance.nearest "abcd" [ "abxy" ]);
  nearest "ab is two insertions from abcd" (Some "abcd")
    (Edit_distance.nearest "ab" [ "abcd" ]);
  nearest "abcd is two deletions from ab" (Some "ab")
    (Edit_distance.nearest "abcd" [ "ab" ]);
  nearest "three characters of two bytes are two deletions from one"
    (Some "\xc3\xa9")
    (Edit_distance.nearest "\xc3\xa9\xc3\xa9\xc3\xa9" [ "\xc3\xa9" ])

let long_names_answer_quickly () =
  distance "a name of 2000 characters and one of 20" 2000
    (Edit_distance.distance (String.make 2000 'x') (String.make 20 'y'));
  nearest "a name of 100000 characters" None
    (Edit_distance.nearest (String.make 100_000 'x')
       [ "check"; "evidence"; "ledger"; "plan"; "scan"; "spec"; "target" ])

let nearest_breaks_a_tie_by_byte_order () =
  nearest "tier is one edit from both" (Some "tied")
    (Edit_distance.nearest "tier" [ "tiers"; "tied" ]);
  nearest "the order of the list does not matter" (Some "tied")
    (Edit_distance.nearest "tier" [ "tied"; "tiers" ])

let nearest_prefers_the_smaller_distance () =
  nearest "warn is nearer to wanr than worn is" (Some "warn")
    (Edit_distance.nearest "wanr" [ "aaaa"; "warn"; "worn" ]);
  nearest "the nearer name wins also when it comes last" (Some "warn")
    (Edit_distance.nearest "wanr" [ "worn"; "aaaa"; "warn" ])

let nearest_of_no_candidates_is_none () =
  nearest "an empty list" None (Edit_distance.nearest "turn" [])

(* Names over a small alphabet, with a code point of two bytes, so
   that two names are often near each other. *)
let name =
  Gen.(
    string_size ~gen:(oneof_list [ 'a'; 'b'; 'c' ]) (0 -- 5)
    |> map (fun s -> String.concat "\xc3\xa9" (String.split_on_char 'c' s)))

let property ?(count = 500) ~name:test_name ~print generator check =
  QCheck_alcotest.to_alcotest ~speed_level:`Quick
    (QCheck2.Test.make ~count ~name:test_name ~print generator check)

let print_pair = QCheck2.Print.(pair string string)
let print_triple = QCheck2.Print.(triple string string string)

let length_in_characters s =
  let rec go i n =
    if i >= String.length s then n
    else go (i + Uchar.utf_decode_length (String.get_utf_8_uchar s i)) (n + 1)
  in
  go 0 0

let distance_is_zero_only_for_equal_names =
  property ~name:"the distance is zero only for equal names" ~print:print_pair
    Gen.(pair name name)
    (fun (a, b) -> Edit_distance.distance a b = 0 = String.equal a b)

let distance_is_symmetric =
  property ~name:"the distance is symmetric" ~print:print_pair
    Gen.(pair name name)
    (fun (a, b) -> Edit_distance.distance a b = Edit_distance.distance b a)

let distance_obeys_the_triangle_inequality =
  property ~name:"the distance obeys the triangle inequality"
    ~print:print_triple
    Gen.(triple name name name)
    (fun (a, b, c) ->
      Edit_distance.distance a c
      <= Edit_distance.distance a b + Edit_distance.distance b c)

let distance_lies_between_the_lengths =
  property
    ~name:
      "the distance lies between the difference and the greater of the lengths"
    ~print:print_pair
    Gen.(pair name name)
    (fun (a, b) ->
      let la = length_in_characters a and lb = length_in_characters b in
      let d = Edit_distance.distance a b in
      abs (la - lb) <= d && d <= max la lb)

(* The nearest name, found by sorting the candidates by distance and
   then by byte order. *)
let nearest_by_sorting name candidates =
  List.map (fun c -> (Edit_distance.distance name c, c)) candidates
  |> List.filter (fun (d, _) -> d <= 2)
  |> List.sort compare
  |> function
  | [] -> None
  | (_, c) :: _ -> Some c

let nearest_agrees_with_a_sort =
  property
    ~name:"nearest gives the first candidate of a sort by distance and bytes"
    ~print:QCheck2.Print.(pair string (list string))
    Gen.(pair name (list_size (0 -- 6) name))
    (fun (n, candidates) ->
      Edit_distance.nearest n candidates = nearest_by_sorting n candidates)

let answers_any_bytes =
  property ~name:"distance answers any two strings and raises nothing"
    ~print:print_pair
    Gen.(pair (string_size (0 -- 16)) (string_size (0 -- 16)))
    (fun (a, b) -> Edit_distance.distance a b >= 0)

let case name test = Alcotest.test_case name `Quick test

let tests =
  [
    case "equal strings are at distance zero" equal_strings_are_at_distance_zero;
    case "each insertion is one edit" each_insertion_is_one_edit;
    case "one swap of neighbours is one edit" one_swap_of_neighbours_is_one_edit;
    case "a swap and an insertion between are two edits"
      a_swap_and_an_insertion_between_are_two_edits;
    case "a code point of two bytes is one character"
      a_code_point_of_two_bytes_is_one_character;
    case "a byte outside UTF-8 is one character"
      a_byte_outside_utf_8_is_one_character;
    case "the distance is the smallest number of edits"
      the_distance_is_the_smallest_number_of_edits;
    case "nearest finds the closest name" nearest_finds_the_closest_name;
    case "nearest finds nothing beyond two edits"
      nearest_finds_nothing_beyond_two_edits;
    case "nearest takes a name at two edits" nearest_takes_a_name_at_two_edits;
    case "nearest breaks a tie by byte order" nearest_breaks_a_tie_by_byte_order;
    case "nearest prefers the smaller distance"
      nearest_prefers_the_smaller_distance;
    case "nearest of no candidates is none" nearest_of_no_candidates_is_none;
    case "long names answer quickly" long_names_answer_quickly;
    distance_is_zero_only_for_equal_names;
    distance_is_symmetric;
    distance_obeys_the_triangle_inequality;
    distance_lies_between_the_lengths;
    nearest_agrees_with_a_sort;
    answers_any_bytes;
  ]
