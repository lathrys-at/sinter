(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

type step = { scope : string list; promises : (string * string) list }

let canonical_bytes value =
  match Json.to_string value with
  | Ok text -> text
  | Error _ ->
      invalid_arg
        "Sinter_core.Commitment_set.hash: a glob, a word, or a target is not \
         UTF-8"

let globs globs =
  Json.Array
    (List.map
       (fun glob -> Json.String glob)
       (List.sort_uniq String.compare globs))

let promise_objects steps =
  List.map
    (fun (word, target, _, scope) ->
      Json.Object
        [
          ("scope", scope);
          ("target", Json.String target);
          ("word", Json.String word);
        ])
    (List.sort
       (fun (w1, t1, s1, _) (w2, t2, s2, _) ->
         match String.compare w1 w2 with
         | 0 -> (
             match String.compare t1 t2 with
             | 0 -> String.compare s1 s2
             | n -> n)
         | n -> n)
       (List.concat_map
          (fun { scope; promises } ->
            let scope = globs scope in
            let bytes = canonical_bytes scope in
            List.map
              (fun (word, target) -> (word, target, bytes, scope))
              promises)
          steps))

let bytes ~scope steps =
  canonical_bytes
    (Json.Object
       [
         ("promises", Json.Array (promise_objects steps)); ("scope", globs scope);
       ])

let hash ~scope steps = Sha256.hex (bytes ~scope steps)
let printed text = String.length (canonical_bytes (Json.String text))

let array_size globs =
  let globs = List.sort_uniq String.compare globs in
  List.fold_left (fun total glob -> total + printed glob + 1) 1 globs
  + if globs = [] then 1 else 0

let size ~scope steps =
  let promises, objects =
    List.fold_left
      (fun (count, total) { scope; promises } ->
        let scope = array_size scope in
        List.fold_left
          (fun (count, total) (word, target) ->
            (count + 1, total + scope + printed target + printed word + 28))
          (count, total) promises)
      (0, 0) steps
  in
  24 + objects + max 0 (promises - 1) + array_size scope
