(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

type node =
  | Literal of char
  | Class of (char * char) list
  | Sequence of node list
  | Alternation of node list
  | Repeat of { body : node; low : int; high : int option; copies : int }

type state = Char of (char * char) list * int | Split of int * int | Accept
type t = { text : string; program : state array; start : int }

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
  | Too_large

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

let parse text =
  let length = String.length text in
  let at = ref 0 in
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
        Some (0, Some 1, 1)
    | Some '*' ->
        incr at;
        Some (0, None, 1)
    | Some '+' ->
        incr at;
        Some (1, None, 1)
    | Some '{' -> (
        match counts !at with
        | low, (Some high as bound) -> Some (low, bound, max 1 high)
        | low, None -> Some (low, None, low + 1))
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
    match more [ first ] with [ one ] -> one | many -> Alternation many
  and sequence () =
    let rec parts acc =
      match peek () with
      | None | Some '|' | Some ')' -> List.rev acc
      | Some c -> parts (quantified c :: acc)
    in
    match parts [] with
    | [] -> fail (Empty_alternative !at)
    | parts -> Sequence parts
  and quantified c =
    let part = atom c in
    match quantifier () with
    | None -> part
    | Some (low, high, copies) -> (
        let quantified = Repeat { body = part; low; high; copies } in
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
        Class (members offset [])
    | '?' | '*' | '+' | '{' -> fail (Quantifier_without_part offset)
    | c when is_literal c ->
        incr at;
        Literal c
    | _ -> not_allowed offset
  in
  let root = alternation () in
  if !at < length then fail (Unopened_group !at);
  root

let rec nullable = function
  | Literal _ | Class _ -> false
  | Sequence nodes -> List.for_all nullable nodes
  | Alternation nodes -> List.exists nullable nodes
  | Repeat { body; low; _ } -> low = 0 || nullable body

let largest = 1_000

let rec size = function
  | Literal _ | Class _ -> 1
  | Sequence nodes | Alternation nodes ->
      List.fold_left
        (fun total node -> min (largest + 1) (total + size node))
        0 nodes
  | Repeat { body; copies; _ } -> min (largest + 1) (size body * copies)

let compile root =
  let states = Dynarray.create () in
  let add state =
    Dynarray.add_last states state;
    Dynarray.length states - 1
  in
  let rec build node next =
    match node with
    | Literal c -> add (Char ([ (c, c) ], next))
    | Class ranges -> add (Char (ranges, next))
    | Sequence nodes -> List.fold_right build nodes next
    | Alternation nodes -> (
        match List.rev nodes with
        | [] -> next
        | last :: earlier ->
            List.fold_left
              (fun other node -> add (Split (build node next, other)))
              (build last next) earlier)
    | Repeat { body; low; high = Some high; _ } ->
        let rec optional count =
          if count = 0 then next
          else
            let rest = optional (count - 1) in
            add (Split (build body rest, rest))
        in
        repeat body low (optional (high - low))
    | Repeat { body; low; high = None; _ } ->
        let loop = add Accept in
        let entry = build body loop in
        Dynarray.set states loop (Split (entry, next));
        if low = 0 then loop else repeat body (low - 1) entry
  and repeat body count next =
    if count = 0 then next else build body (repeat body (count - 1) next)
  in
  let start = build root (add Accept) in
  (Dynarray.to_array states, start)

let of_string text =
  match parse text with
  | exception Stop error -> Error error
  | root when size root > largest -> Error Too_large
  | root when nullable root -> Error Matches_empty
  | root ->
      let program, start = compile root in
      Ok { text; program; start }

let to_string pattern = pattern.text

let matches pattern id =
  let program = pattern.program in
  let seen = Array.make (Array.length program) (-1) in
  let rec close round state found =
    if seen.(state) = round then found
    else begin
      seen.(state) <- round;
      match program.(state) with
      | Split (first, second) -> close round second (close round first found)
      | Char _ | Accept -> state :: found
    end
  in
  let length = String.length id in
  let rec run position states =
    if position = length then
      List.exists
        (fun state -> match program.(state) with Accept -> true | _ -> false)
        states
    else
      let c = id.[position] in
      match
        List.fold_left
          (fun found state ->
            match program.(state) with
            | Char (ranges, next)
              when List.exists (fun (low, high) -> c >= low && c <= high) ranges
              ->
                close (position + 1) next found
            | Char _ | Split _ | Accept -> found)
          [] states
      with
      | [] -> false
      | states -> run (position + 1) states
  in
  String.for_all is_printable id && run 0 (close 0 pattern.start [])

let error_offset = function
  | Matches_empty | Too_large -> 0
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
  | "" ->
      ( "the pattern holds a character that is not in the id pattern language",
        None )
  | character -> (
      let decoded = String.get_utf_8_uchar character 0 in
      let code = Uchar.to_int (Uchar.utf_decode_uchar decoded) in
      if not (Uchar.utf_decode_is_valid decoded) then
        ("a byte that is not UTF-8 is not in the id pattern language", None)
      else if code < 0x20 || (code >= 0x7F && code < 0xA0) then
        ( "a control character is not in the id pattern language, and no id \
           holds one",
          None )
      else if code >= 0xA0 then
        ( Printf.sprintf "'%s' is not printable ASCII, and no id holds it"
            character,
          None )
      else if code = 0x20 then
        ("a space is not in the id pattern language, and no id holds one", None)
      else
        match character with
        | "." | "}" ->
            ( Printf.sprintf "'%s' is not in the id pattern language" character,
              Some
                (Printf.sprintf "put it in a class, for example [%s]" character)
            )
        | "$" ->
            ( "'$' is not in the id pattern language",
              Some "remove it, since a pattern always matches the whole id" )
        | "^" ->
            ( "'^' is not in the id pattern language",
              Some
                "remove it, since a pattern always matches the whole id, and a \
                 class cannot leave characters out" )
        | _ ->
            ( Printf.sprintf
                "'%s' is not in the id pattern language, and no pattern \
                 matches it"
                character,
              None ))

let parts = function
  | Not_allowed { character; _ } -> describe character
  | Unclosed_class _ -> ("the class has no ']' at its end", None)
  | Empty_class _ -> ("a class holds one or more members", None)
  | Bad_range _ ->
      ( "the two ends of a range are both digits, both upper-case letters, or \
         both lower-case letters, and the first end does not come after the \
         second",
        None )
  | Misplaced_hyphen _ ->
      ( "a '-' in a class stands first, last, or between the two ends of a range",
        None )
  | Unclosed_group _ -> ("the group has no ')' at its end", None)
  | Unopened_group _ -> ("the ')' has no '(' before it", None)
  | Empty_group _ -> ("a group holds a pattern", None)
  | Empty_alternative _ -> ("an alternative of the pattern is empty", None)
  | Quantifier_without_part _ ->
      ("a quantifier stands after a literal, a class, or a group", None)
  | Two_quantifiers _ -> ("a part takes one quantifier at most", None)
  | Bad_count _ -> ("a '{' starts a quantifier {n}, {n,}, or {n,m}", None)
  | Count_too_large _ -> ("a count of a quantifier is from 0 to 255", None)
  | Counts_out_of_order _ ->
      ("in the quantifier {n,m}, n is not greater than m", None)
  | Matches_empty -> ("the pattern matches an empty id", None)
  | Too_large ->
      ( "the pattern is too large when its counts are written out",
        Some "use smaller counts" )

let message error =
  match parts error with
  | fault, None -> fault
  | fault, Some help -> fault ^ "; " ^ help
