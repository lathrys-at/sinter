(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

type t = { root : string; home : string; env : string array }

let root repo = repo.root
let env repo = repo.env

(* [remove_tree path] removes the file, link, or directory tree at
   [path]. It follows no symbolic link. *)
let rec remove_tree path =
  match Unix.lstat path with
  | { Unix.st_kind = Unix.S_DIR; _ } ->
      Array.iter
        (fun name -> remove_tree (Filename.concat path name))
        (Sys.readdir path);
      Unix.rmdir path
  | _ -> Unix.unlink path
  | exception Unix.Unix_error (Unix.ENOENT, _, _) -> ()

let temp_dir () =
  let dir = Filename.temp_dir "sinter-git-test" "" in
  at_exit (fun () -> try remove_tree dir with Unix.Unix_error _ -> ());
  dir

let contents path = In_channel.with_open_bin path In_channel.input_all

let write_file path text =
  Out_channel.with_open_bin path (fun channel ->
      Out_channel.output_string channel text)

(* [spawn program args ~env ~dir ~input] runs [program] in [dir], and
   gives its exit status, its standard output, and its standard error. *)
let spawn program args ~env ~dir ~input =
  let scratch = Filename.temp_dir "sinter-git-run" "" in
  Fun.protect
    ~finally:(fun () -> remove_tree scratch)
    (fun () ->
      let path name = Filename.concat scratch name in
      write_file (path "in") input;
      let open_fd name flags = Unix.openfile (path name) flags 0o600 in
      let stdin = open_fd "in" [ Unix.O_RDONLY ] in
      let stdout = open_fd "out" [ Unix.O_WRONLY; Unix.O_CREAT ] in
      let stderr = open_fd "err" [ Unix.O_WRONLY; Unix.O_CREAT ] in
      let pid =
        Fun.protect
          ~finally:(fun () -> List.iter Unix.close [ stdin; stdout; stderr ])
          (fun () ->
            Unix.create_process_env program
              (Array.of_list ("git" :: "-C" :: dir :: args))
              env stdin stdout stderr)
      in
      let _, status = Unix.waitpid [] pid in
      let code =
        match status with
        | Unix.WEXITED code -> code
        | Unix.WSIGNALED _ | Unix.WSTOPPED _ -> 255
      in
      (code, contents (path "out"), contents (path "err")))

let search_path = Option.value (Sys.getenv_opt "PATH") ~default:""

(* The git that the shell would run. On macOS, it can be a small program
   that finds the real git and starts it, which costs time on each run. *)
let git_on_path =
  String.split_on_char ':' search_path
  |> List.find_map (fun dir ->
      let git = Filename.concat dir "git" in
      if dir <> "" && Sys.file_exists git then Some git else None)
  |> Option.value ~default:"git"

(* The directory of the programs of git, which holds git itself. *)
let exec_path =
  match
    spawn git_on_path [ "--exec-path" ] ~env:(Unix.environment ()) ~dir:"."
      ~input:""
  with
  | 0, output, _ -> Some (String.trim output)
  | _ -> None

let real_git =
  match exec_path with
  | Some dir when Sys.file_exists (Filename.concat dir "git") ->
      Filename.concat dir "git"
  | _ -> git_on_path

let fixed_variables home =
  [
    "GIT_CONFIG_GLOBAL=/dev/null";
    "GIT_CONFIG_NOSYSTEM=1";
    "HOME=" ^ home;
    "GIT_AUTHOR_NAME=A U Thor";
    "GIT_AUTHOR_EMAIL=author@example.com";
    "GIT_AUTHOR_DATE=1700000000 +0000";
    "GIT_COMMITTER_NAME=C O Mitter";
    "GIT_COMMITTER_EMAIL=committer@example.com";
    "GIT_COMMITTER_DATE=1700000000 +0000";
    "GIT_CONFIG_COUNT=1";
    "GIT_CONFIG_KEY_0=init.defaultBranch";
    "GIT_CONFIG_VALUE_0=main";
  ]

(* [make_env ~home ~ceiling] is the environment of the git children of
   one test directory. Git looks for a repository in no directory above
   [ceiling], so that a test directory under the project's own working
   tree, as the mutation runner makes, never reaches the project's
   repository. *)
let make_env ~home ~ceiling =
  let inherited =
    Array.to_list (Unix.environment ())
    |> List.filter (fun entry ->
        not
          (String.starts_with ~prefix:"GIT_" entry
          || String.starts_with ~prefix:"HOME=" entry
          || String.starts_with ~prefix:"XDG_CONFIG_HOME=" entry
          || String.starts_with ~prefix:"PATH=" entry))
  in
  let path =
    match exec_path with
    | Some dir -> dir ^ ":" ^ search_path
    | None -> search_path
  in
  Array.of_list
    (inherited
    @ ("PATH=" ^ path)
      :: ("GIT_CEILING_DIRECTORIES=" ^ Unix.realpath ceiling)
      :: fixed_variables home)

let run_git ~env ~dir ?(input = "") args = spawn real_git args ~env ~dir ~input

let checked args (code, output, errors) =
  if code = 0 then output
  else
    failwith
      (Printf.sprintf "git %s exited with %d: %s" (String.concat " " args) code
         errors)

let git repo args = checked args (run_git ~env:repo.env ~dir:repo.root args)

let git_input repo args input =
  checked args (run_git ~env:repo.env ~dir:repo.root ~input args)

let git_status repo args =
  let code, _, _ = run_git ~env:repo.env ~dir:repo.root args in
  code

let init ?(object_format = "sha1") () =
  let base = temp_dir () in
  let home = Filename.concat base "home" in
  Unix.mkdir home 0o700;
  let env = make_env ~home ~ceiling:base in
  let args =
    [ "init"; "-q"; "--template="; "--object-format=" ^ object_format; "repo" ]
  in
  ignore (checked args (run_git ~env ~dir:base args));
  { root = Unix.realpath (Filename.concat base "repo"); home; env }

(* The working tree. *)

let rec make_parents path =
  let parent = Filename.dirname path in
  if not (Sys.file_exists parent) then (
    make_parents parent;
    Unix.mkdir parent 0o755)

let under repo path = Filename.concat repo.root path

let write repo path content =
  let full = under repo path in
  make_parents full;
  write_file full content

let make_executable repo path = Unix.chmod (under repo path) 0o755

let symlink repo ~target path =
  let full = under repo path in
  make_parents full;
  Unix.symlink target full

let remove repo path = remove_tree (under repo path)

let append_config repo text =
  Out_channel.with_open_gen [ Open_wronly; Open_append; Open_binary ] 0o644
    (Filename.concat repo.root ".git/config") (fun channel ->
      Out_channel.output_string channel text)

(* [copy_tree source target] copies the file, link, or directory tree at
   [source] to [target], with the permission bits of each file. *)
let rec copy_tree source target =
  let stat = Unix.lstat source in
  match stat.Unix.st_kind with
  | Unix.S_DIR ->
      Unix.mkdir target 0o755;
      Array.iter
        (fun name ->
          copy_tree (Filename.concat source name) (Filename.concat target name))
        (Sys.readdir source)
  | Unix.S_LNK -> Unix.symlink (Unix.readlink source) target
  | _ ->
      write_file target (contents source);
      Unix.chmod target stat.Unix.st_perm

let copy repo =
  let base = temp_dir () in
  let target = Filename.concat base "repo" in
  copy_tree repo.root target;
  {
    root = Unix.realpath target;
    home = repo.home;
    env = make_env ~home:repo.home ~ceiling:base;
  }

let index_state repo =
  let index = Filename.concat repo.root ".git/index" in
  match Unix.stat index with
  | stat ->
      Printf.sprintf "inode %d, %d bytes, modified at %h, digest %s"
        stat.Unix.st_ino stat.Unix.st_size stat.Unix.st_mtime
        (Digest.to_hex (Digest.file index))
  | exception Unix.Unix_error (Unix.ENOENT, _, _) -> "absent"

(* History. *)

type change =
  | File of string * string
  | Executable of string * string
  | Link of string * string
  | Submodule of string * string
  | Delete of string

let data text = Printf.sprintf "data %d\n%s\n" (String.length text) text

let change_command = function
  | File (path, content) ->
      Printf.sprintf "M 100644 inline %s\n%s" path (data content)
  | Executable (path, content) ->
      Printf.sprintf "M 100755 inline %s\n%s" path (data content)
  | Link (path, target) ->
      Printf.sprintf "M 120000 inline %s\n%s" path (data target)
  | Submodule (path, id) -> Printf.sprintf "M 160000 %s %s\n" id path
  | Delete path -> Printf.sprintf "D %s\n" path

let commit ?(parents = []) ~ref ~mark ~message changes =
  let parent_lines =
    List.mapi
      (fun index parent ->
        Printf.sprintf "%s :%d\n" (if index = 0 then "from" else "merge") parent)
      parents
  in
  String.concat ""
    ([
       Printf.sprintf "commit %s\nmark :%d\n" ref mark;
       "author A U Thor <author@example.com> 1700000000 +0000\n";
       "committer C O Mitter <committer@example.com> 1700000000 +0000\n";
       data message;
     ]
    @ parent_lines
    @ List.map change_command changes)

let reset ~ref ~mark = Printf.sprintf "reset %s\nfrom :%d\n\n" ref mark

let import repo commands =
  let input = String.concat "" commands ^ "done\n" in
  let args = [ "fast-import"; "--quiet"; "--done" ] in
  ignore (checked args (run_git ~env:repo.env ~dir:repo.root ~input args))

let checkout repo = ignore (git repo [ "reset"; "-q"; "--hard" ])

(* Fake executables. *)

let fake_git script =
  let dir = temp_dir () in
  let bin = Filename.concat dir "bin" in
  Unix.mkdir bin 0o755;
  Unix.symlink "/bin/sh" (Filename.concat bin "git");
  let path = Filename.concat dir "script" in
  write_file path script;
  let home = Filename.concat dir "home" in
  Unix.mkdir home 0o700;
  let env =
    Array.to_list (make_env ~home ~ceiling:dir)
    |> List.filter (fun entry -> not (String.starts_with ~prefix:"PATH=" entry))
  in
  (Array.of_list (("PATH=" ^ bin) :: env), path)

let break repo = remove repo ".git"

(* The shared repository. *)

let submodule_commit = String.make 40 'c'

let first_files =
  [
    File (".gitignore", "*.log\nbuild/\n");
    File ("README.md", "hello\n");
    File ("src/main.ml", "let () = ()\n");
    File ("tracked.log", "kept although ignored\n");
    File ("gone.txt", "deleted on disk\n");
    File ("bytes.bin", "\000\001\n\255");
    Executable ("run.sh", "#!/bin/sh\n");
    Link ("link", "README.md");
    Link ("link-as-file", "README.md");
    Submodule ("sub", submodule_commit);
    Submodule ("sub-as-file", submodule_commit);
  ]

(* The files of commit 2 that the working tree changes, for the diff. *)
let quoted_name = "caf\xc3\xa9\tdoc one.txt"

let second_changes =
  [
    File ("mod.txt", "1\n2\n3\n4\n5\n6\n7\n8\n9\n10\n");
    File ("head.txt", "a\nb\nc\n");
    File ("tail.txt", "a\nb\nc\n");
    File ("bin.dat", "\000binary\000\n");
    File ("mode.sh", "#!/bin/sh\n");
    File ("removed.txt", "removed from the index\n");
    File ("old-name.txt", "renamed\n");
    File ("unstaged.txt", "removed from the index, kept on disk\n");
    File ("typed.txt", "becomes a link\n");
    File (quoted_name, "before\n");
  ]

let origin_changes = [ File ("origin.txt", "origin\n") ]
let lonely_files = [ File ("lonely.txt", "lonely\n") ]

let shared_config =
  "[remote \"origin\"]\n\
   \turl = /dev/null\n\
   \tfetch = +refs/heads/*:refs/remotes/origin/*\n\
   [branch \"main\"]\n\
   \tremote = origin\n\
   \tmerge = refs/heads/main\n\
   [branch \"gone\"]\n\
   \tremote = origin\n\
   \tmerge = refs/heads/missing\n"

let change_working_tree repo =
  remove repo "gone.txt";
  remove repo "link-as-file";
  write repo "link-as-file" "README.md";
  remove repo "sub-as-file";
  write repo "sub-as-file" "a file\n";
  write repo "untracked.txt" "new\n";
  write repo "ignored.log" "ignored\n";
  write repo "build/out.o" "ignored\n";
  symlink repo ~target:"README.md" "untracked-link";
  write repo "nested/.git/HEAD" (submodule_commit ^ "\n");
  write repo "nested/.git/objects/.keep" "";
  write repo "nested/.git/refs/.keep" "";
  write repo "nested/inner.txt" "inner\n";
  write repo "mod.txt" "1\n2\nthree\n4\n5\n8\n9\nnine and a half\n10\n";
  write repo "head.txt" "c\n";
  write repo "tail.txt" "a\n";
  write repo "bin.dat" "\000binary, changed\000\n";
  make_executable repo "mode.sh";
  remove repo "removed.txt";
  remove repo "old-name.txt";
  write repo "new-name.txt" "renamed\n";
  write repo "added.txt" "added\n";
  remove repo "typed.txt";
  symlink repo ~target:"README.md" "typed.txt";
  write repo quoted_name "after\n";
  ignore
    (git repo
       [
         "update-index";
         "--add";
         "--remove";
         "added.txt";
         "new-name.txt";
         "old-name.txt";
         "removed.txt";
         "--force-remove";
         "unstaged.txt";
       ])

let shared_repo =
  lazy
    (let repo = init () in
     import repo
       [
         commit ~ref:"refs/heads/main" ~mark:1 ~message:"first" first_files;
         commit ~parents:[ 1 ] ~ref:"refs/heads/main" ~mark:2 ~message:"second"
           second_changes;
         commit ~parents:[ 1 ] ~ref:"refs/remotes/origin/main" ~mark:3
           ~message:"origin" origin_changes;
         commit ~ref:"refs/heads/lonely" ~mark:4 ~message:"lonely" lonely_files;
         reset ~ref:"refs/heads/loc" ~mark:2;
         reset ~ref:"refs/remotes/origin/orig" ~mark:3;
         reset ~ref:"refs/heads/both" ~mark:2;
         reset ~ref:"refs/remotes/origin/both" ~mark:3;
         reset ~ref:"refs/heads/gone" ~mark:2;
       ];
     append_config repo shared_config;
     checkout repo;
     change_working_tree repo;
     repo)

let shared () = Lazy.force shared_repo
