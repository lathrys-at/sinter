(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

module Names = Map.Make (String)

type t = { sets : Path_set.t array; filed : int list Names.t }

let make sets =
  let filed =
    List.fold_left
      (fun filed (position, set) ->
        List.fold_left
          (fun filed -> function
            | Path_set.Plain glob ->
                Names.update
                  (String.concat "/" (Glob.leading_names glob))
                  (function
                    | Some (last :: _ as positions) when last = position ->
                        Some positions
                    | Some positions -> Some (position :: positions)
                    | None -> Some [ position ])
                  filed
            | Path_set.Excluded _ -> filed)
          filed (Path_set.members set))
      Names.empty
      (List.mapi (fun position set -> (position, set)) sets)
  in
  { sets = Array.of_list sets; filed }

let holders index path =
  let rec keys prefix found = function
    | [] -> found
    | name :: rest ->
        let key = if prefix = "" then name else prefix ^ "/" ^ name in
        keys key (key :: found) rest
  in
  List.concat_map
    (fun key -> Option.value (Names.find_opt key index.filed) ~default:[])
    (keys "" [ "" ] (String.split_on_char '/' path))
  |> List.sort_uniq Int.compare
  |> List.filter (fun position -> Path_set.mem index.sets.(position) path)
