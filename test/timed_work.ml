(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

let seconds f input =
  Gc.full_major ();
  let start = Sys.time () in
  ignore (Sys.opaque_identity (f input));
  Sys.time () -. start

let growth ?(exponent = 1.) ~margin ~runs ~sizes:(small, large) ~input f =
  if small < 1 then invalid_arg "Timed_work.growth: a size is below 1";
  if margin < 1. then invalid_arg "Timed_work.growth: the margin is below 1";
  if exponent < 0. then invalid_arg "Timed_work.growth: the exponent is below 0";
  if runs < 1 then invalid_arg "Timed_work.growth: the runs are below 1";
  let ratio = float_of_int large /. float_of_int small in
  if not (ratio > margin) then
    invalid_arg
      "Timed_work.growth: the ratio of the sizes is not larger than the margin";
  let small_input = input small in
  ignore (Sys.opaque_identity (f small_input));
  let small_time =
    List.fold_left Float.min infinity
      (List.init runs (fun _ -> seconds f small_input))
  in
  let limit = margin *. small_time *. (ratio ** exponent) in
  let large_input = input large in
  let rec run left shortest =
    if left = 0 then
      Error
        (Printf.sprintf
           "the time grows from %.6f s at the size %d to %.6f s at the size \
            %d, over the limit of %.6f s"
           small_time small shortest large limit)
    else
      let time = seconds f large_input in
      if time <= limit then Ok () else run (left - 1) (Float.min shortest time)
  in
  run runs infinity

let check_growth ?exponent ~margin ~runs ~sizes ~input f =
  match growth ?exponent ~margin ~runs ~sizes ~input f with
  | Ok () -> ()
  | Error message -> Alcotest.fail message
