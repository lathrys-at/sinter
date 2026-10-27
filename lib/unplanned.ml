(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

module Paths = Map.Make (String)
module Names = Set.Make (String)

let finding path (h : Git.hunk) =
  let id = Printf.sprintf "hunk:%s:%d-%d" path h.line h.eline in
  Finding.make Finding_class.Unplanned_change
    (Finding.Fact { id; ack_name = id })
    ~place:
      {
        Finding.path;
        span =
          {
            start = { line = h.line; column = 1 };
            stop = { line = h.eline; column = h.ecol };
          };
      }
    ~detail:
      (Printf.sprintf
         "no step of an open plan, no rule, and no exempt path covers %s" path)
    ()

let findings ?same ~base ~manifest facts diff =
  let config = Facts.manifest facts in
  let covering = Facts.covering facts in
  let plan_files =
    List.fold_left
      (fun paths (plan : Facts.plan) -> Names.add plan.path paths)
      Names.empty
      (Facts.plans facts @ Facts.plans base)
  in
  let covered path =
    Manifest.is_historical config path
    || covering path <> []
    || Manifest.is_exempt config
         ~plan_file:(fun path -> Names.mem path plan_files)
         ~manifest path
  in
  let documents = lazy (Paths.of_list (Facts.files facts))
  and earlier = lazy (Paths.of_list (Facts.files base))
  and fixes = lazy (Repair.fixes ?same ~base facts) in
  List.concat_map
    (fun (path, change) ->
      if covered path then []
      else
        List.filter_map
          (fun h ->
            if
              Repair.hunk (Lazy.force fixes)
                ~base:(Paths.find_opt path (Lazy.force earlier))
                (Paths.find_opt path (Lazy.force documents))
                h
            then None
            else Some (finding path h))
          (Git.hunks change))
    diff
