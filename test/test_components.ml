(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

open Sinter_core

let case name f = Alcotest.test_case name `Quick f

let sorted components =
  List.sort compare (List.map (List.sort compare) components)

let of_graph_gives_each_component () =
  Alcotest.(check (list (list int)))
    "the components"
    [ [ 0; 1; 2 ]; [ 3 ]; [ 4 ]; [ 5 ] ]
    (sorted
       (Components.of_graph [| [ 1 ]; [ 2; 3 ]; [ 0 ]; [ 4 ]; [ 4 ]; [] |]))

let of_graph_gives_no_component_of_no_node () =
  Alcotest.(check (list (list int)))
    "the components" [] (Components.of_graph [||])

let of_graph_refuses_a_successor_out_of_range () =
  match Components.of_graph [| [ 1 ] |] with
  | (_ : int list list) -> Alcotest.fail "no exception"
  | exception Invalid_argument _ -> ()

let of_graph_grows_in_proportion_to_the_graph () =
  Counted_work.check_growth ~margin:1.5 ~sizes:(1_000, 16_000)
    ~input:(fun count ->
      Array.init count (fun node -> [ (node + 1) mod count; node / 2 ]))
    Components.of_graph

let graph =
  QCheck2.Gen.(
    int_range 1 8 >>= fun count ->
    array_size (return count) (list_size (int_bound 3) (int_bound (count - 1))))

let components_are_the_sets_of_nodes_that_reach_each_other =
  QCheck_alcotest.to_alcotest ~speed_level:`Quick
    (QCheck2.Test.make ~count:300
       ~name:
         "each node is in one component, and two nodes share a component \
          exactly when each reaches the other"
       ~print:QCheck2.Print.(array (list int))
       graph
       (fun successors ->
         let count = Array.length successors in
         let reaches from target =
           let rec walk seen = function
             | [] -> List.mem target seen
             | node :: rest ->
                 if List.mem node seen then walk seen rest
                 else walk (node :: seen) (successors.(node) @ rest)
           in
           walk [] [ from ]
         in
         let components = Components.of_graph successors in
         let component node =
           List.find (fun members -> List.mem node members) components
         in
         List.sort compare (List.concat components) = List.init count Fun.id
         && List.for_all
              (fun a ->
                List.for_all
                  (fun b ->
                    List.mem b (component a) = (reaches a b && reaches b a))
                  (List.init count Fun.id))
              (List.init count Fun.id)))

let tests =
  [
    case "of_graph gives each component" of_graph_gives_each_component;
    case "of_graph gives no component of no node"
      of_graph_gives_no_component_of_no_node;
    case "of_graph refuses a successor out of range"
      of_graph_refuses_a_successor_out_of_range;
    case "of_graph grows in proportion to the graph"
      of_graph_grows_in_proportion_to_the_graph;
    components_are_the_sets_of_nodes_that_reach_each_other;
  ]
