(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

open Sinter_core

let counted f =
  let counts = Allocation.create () in
  Allocation.measure (Some counts) "work" (fun () ->
      ignore (Sys.opaque_identity (f ())));
  match Allocation.phases counts with
  | [ (_, words) ] -> words
  | _ -> invalid_arg "Counted_work: the count has no phase"

let words f = counted f - counted (fun () -> ())

let growth ?(exponent = 1.) ~margin ~sizes:(small, large) ~input f =
  if small < 1 then invalid_arg "Counted_work.growth: a size is below 1";
  if margin < 1. then invalid_arg "Counted_work.growth: the margin is below 1";
  if exponent < 0. then
    invalid_arg "Counted_work.growth: the exponent is below 0";
  let ratio = float_of_int large /. float_of_int small in
  if not (ratio > margin) then
    invalid_arg
      "Counted_work.growth: the ratio of the sizes is not larger than the \
       margin";
  let small_input = input small in
  ignore (Sys.opaque_identity (f small_input));
  let small_words = words (fun () -> f small_input) in
  let large_input = input large in
  let large_words = words (fun () -> f large_input) in
  let limit = margin *. float_of_int small_words *. (ratio ** exponent) in
  if float_of_int large_words <= limit then Ok ()
  else
    Error
      (Printf.sprintf
         "the work grows from %d words at the size %d to %d words at the size \
          %d, over the limit of %.0f words"
         small_words small large_words large limit)

let check_growth ?exponent ~margin ~sizes ~input f =
  match growth ?exponent ~margin ~sizes ~input f with
  | Ok () -> ()
  | Error message -> Alcotest.fail message
