(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

let rec bind = function
  | [] -> ()
  | name :: file :: rest ->
      let content = In_channel.with_open_bin file In_channel.input_all in
      Printf.printf "let %s = %S\n" name content;
      bind rest
  | [ _ ] ->
      prerr_endline "embed: give a file after each name";
      exit 2

let () = match Array.to_list Sys.argv with [] -> () | _ :: args -> bind args
