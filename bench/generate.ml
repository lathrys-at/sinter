(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

open Cmdliner
open Sinter_bench

let generate seed declarations dir =
  match
    if declarations < 2 then
      Error (Printf.sprintf "N is %d, and it must be 2 or more" declarations)
    else if Sys.file_exists dir then Error (dir ^ " exists")
    else (
      Unix.mkdir dir 0o755;
      let tree = Generated_tree.make ~seed ~declarations in
      let repo = Generated_tree.write tree dir in
      Ok (tree, repo))
  with
  | Error message ->
      Printf.eprintf "generate: %s\n" message;
      1
  | Ok (tree, repo) ->
      Printf.printf
        "%s: files %d, req %d, design %d, decision %d, plans %d, seed %d\n"
        (Git_fixture.root repo)
        (List.length (Generated_tree.main tree))
        (Generated_tree.count tree "req")
        (Generated_tree.count tree "design")
        (Generated_tree.count tree "decision")
        (Generated_tree.count tree "plan")
        seed;
      0
  | exception
      (Failure message | Invalid_argument message | Sinter_bridge.Error message)
    ->
      Printf.eprintf "generate: %s\n" message;
      1
  | exception Unix.Unix_error (error, call, path) ->
      Printf.eprintf "generate: %s %s: %s\n" call path
        (Unix.error_message error);
      1

let () =
  let doc = "Make a git repository of generated markdown files" in
  let man =
    [
      `S Manpage.s_description;
      `P
        "Make the folder $(i,DIR), and a git repository in $(i,DIR)/repo that \
         holds $(i,N) declarations of the kinds req, design, and decision, in \
         markdown files. The repository also holds notes that cite, one plan \
         for each 1,000 declarations, a README.md, and a sinter.toml that \
         reads every markdown file.";
      `P
        "The branch main holds one commit with every file. The branch work \
         holds one more commit, which changes one file in 100. HEAD is work. \
         The working tree changes one more file in 1,000, with no commit. \
         Every file has the modification time 1700000000, and the index holds \
         that time, so git reads no file that did not change.";
      `P
        "The same seed and the same $(i,N) give the same files and the same \
         commits, byte for byte, on every run of one build.";
      `S "OUTPUT";
      `P
        "One line on standard output: the path of the working tree, and then \
         the number of files, the number of declarations of each kind, the \
         number of plans, and the seed, each after its name. Each error goes \
         to standard error.";
    ]
  in
  let seed =
    Arg.(
      value & opt int 1
      & info [ "seed" ] ~docv:"SEED" ~doc:"The seed of the tree.")
  in
  let declarations =
    Arg.(
      required
      & pos 0 (some int) None
      & info [] ~docv:"N" ~doc:"The number of declarations, 2 or more.")
  in
  let dir =
    Arg.(
      required
      & pos 1 (some string) None
      & info [] ~docv:"DIR" ~doc:"The folder to make. It must not exist.")
  in
  exit
    (Cmd.eval'
       (Cmd.v
          (Cmd.info "generate" ~doc ~man
             ~exits:
               (Cmd.Exit.info 1 ~doc:"when the repository is not made."
               :: Cmd.Exit.defaults))
          Term.(const generate $ seed $ declarations $ dir)))
