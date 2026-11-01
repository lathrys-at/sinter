(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

let case name f = Alcotest.test_case name `Quick f

let file () =
  let path = Filename.concat (Git_fixture.temp_dir ()) "file" in
  Out_channel.with_open_bin path (fun channel ->
      Out_channel.output_string channel "text\n");
  Unix.chmod path 0o640;
  path

let permissions path = (Unix.stat path).Unix.st_perm

let with_unreadable_runs_the_function_only_when_the_open_is_refused () =
  let path = file () in
  let runs = ref 0 in
  match
    Unreadable.with_unreadable path (fun () ->
        incr runs;
        match open_in_bin path with
        | channel ->
            close_in channel;
            false
        | exception Sys_error _ -> true)
  with
  | Some refused ->
      Alcotest.(check bool)
        "the open is refused inside the function" true refused
  | None -> Alcotest.(check int) "the runs of the function" 0 !runs

let with_unreadable_takes_every_permission_while_the_function_runs () =
  let path = file () in
  Option.iter
    (Alcotest.(check int) "the permissions" 0o000)
    (Unreadable.with_unreadable path (fun () -> permissions path))

let with_unreadable_gives_the_permissions_back () =
  let path = file () in
  ignore (Unreadable.with_unreadable path (fun () -> ()));
  Alcotest.(check int) "after a return" 0o640 (permissions path);
  (match Unreadable.with_unreadable path (fun () -> raise Exit) with
  | Some () | None -> ()
  | exception Exit -> ());
  Alcotest.(check int) "after an exception" 0o640 (permissions path)

let with_unreadable_works_on_a_folder () =
  let path = Git_fixture.temp_dir () in
  Unix.chmod path 0o750;
  Option.iter
    (fun refused ->
      Alcotest.(check bool) "the folder does not list" true refused)
    (Unreadable.with_unreadable path (fun () ->
         match Sys.readdir path with
         | _ -> false
         | exception Sys_error _ -> true));
  Alcotest.(check int) "the permissions" 0o750 (permissions path)

let with_unreadable_of_a_missing_path_raises () =
  let path = Filename.concat (Git_fixture.temp_dir ()) "missing" in
  match Unreadable.with_unreadable path (fun () -> ()) with
  | _ -> Alcotest.fail "the call gave a value"
  | exception Unix.Unix_error (Unix.ENOENT, _, _) -> ()

let tests =
  [
    case "with_unreadable runs the function only when the open is refused"
      with_unreadable_runs_the_function_only_when_the_open_is_refused;
    case "with_unreadable takes every permission while the function runs"
      with_unreadable_takes_every_permission_while_the_function_runs;
    case "with_unreadable gives the permissions back"
      with_unreadable_gives_the_permissions_back;
    case "with_unreadable works on a folder" with_unreadable_works_on_a_folder;
    case "with_unreadable of a missing path raises"
      with_unreadable_of_a_missing_path_raises;
  ]
