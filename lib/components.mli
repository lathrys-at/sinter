(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(** The strongly connected components of a directed graph: the largest sets of
    nodes in which each node reaches every other node of the set. *)

val of_graph : int list array -> int list list
(** [of_graph successors] is the strongly connected components of the graph
    whose nodes are the indices of [successors], with an edge from [node] to
    each node of [successors.(node)]. Each node is in exactly one component. A
    node on no cycle is a component of one node. The time and the memory are in
    proportion to the nodes and the edges.

    @raise Invalid_argument if a successor is not an index of [successors]. *)
