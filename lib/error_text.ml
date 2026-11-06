(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

type place = { path : string; span : Toml.span; line : string option }
type t = { fault : string; help : string; place : place option }

let fault_of_sinter = "report this as a fault of sinter"
let output_help = "check that the output stays open and that the disk has space"

let first_line text =
  match String.index_opt text '\n' with
  | Some stop -> String.sub text 0 stop
  | None -> text

let git_text = function
  | Git.Git_not_found reason ->
      ( "cannot start git: " ^ reason,
        "install git 2.43.7 or later, and put it on PATH" )
  | Git.Not_a_repository { dir; _ } ->
      ( Printf.sprintf "the folder %s is in no git repository" dir,
        "run sinter inside the working tree of a git repository" )
  | Git.Bad_revision revision ->
      ( Printf.sprintf "'%s' names no commit" revision,
        "name a revision that names a commit" )
  | Git.Default_branch_not_found name ->
      ( Printf.sprintf "no branch '%s' exists" name,
        "set 'default-branch' in sinter.toml to the name of the default branch"
      )
  | Git.No_merge_base (a, b) ->
      ( Printf.sprintf "%s and %s have no common ancestor" a b,
        "name a base with --base" )
  | Git.Command_failed { args; stderr; _ } ->
      ( Printf.sprintf "git %s failed: %s" (String.concat " " args)
          (first_line stderr),
        "run the same git command in the repository to see the whole message" )
  | Git.Malformed_output { args; detail } ->
      ( Printf.sprintf "git %s gave output that sinter cannot read: %s"
          (String.concat " " args) detail,
        "use git 2.43.7 or later; with such a git, " ^ fault_of_sinter )
  | Git.File_error reason ->
      ( reason,
        "check that you can read and write the file, and that the disk has \
         space" )

let of_git error =
  let fault, help = git_text error in
  { fault; help; place = None }
