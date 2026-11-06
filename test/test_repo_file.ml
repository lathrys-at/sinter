(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

open Sinter_core

let case name f = Alcotest.test_case name `Quick f

let property ?(count = 100) ~name ~print generator check =
  QCheck_alcotest.to_alcotest ~speed_level:`Quick
    (QCheck2.Test.make ~count ~name ~print generator check)

let write path text =
  Out_channel.with_open_bin path (fun channel ->
      Out_channel.output_string channel text)

let ( / ) = Filename.concat

let error =
  Alcotest.testable
    (fun formatter error ->
      Format.pp_print_string formatter (Repo_file.message "p" error))
    ( = )

let content = Alcotest.(result string error)

let contains ~part text =
  let size = String.length part in
  let rec from at =
    at + size <= String.length text
    && (String.equal (String.sub text at size) part || from (at + 1))
  in
  from 0

let secret = "TOKEN=hidden-value\n"

type ending = File | Folder | Pipe | Nothing

let make_ending path = function
  | File -> write path secret
  | Folder -> Unix.mkdir path 0o755
  | Pipe -> Unix.mkfifo path 0o644
  | Nothing -> ()

let rec make_folders folder = function
  | [] -> folder
  | part :: rest ->
      Unix.mkdir (folder / part) 0o755;
      make_folders (folder / part) rest

type tree = { parts : string list; link_at : int option; ending : ending }

let print_ending = function
  | File -> "a file"
  | Folder -> "a folder"
  | Pipe -> "a pipe"
  | Nothing -> "nothing"

let print_tree { parts; link_at; ending } =
  Printf.sprintf "%S, a link at %s, %s at the end" (String.concat "/" parts)
    (Option.fold ~none:"no part" ~some:string_of_int link_at)
    (print_ending ending)

let tree =
  let open QCheck2.Gen in
  let* parts =
    list_size (int_range 1 4) (oneof_list [ "a"; "b c"; "\xc3\xa9"; "..e" ])
  in
  let* link_at = option (int_bound (List.length parts - 1)) in
  let* ending = oneof_list [ File; Folder; Pipe; Nothing ] in
  return { parts; link_at; ending }

let rec take count = function
  | part :: rest when count > 0 -> part :: take (count - 1) rest
  | _ -> []

let rec drop count = function
  | _ :: rest when count > 0 -> drop (count - 1) rest
  | parts -> parts

let split_last parts =
  let count = List.length parts - 1 in
  (take count parts, drop count parts |> String.concat "")

let build root outside { parts; link_at; ending } =
  match link_at with
  | None ->
      let folders, last = split_last parts in
      make_ending (make_folders root folders / last) ending
  | Some at ->
      let above = make_folders root (take at parts) in
      let rest = drop (at + 1) parts in
      let name = List.nth parts at in
      if List.is_empty rest then make_ending (outside / "target") ending
      else (
        Unix.mkdir (outside / "target") 0o755;
        let folders, last = split_last rest in
        make_ending (make_folders (outside / "target") folders / last) ending);
      Unix.symlink (outside / "target") (above / name)

let expected { link_at; ending; _ } =
  match (link_at, ending) with
  | Some _, _ -> Error Repo_file.Symbolic_link
  | None, File -> Ok secret
  | None, (Folder | Pipe) -> Error Repo_file.Not_regular
  | None, Nothing -> Error Repo_file.Nothing_at_path

let holds_no_target_text ~outside path result =
  match result with
  | Ok _ -> true
  | Error error ->
      let message = Repo_file.message path error in
      (not (contains ~part:outside message))
      && (not (contains ~part:"target" message))
      && not (contains ~part:"hidden-value" message)

let each_tree_gives_the_answer_of_its_case =
  property ~name:"each tree gives the answer of its case" ~print:print_tree tree
    (fun tree ->
      Fixture.with_temporary_folder (fun scratch ->
          let root = scratch / "root" and outside = scratch / "outside" in
          Unix.mkdir root 0o755;
          Unix.mkdir outside 0o755;
          build root outside tree;
          let path = String.concat "/" tree.parts in
          let result = Repo_file.read ~root path in
          result = expected tree && holds_no_target_text ~outside path result))

let read_gives_the_bytes_of_a_file =
  property ~name:"read gives the bytes of a file" ~print:String.escaped
    QCheck2.Gen.(string_size ~gen:char (int_bound 64))
    (fun bytes ->
      Fixture.with_temporary_folder (fun root ->
          write (root / "f") bytes;
          Repo_file.read ~root "f" = Ok bytes))

let a_part_that_is_not_a_name_is_an_error =
  property ~name:"a part that is not a name is an error, and no walk"
    ~print:String.escaped
    QCheck2.Gen.(
      let name = oneof_list [ "d"; "f" ]
      and bad = oneof_list [ ""; "."; ".." ] in
      let* before = list_size (int_bound 2) name in
      let* part = bad in
      let* after = list_size (int_bound 2) name in
      return (String.concat "/" (before @ (part :: after))))
    (fun path ->
      Fixture.with_temporary_folder (fun root ->
          Unix.mkdir (root / "d") 0o755;
          write (root / "f") "text\n";
          write (root / "d" / "f") "text\n";
          Repo_file.read ~root path = Error Repo_file.Not_a_repository_path))

let the_absolute_and_the_empty_path_are_errors () =
  Fixture.with_temporary_folder (fun root ->
      write (root / "f") "text\n";
      List.iter
        (fun path ->
          Alcotest.check content path (Error Repo_file.Not_a_repository_path)
            (Repo_file.read ~root path))
        [ root / "f"; ""; "f/"; "/" ])

let a_long_file_comes_back_whole () =
  Fixture.with_temporary_folder (fun root ->
      let text = String.make 300_000 'x' in
      Unix.mkdir (root / "d") 0o755;
      write (root / "d" / "f") text;
      Alcotest.check content "the text" (Ok text) (Repo_file.read ~root "d/f"))

let a_file_on_the_way_is_nothing_at_the_path () =
  Fixture.with_temporary_folder (fun root ->
      write (root / "f") "text\n";
      Alcotest.check content "under a file" (Error Repo_file.Nothing_at_path)
        (Repo_file.read ~root "f/g");
      Alcotest.check content "deep under a file"
        (Error Repo_file.Nothing_at_path)
        (Repo_file.read ~root "f/g/h"))

let a_pipe_on_the_way_is_nothing_at_the_path () =
  Fixture.with_temporary_folder (fun root ->
      Unix.mkfifo (root / "p") 0o644;
      Alcotest.check content "under a pipe" (Error Repo_file.Nothing_at_path)
        (Repo_file.read ~root "p/g"))

let in_folder folder f =
  let previous = Sys.getcwd () in
  Sys.chdir folder;
  Fun.protect ~finally:(fun () -> Sys.chdir previous) f

let a_socket_is_not_regular () =
  Fixture.with_temporary_folder (fun root ->
      let socket = Unix.socket Unix.PF_UNIX Unix.SOCK_STREAM 0 in
      Fun.protect
        ~finally:(fun () -> Unix.close socket)
        (fun () ->
          in_folder root (fun () -> Unix.bind socket (Unix.ADDR_UNIX "s"));
          Alcotest.check content "the socket" (Error Repo_file.Not_regular)
            (Repo_file.read ~root "s")))

let a_dangling_link_is_a_link () =
  Fixture.with_temporary_folder (fun root ->
      Unix.symlink "nowhere-text" (root / "last");
      Unix.symlink "nowhere-text" (root / "way");
      Alcotest.check content "at the last part" (Error Repo_file.Symbolic_link)
        (Repo_file.read ~root "last");
      Alcotest.check content "on the way" (Error Repo_file.Symbolic_link)
        (Repo_file.read ~root "way/f"))

let a_link_inside_the_root_is_also_a_link () =
  Fixture.with_temporary_folder (fun root ->
      Unix.mkdir (root / "d") 0o755;
      write (root / "d" / "f") "text\n";
      Unix.symlink "d" (root / "e");
      Unix.symlink "d/f" (root / "g");
      Alcotest.check content "a link to a folder"
        (Error Repo_file.Symbolic_link)
        (Repo_file.read ~root "e/f");
      Alcotest.check content "a link to a file" (Error Repo_file.Symbolic_link)
        (Repo_file.read ~root "g"))

let a_link_deep_in_the_path_is_a_link () =
  Fixture.with_temporary_folder (fun root ->
      Unix.mkdir (root / "d") 0o755;
      Unix.mkdir (root / "d" / "e") 0o755;
      Unix.symlink "nowhere" (root / "d" / "e" / "l");
      Alcotest.check content "on the way" (Error Repo_file.Symbolic_link)
        (Repo_file.read ~root "d/e/l/f"))

let a_link_in_the_root_is_followed () =
  Fixture.with_temporary_folder (fun scratch ->
      Unix.mkdir (scratch / "real") 0o755;
      write (scratch / "real" / "f") "text\n";
      Unix.symlink (scratch / "real") (scratch / "alias");
      Alcotest.check content "the text" (Ok "text\n")
        (Repo_file.read ~root:(scratch / "alias") "f"))

let a_name_with_a_nul_byte_is_nothing_at_the_path () =
  Fixture.with_temporary_folder (fun root ->
      write (root / "f") "text\n";
      Alcotest.check content "the name" (Error Repo_file.Nothing_at_path)
        (Repo_file.read ~root "f\000g"))

let a_root_that_is_gone_is_nothing_at_the_path () =
  Fixture.with_temporary_folder (fun scratch ->
      Alcotest.check content "the root" (Error Repo_file.Nothing_at_path)
        (Repo_file.read ~root:(scratch / "gone") "f"))

let too_long = String.make 300 'n'

let a_name_too_long_does_not_open () =
  Fixture.with_temporary_folder (fun root ->
      match Repo_file.read ~root too_long with
      | Error (Repo_file.Cannot_open reason) ->
          Alcotest.(check string)
            "the reason"
            (Unix.error_message Unix.ENAMETOOLONG)
            reason
      | other ->
          Alcotest.failf "the read gives %s"
            (match other with
            | Ok _ -> "a text"
            | Error error -> Repo_file.message "p" error))

let a_root_with_a_name_too_long_does_not_open () =
  Fixture.with_temporary_folder (fun scratch ->
      Alcotest.check content "the root"
        (Error (Repo_file.Cannot_open (Unix.error_message Unix.ENAMETOOLONG)))
        (Repo_file.read ~root:(scratch / too_long) "f"))

let a_root_that_is_a_file_does_not_open_a_part () =
  Fixture.with_temporary_folder (fun scratch ->
      write (scratch / "file") "text\n";
      Alcotest.check content "the part"
        (Error (Repo_file.Cannot_open (Unix.error_message Unix.ENOTDIR)))
        (Repo_file.read ~root:(scratch / "file") "f"))

let skipped_for_this_user () =
  print_endline "skipped: this user reads a file that has no permissions";
  Alcotest.skip ()

let a_file_with_no_permissions_does_not_open () =
  Fixture.with_temporary_folder (fun root ->
      write (root / "f") "text\n";
      match
        Unreadable.with_unreadable (root / "f") (fun () ->
            Repo_file.read ~root "f")
      with
      | None -> skipped_for_this_user ()
      | Some result ->
          Alcotest.check content "the file"
            (Error (Repo_file.Cannot_open (Unix.error_message Unix.EACCES)))
            result)

let a_folder_with_no_permissions_does_not_open () =
  Fixture.with_temporary_folder (fun root ->
      Unix.mkdir (root / "d") 0o755;
      write (root / "d" / "f") "text\n";
      match
        Unreadable.with_unreadable (root / "d") (fun () ->
            Repo_file.read ~root "d/f")
      with
      | None -> skipped_for_this_user ()
      | Some result ->
          Alcotest.check content "the folder"
            (Error (Repo_file.Cannot_open (Unix.error_message Unix.EACCES)))
            result)

let open_handles () = Array.length (Sys.readdir "/dev/fd")

let no_handle_stays_open_after_any_answer () =
  Fixture.with_temporary_folder (fun root ->
      Unix.mkdir (root / "d") 0o755;
      write (root / "d" / "f") "text\n";
      Unix.mkfifo (root / "d" / "p") 0o644;
      Unix.symlink "f" (root / "d" / "l");
      Unix.symlink "d" (root / "e");
      let before = open_handles () in
      List.iter
        (fun path -> ignore (Repo_file.read ~root path))
        [
          "d/f";
          "d/p";
          "d";
          "d/l";
          "e/f";
          "d/f/g";
          "d/missing";
          "d/missing/g";
          "d/" ^ too_long;
          "./d/f";
        ];
      ignore (Repo_file.read ~root:(root / "gone") "f");
      ignore (Repo_file.read ~root:(root / "d" / "f") "g");
      Alcotest.(check int) "the open handles" before (open_handles ()))

let each_refusal_at_depth_closes_each_handle =
  property ~count:30 ~name:"no tree leaves a handle open" ~print:print_tree tree
    (fun tree ->
      Fixture.with_temporary_folder (fun scratch ->
          let root = scratch / "root" and outside = scratch / "outside" in
          Unix.mkdir root 0o755;
          Unix.mkdir outside 0o755;
          build root outside tree;
          let before = open_handles () in
          ignore (Repo_file.read ~root (String.concat "/" tree.parts));
          open_handles () = before))

let with_swaps swaps use =
  match Unix.fork () with
  | 0 ->
      (try
         while true do
           List.iter (fun (from, into) -> Unix.rename from into) swaps
         done
       with Unix.Unix_error _ -> ());
      Unix._exit 0
  | child ->
      Fun.protect
        ~finally:(fun () ->
          Unix.kill child Sys.sigkill;
          ignore (Unix.waitpid [] child))
        use

let no_read_during_a_swap_gives_the_secret () =
  Fixture.with_temporary_folder (fun scratch ->
      let root = scratch / "root" and outside = scratch / "outside" in
      Unix.mkdir root 0o755;
      Unix.mkdir outside 0o755;
      write (outside / "x") secret;
      Unix.mkdir (root / "d") 0o755;
      write (root / "d" / "x") "inside\n";
      write (root / "f") "inside\n";
      Unix.symlink outside (root / "d.link");
      Unix.symlink (outside / "x") (root / "f.link");
      let swaps =
        [
          (root / "d", root / "d.folder");
          (root / "d.link", root / "d");
          (root / "d", root / "d.link");
          (root / "d.folder", root / "d");
          (root / "f", root / "f.file");
          (root / "f.link", root / "f");
          (root / "f", root / "f.link");
          (root / "f.file", root / "f");
        ]
      in
      let leaked =
        with_swaps swaps (fun () ->
            let stop = Unix.gettimeofday () +. 0.2 in
            let rec reads leaked =
              if Unix.gettimeofday () > stop then leaked
              else
                let answers =
                  [ Repo_file.read ~root "d/x"; Repo_file.read ~root "f" ]
                in
                reads (leaked || List.mem (Ok secret) answers)
            in
            reads false)
      in
      Alcotest.(check bool) "a read gave the secret" false leaked)

let each_message_names_the_path () =
  List.iter
    (fun (expected, error) ->
      Alcotest.(check string) expected expected (Repo_file.message "a/b" error))
    [
      ( "a/b: the path names no file of the repository",
        Repo_file.Not_a_repository_path );
      ("a/b: no file is at this path", Repo_file.Nothing_at_path);
      ( "a/b is a symbolic link, and Sinter does not follow links",
        Repo_file.Symbolic_link );
      ( "a/b is not a regular file, and Sinter reads only regular files",
        Repo_file.Not_regular );
      ("a/b: Permission denied", Repo_file.Cannot_open "Permission denied");
      ("a/b: Input/output error", Repo_file.Cannot_read "Input/output error");
    ]

let place_testable =
  Alcotest.testable
    (fun formatter place ->
      Format.pp_print_string formatter
        (match place with
        | Repo_file.Inside path -> "inside " ^ path
        | Repo_file.Outside path -> "outside " ^ path))
    ( = )

let place_result = Alcotest.(result place_testable string)

let with_root f =
  Fixture.with_temporary_folder (fun scratch ->
      let root = scratch / "root" in
      Unix.mkdir root 0o755;
      Unix.mkdir (root / "ci") 0o755;
      f ~scratch ~root)

let a_path_below_the_root_is_inside () =
  with_root (fun ~scratch:_ ~root ->
      List.iter
        (fun (path, expected) ->
          Alcotest.check place_result path (Ok (Repo_file.Inside expected))
            (Repo_file.place ~root ~dir:root path))
        [
          (root / "sinter.toml", "sinter.toml");
          (root / "ci/m.toml", "ci/m.toml");
          (root / "ci/../m.toml", "m.toml");
          (root / "./ci/./m.toml", "ci/m.toml");
          (root ^ "//ci//m.toml", "ci/m.toml");
          (root / "missing/m.toml", "missing/m.toml");
          (root / "ci/", "ci/");
          (root / "ci/.", "ci/");
          (root / "ci/a/..", "ci/");
          (root / "sinter.toml/", "sinter.toml/");
        ])

let a_link_below_the_root_stays_inside () =
  with_root (fun ~scratch ~root ->
      Unix.symlink scratch (root / "link");
      Unix.symlink scratch (root / "ci" / "link");
      List.iter
        (fun (path, expected) ->
          Alcotest.check place_result path (Ok (Repo_file.Inside expected))
            (Repo_file.place ~root ~dir:root path))
        [
          (root / "link", "link");
          (root / "link/m.toml", "link/m.toml");
          (root / "ci/link/m.toml", "ci/link/m.toml");
        ])

let a_link_to_the_root_outside_it_leads_inside () =
  with_root (fun ~scratch ~root ->
      Unix.symlink root (scratch / "alias");
      Alcotest.check place_result "through the alias"
        (Ok (Repo_file.Inside "ci/m.toml"))
        (Repo_file.place ~root ~dir:root (scratch / "alias/ci/m.toml"));
      Alcotest.check place_result "from the alias of the root"
        (Ok (Repo_file.Inside "m.toml"))
        (Repo_file.place ~root:(scratch / "alias") ~dir:root (root / "m.toml")))

let a_link_to_a_folder_below_the_root_leads_inside () =
  with_root (fun ~scratch ~root ->
      Unix.mkdir (root / "ci" / "deep") 0o755;
      Unix.symlink (root / "ci") (scratch / "alias");
      Unix.symlink (root / "ci" / "deep") (scratch / "deep");
      Alcotest.check place_result "one folder below"
        (Ok (Repo_file.Inside "ci/l.toml"))
        (Repo_file.place ~root ~dir:root (scratch / "alias/l.toml"));
      Alcotest.check place_result "two folders below"
        (Ok (Repo_file.Inside "ci/deep/x/l.toml"))
        (Repo_file.place ~root ~dir:root (scratch / "deep/x/l.toml"));
      Alcotest.check place_result "a name that starts like the root"
        (Ok (Repo_file.Outside (root ^ "2/m.toml")))
        (Repo_file.place ~root ~dir:root (root ^ "2/m.toml")))

let a_link_at_the_last_part_outside_the_root_stays_outside () =
  with_root (fun ~scratch ~root ->
      write (root / "m.toml") "text\n";
      Unix.symlink (root / "m.toml") (scratch / "alias.toml");
      Alcotest.check place_result "the path"
        (Ok (Repo_file.Outside (scratch / "alias.toml")))
        (Repo_file.place ~root ~dir:root (scratch / "alias.toml")))

let a_path_not_below_the_root_is_outside () =
  with_root (fun ~scratch ~root ->
      List.iter
        (fun (path, expected) ->
          Alcotest.check place_result path (Ok (Repo_file.Outside expected))
            (Repo_file.place ~root ~dir:root path))
        [
          (root, root);
          (root ^ "/", root ^ "/");
          (root / "ci/..", root ^ "/");
          (scratch / "m.toml", scratch / "m.toml");
          (scratch / "m.toml/", scratch / "m.toml/");
          (root / "../m.toml", scratch / "m.toml");
          ("/", "/");
          ("/.", "/");
          ("/..", "/");
          ("/../../x", "/x");
        ])

let the_text_of_a_link_and_two_dots_stays_in_the_text () =
  with_root (fun ~scratch ~root ->
      Unix.mkdir (scratch / "far") 0o755;
      Unix.mkdir (scratch / "far" / "deep") 0o755;
      Unix.symlink (scratch / "far" / "deep") (root / "ci" / "link");
      Alcotest.check place_result "two levels up, by the text"
        (Ok (Repo_file.Inside "m.toml"))
        (Repo_file.place ~root ~dir:root (root / "ci/link/../../m.toml"));
      Alcotest.check place_result "three levels up, by the text"
        (Ok (Repo_file.Outside (scratch / "m.toml")))
        (Repo_file.place ~root ~dir:root (root / "ci/link/../../../m.toml")))

let a_relative_path_is_relative_to_the_folder () =
  with_root (fun ~scratch ~root ->
      Alcotest.check place_result "from a folder below the root"
        (Ok (Repo_file.Inside "ci/m.toml"))
        (Repo_file.place ~root ~dir:(root / "ci") "m.toml");
      Alcotest.check place_result "up to the root"
        (Ok (Repo_file.Inside "m.toml"))
        (Repo_file.place ~root ~dir:(root / "ci") "../m.toml");
      Alcotest.check place_result "out of the root"
        (Ok (Repo_file.Outside (scratch / "m.toml")))
        (Repo_file.place ~root ~dir:root "../m.toml"))

let a_root_with_no_real_path_is_an_error () =
  with_root (fun ~scratch ~root ->
      Alcotest.check place_result "the root"
        (Error (Unix.error_message Unix.ENOENT))
        (Repo_file.place ~root:(scratch / "gone") ~dir:root (root / "m.toml"));
      Alcotest.check place_result "the folder of a relative path"
        (Error (Unix.error_message Unix.ENOENT))
        (Repo_file.place ~root ~dir:(scratch / "gone") "m.toml"))

let an_absolute_path_does_not_need_the_folder () =
  with_root (fun ~scratch ~root ->
      Alcotest.check place_result "the place" (Ok (Repo_file.Inside "m.toml"))
        (Repo_file.place ~root ~dir:(scratch / "gone") (root / "m.toml")))

let oracle ~scratch path =
  let parts =
    List.fold_left
      (fun kept part ->
        match (part, kept) with
        | ("" | "."), _ -> kept
        | "..", [] -> []
        | "..", _ :: above -> above
        | _ -> part :: kept)
      []
      (String.split_on_char '/' path)
    |> List.rev
  in
  let root_parts =
    List.filter (fun part -> part <> "") (String.split_on_char '/' scratch)
    @ [ "root" ]
  in
  let ending =
    if
      (String.ends_with ~suffix:"/" path
      || String.ends_with ~suffix:"/." path
      || String.ends_with ~suffix:"/.." path)
      && parts <> []
    then "/"
    else ""
  in
  let rec below root parts =
    match (root, parts) with
    | [], (_ :: _ as rest) -> Some rest
    | same :: root, part :: parts when String.equal same part ->
        below root parts
    | _ -> None
  in
  match below root_parts parts with
  | Some rest -> Repo_file.Inside (String.concat "/" rest ^ ending)
  | None -> Repo_file.Outside ("/" ^ String.concat "/" parts ^ ending)

let place_is_the_text_of_the_path_against_the_root =
  property ~name:"place is the text of the path against the root"
    ~print:(String.concat "/")
    QCheck2.Gen.(
      list_size (int_bound 8)
        (oneof_list [ "a"; "b"; "link"; "root"; "."; ".."; "" ]))
    (fun segments ->
      with_root (fun ~scratch ~root ->
          Unix.mkdir (root / "a") 0o755;
          Unix.mkdir (root / "b") 0o755;
          Unix.symlink scratch (root / "link");
          Unix.symlink scratch (root / "a" / "link");
          Unix.symlink "/" (root / "b" / "link");
          let path = root ^ "/" ^ String.concat "/" segments in
          Repo_file.place ~root ~dir:root path = Ok (oracle ~scratch path)))

let tests =
  [
    each_tree_gives_the_answer_of_its_case;
    read_gives_the_bytes_of_a_file;
    a_part_that_is_not_a_name_is_an_error;
    case "the absolute and the empty path are errors"
      the_absolute_and_the_empty_path_are_errors;
    case "a long file comes back whole" a_long_file_comes_back_whole;
    case "a file on the way is nothing at the path"
      a_file_on_the_way_is_nothing_at_the_path;
    case "a pipe on the way is nothing at the path"
      a_pipe_on_the_way_is_nothing_at_the_path;
    case "a socket is not regular" a_socket_is_not_regular;
    case "a dangling link is a link" a_dangling_link_is_a_link;
    case "a link inside the root is also a link"
      a_link_inside_the_root_is_also_a_link;
    case "a link deep in the path is a link" a_link_deep_in_the_path_is_a_link;
    case "a link in the root is followed" a_link_in_the_root_is_followed;
    case "a name with a NUL byte is nothing at the path"
      a_name_with_a_nul_byte_is_nothing_at_the_path;
    case "a root that is gone is nothing at the path"
      a_root_that_is_gone_is_nothing_at_the_path;
    case "a name too long does not open" a_name_too_long_does_not_open;
    case "a root with a name too long does not open"
      a_root_with_a_name_too_long_does_not_open;
    case "a root that is a file does not open a part"
      a_root_that_is_a_file_does_not_open_a_part;
    case "a file with no permissions does not open"
      a_file_with_no_permissions_does_not_open;
    case "a folder with no permissions does not open"
      a_folder_with_no_permissions_does_not_open;
    case "no handle stays open after any answer"
      no_handle_stays_open_after_any_answer;
    each_refusal_at_depth_closes_each_handle;
    case "no read during a swap gives the secret"
      no_read_during_a_swap_gives_the_secret;
    case "each message names the path" each_message_names_the_path;
    case "a path below the root is inside" a_path_below_the_root_is_inside;
    case "a link below the root stays inside" a_link_below_the_root_stays_inside;
    case "a link to the root outside it leads inside"
      a_link_to_the_root_outside_it_leads_inside;
    case "a link to a folder below the root leads inside"
      a_link_to_a_folder_below_the_root_leads_inside;
    case "a link at the last part outside the root stays outside"
      a_link_at_the_last_part_outside_the_root_stays_outside;
    case "a path not below the root is outside"
      a_path_not_below_the_root_is_outside;
    case "the text of a link and two dots stays in the text"
      the_text_of_a_link_and_two_dots_stays_in_the_text;
    case "a relative path is relative to the folder"
      a_relative_path_is_relative_to_the_folder;
    case "a root with no real path is an error"
      a_root_with_no_real_path_is_an_error;
    case "an absolute path does not need the folder"
      an_absolute_path_does_not_need_the_folder;
    place_is_the_text_of_the_path_against_the_root;
  ]
