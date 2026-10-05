(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(* Each node has a number of its own, from 0, which is its index in
   [nodes]. A node has a smaller number than every node that holds it.
   [Class] holds ranges; a single member [c] is [(c, c)].
   [Repeat (body, n, None)] has no upper count. *)
type node = { number : int; shape : shape }

and shape =
  | Literal of char
  | Class of (char * char) list
  | Sequence of node list
  | Alternation of node list
  | Repeat of node * int * int option

type t = { text : string; root : node; nodes : node array }

type error =
  | Not_allowed of { offset : int; character : string }
  | Unclosed_class of int
  | Empty_class of int
  | Bad_range of int
  | Misplaced_hyphen of int
  | Unclosed_group of int
  | Unopened_group of int
  | Empty_group of int
  | Empty_alternative of int
  | Quantifier_without_part of int
  | Two_quantifiers of int
  | Bad_count of int
  | Count_too_large of int
  | Counts_out_of_order of int
  | Matches_empty

let is_printable c = c >= '!' && c <= '~'

let is_literal c =
  is_printable c
  &&
  match c with
  | '\\' | '.' | '[' | ']' | '(' | ')' | '{' | '}' | '*' | '+' | '?' | '|' | '^'
  | '$' ->
      false
  | _ -> true

let is_member c =
  is_printable c && match c with '\\' | '[' | ']' | '^' -> false | _ -> true

let is_digit c = c >= '0' && c <= '9'

type kind = Digit | Upper | Lower | Other

let kind c =
  if is_digit c then Digit
  else if c >= 'A' && c <= 'Z' then Upper
  else if c >= 'a' && c <= 'z' then Lower
  else Other

let character_at text offset =
  let decoded = String.get_utf_8_uchar text offset in
  if Uchar.utf_decode_is_valid decoded then
    String.sub text offset (Uchar.utf_decode_length decoded)
  else String.make 1 text.[offset]

exception Stop of error

(* A recursive descent over [text]. [at] is the offset of the next
   byte to read. *)
let parse text =
  let length = String.length text in
  let at = ref 0 in
  let made = ref [] and count = ref 0 in
  let make shape =
    let node = { number = !count; shape } in
    incr count;
    made := node :: !made;
    node
  in
  let peek () = if !at < length then Some text.[!at] else None in
  let fail error = raise (Stop error) in
  let not_allowed offset =
    fail (Not_allowed { offset; character = character_at text offset })
  in
  let number start =
    let rec digits value =
      match peek () with
      | Some c when is_digit c ->
          incr at;
          let value = (value * 10) + Char.code c - Char.code '0' in
          if value > 255 then fail (Count_too_large start) else digits value
      | _ -> value
    in
    match peek () with
    | Some c when is_digit c -> digits 0
    | _ -> fail (Bad_count start)
  in
  let counts start =
    incr at;
    let low = number start in
    let high =
      match peek () with
      | Some '}' -> Some low
      | Some ',' -> (
          incr at;
          match peek () with Some '}' -> None | _ -> Some (number start))
      | _ -> fail (Bad_count start)
    in
    if peek () <> Some '}' then fail (Bad_count start);
    incr at;
    (match high with
    | Some high when low > high -> fail (Counts_out_of_order start)
    | _ -> ());
    (low, high)
  in
  let quantifier () =
    match peek () with
    | Some '?' ->
        incr at;
        Some (0, Some 1)
    | Some '*' ->
        incr at;
        Some (0, None)
    | Some '+' ->
        incr at;
        Some (1, None)
    | Some '{' -> Some (counts !at)
    | _ -> None
  in
  let rec members start acc =
    match peek () with
    | None -> fail (Unclosed_class start)
    | Some ']' ->
        incr at;
        List.rev acc
    | Some '-' ->
        let first = !at = start + 1 in
        let last = !at + 1 >= length || text.[!at + 1] = ']' in
        if not (first || last) then fail (Misplaced_hyphen !at);
        incr at;
        members start (('-', '-') :: acc)
    | Some c when is_member c ->
        let offset = !at in
        if
          offset + 2 < length
          && text.[offset + 1] = '-'
          && text.[offset + 2] <> ']'
        then begin
          let high = text.[offset + 2] in
          if kind c = Other || kind c <> kind high || c > high then
            fail (Bad_range offset);
          at := offset + 3;
          members start ((c, high) :: acc)
        end
        else begin
          incr at;
          members start ((c, c) :: acc)
        end
    | Some _ -> not_allowed !at
  in
  let rec alternation () =
    let first = sequence () in
    let rec more acc =
      match peek () with
      | Some '|' ->
          incr at;
          more (sequence () :: acc)
      | _ -> List.rev acc
    in
    make (Alternation (more [ first ]))
  and sequence () =
    let rec parts acc =
      match peek () with
      | None | Some '|' | Some ')' -> List.rev acc
      | Some c -> parts (quantified c :: acc)
    in
    match parts [] with
    | [] -> fail (Empty_alternative !at)
    | parts -> make (Sequence parts)
  and quantified c =
    let part = atom c in
    match quantifier () with
    | None -> part
    | Some (low, high) -> (
        let quantified = make (Repeat (part, low, high)) in
        match peek () with
        | Some ('?' | '*' | '+' | '{') -> fail (Two_quantifiers !at)
        | _ -> quantified)
  and atom c =
    let offset = !at in
    match c with
    | '(' -> (
        incr at;
        if peek () = Some ')' then fail (Empty_group offset);
        let inner = alternation () in
        match peek () with
        | Some ')' ->
            incr at;
            inner
        | _ -> fail (Unclosed_group offset))
    | '[' ->
        incr at;
        if peek () = Some ']' then fail (Empty_class offset);
        make (Class (members offset []))
    | '?' | '*' | '+' | '{' -> fail (Quantifier_without_part offset)
    | c when is_literal c ->
        incr at;
        make (Literal c)
    | _ -> not_allowed offset
  in
  let root = alternation () in
  if !at < length then fail (Unopened_group !at);
  (root, Array.of_list (List.rev !made))

let rec nullable node =
  match node.shape with
  | Literal _ | Class _ -> false
  | Sequence nodes -> List.for_all nullable nodes
  | Alternation nodes -> List.exists nullable nodes
  | Repeat (body, low, _) -> low = 0 || nullable body

let of_string text =
  match parse text with
  | exception Stop error -> Error error
  | root, _ when nullable root -> Error Matches_empty
  | root, nodes -> Ok { text; root; nodes }

let to_string pattern = pattern.text

(* A set of places in the id, from 0 to its length, is a list sorted
   upward with no place twice. *)
let rec union a b =
  match (a, b) with
  | [], set | set, [] -> set
  | x :: xs, y :: ys ->
      if x < y then x :: union xs b
      else if y < x then y :: union a ys
      else x :: union xs ys

(* [ends.(number).(start)] is the set of places where a match of the
   node [number] that starts at [start] can end. The table is filled in
   the order of the numbers, so the sets of the parts of a node are
   there before the node needs them. *)
let matches pattern id =
  let length = String.length id in
  let table = Array.make (Array.length pattern.nodes) [||] in
  let ends node start = table.(node.number).(start) in
  let step node from =
    List.fold_left (fun set place -> union set (ends node place)) [] from
  in
  (* Every place that some number of rounds of [body] reaches from a
     place of [from], zero rounds included. Each place is read once. *)
  let closure body from =
    let seen = Array.make (length + 1) false in
    let rec visit = function
      | [] -> ()
      | place :: rest when seen.(place) -> visit rest
      | place :: rest ->
          seen.(place) <- true;
          visit (List.rev_append (ends body place) rest)
    in
    visit from;
    List.filter (fun place -> seen.(place)) (List.init (length + 1) Fun.id)
  in
  let compute node start =
    let one accepts =
      if start < length && accepts id.[start] then [ start + 1 ] else []
    in
    match node.shape with
    | Literal c -> one (Char.equal c)
    | Class ranges ->
        one (fun c -> List.exists (fun (l, h) -> c >= l && c <= h) ranges)
    | Alternation nodes ->
        List.fold_left (fun set n -> union set (ends n start)) [] nodes
    | Sequence nodes ->
        List.fold_left (fun from n -> step n from) [ start ] nodes
    | Repeat (body, low, high) -> (
        (* [after rounds current] is the set after [rounds] more rounds
           of [body]; [from rounds current] joins the sets of the
           rounds from [rounds] to [high]. The next set is a function of
           the current one alone, so a set that comes back unchanged
           stays so for every later round. *)
        let rec after rounds current =
          if rounds = 0 then current else after (rounds - 1) (step body current)
        in
        let first = after low [ start ] in
        match high with
        | None -> closure body first
        | Some high ->
            let rec from rounds current =
              let next = step body current in
              if rounds = high || next = current then current
              else union current (from (rounds + 1) next)
            in
            from low first)
  in
  Array.iter
    (fun node -> table.(node.number) <- Array.init (length + 1) (compute node))
    pattern.nodes;
  String.for_all is_printable id && List.mem length (ends pattern.root 0)

let error_offset = function
  | Matches_empty -> 0
  | Not_allowed { offset; _ } -> offset
  | Unclosed_class offset
  | Empty_class offset
  | Bad_range offset
  | Misplaced_hyphen offset
  | Unclosed_group offset
  | Unopened_group offset
  | Empty_group offset
  | Empty_alternative offset
  | Quantifier_without_part offset
  | Two_quantifiers offset
  | Bad_count offset
  | Count_too_large offset
  | Counts_out_of_order offset ->
      offset

let describe = function
  | "" -> "the pattern holds a character that is not in the id pattern language"
  | character -> (
      let decoded = String.get_utf_8_uchar character 0 in
      let code = Uchar.to_int (Uchar.utf_decode_uchar decoded) in
      if not (Uchar.utf_decode_is_valid decoded) then
        "a byte that is not UTF-8 is not in the id pattern language"
      else if code < 0x20 || (code >= 0x7F && code < 0xA0) then
        "a control character is not in the id pattern language, and no id \
         holds one"
      else if code >= 0xA0 then
        Printf.sprintf "'%s' is not printable ASCII, and no id holds it"
          character
      else if code = 0x20 then
        "a space is not in the id pattern language, and no id holds one"
      else
        match character with
        | "." | "}" ->
            Printf.sprintf
              "'%s' is not in the id pattern language; put it in a class, for \
               example [%s]"
              character character
        | "$" ->
            "'$' is not in the id pattern language; a pattern always matches \
             the whole id"
        | "^" ->
            "'^' is not in the id pattern language; a pattern always matches \
             the whole id, and a class cannot leave characters out"
        | _ ->
            Printf.sprintf
              "'%s' is not in the id pattern language, and no pattern matches \
               it"
              character)

let message = function
  | Not_allowed { character; _ } -> describe character
  | Unclosed_class _ -> "the class has no ']' at its end"
  | Empty_class _ -> "a class holds one or more members"
  | Bad_range _ ->
      "the two ends of a range are both digits, both upper-case letters, or \
       both lower-case letters, and the first end does not come after the \
       second"
  | Misplaced_hyphen _ ->
      "a '-' in a class stands first, last, or between the two ends of a range"
  | Unclosed_group _ -> "the group has no ')' at its end"
  | Unopened_group _ -> "the ')' has no '(' before it"
  | Empty_group _ -> "a group holds a pattern"
  | Empty_alternative _ -> "an alternative of the pattern is empty"
  | Quantifier_without_part _ ->
      "a quantifier stands after a literal, a class, or a group"
  | Two_quantifiers _ -> "a part takes one quantifier at most"
  | Bad_count _ -> "a '{' starts a quantifier {n}, {n,}, or {n,m}"
  | Count_too_large _ -> "a count of a quantifier is from 0 to 255"
  | Counts_out_of_order _ -> "in the quantifier {n,m}, n is not greater than m"
  | Matches_empty -> "the pattern matches an empty id"
