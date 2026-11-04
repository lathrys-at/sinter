(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

type visit = { number : int; mutable low : int; mutable on_stack : bool }
type call = Start of int list | Visit of int * visit * int list

let of_graph successors =
  let visits = Array.make (Array.length successors) None in
  let next =
    ref
      (0
      [@mutaml.skip
        "the numbers of arrival only order the nodes, so every first number \
         gives the same components"])
  in
  let stack = ref [] in
  let found = ref [] in
  let enter node =
    let visit = { number = !next; low = !next; on_stack = true } in
    visits.(node) <- Some visit;
    incr next;
    stack := (node, visit) :: !stack;
    visit
  in
  let rec pop root members =
    match !stack with
    | [] -> members
    | (node, visit) :: rest ->
        stack := rest;
        visit.on_stack <- false;
        if node = root then node :: members else pop root (node :: members)
  in
  let rec run = function
    | [] -> ()
    | Start [] :: calls -> run calls
    | Start (node :: rest) :: calls -> (
        match visits.(node) with
        | Some _ -> run (Start rest :: calls)
        | None ->
            let visit = enter node in
            run (Visit (node, visit, successors.(node)) :: Start rest :: calls))
    | Visit (node, visit, successor :: rest) :: calls -> (
        match visits.(successor) with
        | Some reached ->
            if reached.on_stack then visit.low <- min visit.low reached.number;
            run (Visit (node, visit, rest) :: calls)
        | None ->
            let reached = enter successor in
            run
              (Visit (successor, reached, successors.(successor))
              :: Visit (node, visit, rest)
              :: calls))
    | Visit (node, visit, []) :: calls ->
        (match calls with
        | Visit (_, caller, _) :: _ -> caller.low <- min caller.low visit.low
        | Start _ :: _ | [] -> ());
        if visit.low = visit.number then found := pop node [] :: !found;
        run calls
  in
  run [ Start (List.init (Array.length successors) Fun.id) ];
  !found
