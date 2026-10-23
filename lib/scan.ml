(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

type error =
  | Repository of Git.error
  | No_manifest
  | Missing_manifest of string
  | Unreadable_manifest of { path : string; reason : string }
  | Invalid_manifest of { path : string; errors : Manifest.error list }
  | Two_packs of { file : string; pack : string; other : string }
  | Plan_not_read of string
  | Pack_not_available of string
  | Bad_base of string
  | Target_not_found of string
  | No_merge_base of string
  | No_head
  | Unreadable_file of { file : string; error : Text_file.error }
  | Unparsed_file of { file : string; error : Sinter_bridge.Tree.error }
  | Reader of Markdown.load_error

let ( let* ) = Result.bind

(* The first line of [text]. *)
let first_line text =
  match String.index_opt text '\n' with
  | Some stop -> String.sub text 0 stop
  | None -> text

let git_message = function
  | Git.Git_not_found reason -> "cannot start git: " ^ reason
  | Git.Not_a_repository { dir; _ } ->
      Printf.sprintf "the folder %s is in no git repository" dir
  | Git.Bad_revision revision -> Printf.sprintf "'%s' names no commit" revision
  | Git.Target_not_found name -> Printf.sprintf "no branch '%s' exists" name
  | Git.No_merge_base (a, b) ->
      Printf.sprintf "%s and %s have no common ancestor" a b
  | Git.Command_failed { args; stderr; _ } ->
      Printf.sprintf "git %s failed: %s" (String.concat " " args)
        (first_line stderr)
  | Git.Malformed_output { args; detail } ->
      Printf.sprintf "git %s gave output that sinter cannot read: %s"
        (String.concat " " args) detail
  | Git.File_error reason -> reason

let messages = function
  | Repository error -> [ git_message error ]
  | No_manifest ->
      [
        "no sinter.toml at the repository root; create one, or name one with \
         --manifest";
      ]
  | Missing_manifest path -> [ Printf.sprintf "no manifest at %s" path ]
  | Unreadable_manifest { path; reason } ->
      [ Printf.sprintf "cannot read the manifest %s: %s" path reason ]
  | Invalid_manifest { path; errors } ->
      List.map (fun error -> Manifest.render ~path error) errors
  | Two_packs { file; pack; other } ->
      [
        Printf.sprintf
          "%s is in the files of two packs, %s and %s; add a '!' glob to one \
           of them"
          file pack other;
      ]
  | Plan_not_read file ->
      [
        Printf.sprintf
          "%s is under .plans/, and the pack markdown does not read it; add \
           \".plans/\" to its files"
          file;
      ]
  | Pack_not_available name ->
      [
        Printf.sprintf
          "the pack %s is not in the cache of packs; run sinter pack fetch" name;
      ]
  | Bad_base revision ->
      [ Printf.sprintf "the base '%s' names no commit" revision ]
  | Target_not_found name ->
      [
        Printf.sprintf
          "no branch '%s' exists here or on origin; set 'target' in sinter.toml"
          name;
      ]
  | No_merge_base name ->
      [
        Printf.sprintf
          "HEAD and the branch '%s' have no common ancestor; name a base with \
           --base"
          name;
      ]
  | No_head ->
      [ "HEAD names no commit; make a commit, or name a base with --base" ]
  | Unreadable_file { file; error } -> [ Text_file.message file error ]
  | Unparsed_file { file; error } ->
      [ file ^ ": " ^ Sinter_bridge.Tree.message error ]
  | Reader (Markdown.Grammar error) ->
      [
        "the built-in grammar of markdown does not load: "
        ^ Sinter_bridge.Language.message error;
      ]
  | Reader (Markdown.Query error) ->
      [
        "the built-in query of markdown does not compile: "
        ^ Sinter_bridge.Query.message error;
      ]

type outcome = { warnings : string list; records : Jsonl.record list }

let repository result = Result.map_error (fun error -> Repository error) result

let escape_path path =
  let rec pieces rest =
    match Sinter_bridge.Utf_8.first_invalid rest with
    | None -> [ rest ]
    | Some offset ->
        String.sub rest 0 offset
        :: Printf.sprintf "\\x%02x" (Char.code rest.[offset])
        :: pieces
             (String.sub rest (offset + 1) (String.length rest - offset - 1))
  in
  String.concat "" (pieces path)

let ledger_warning =
  "warning: the ledger ref refs/sinter/ledger is absent, so every plan counts \
   as open; fetch it with git fetch origin \
   refs/sinter/ledger:refs/sinter/ledger"

(* A path that the glob [.plans/**/*.md] matches. *)
let is_plan_path path =
  String.starts_with ~prefix:".plans/" path
  && String.ends_with ~suffix:".md" path

(* The manifest at [path], shown to the person as [shown]. *)
let load_manifest ~path ~shown ~missing =
  match Manifest.load path with
  | Ok manifest -> Ok manifest
  | Error Manifest.Missing -> Error missing
  | Error (Manifest.Unreadable reason) ->
      Error (Unreadable_manifest { path = shown; reason })
  | Error (Manifest.Invalid errors) ->
      Error (Invalid_manifest { path = shown; errors })

(* The path of the manifest for the index record: relative to [root]
   when the manifest is under it, otherwise absolute. *)
let manifest_location ~root path =
  match (Unix.realpath root, Unix.realpath path) with
  | root, path ->
      let prefix = root ^ "/" in
      if String.starts_with ~prefix path then
        Ok
          (String.sub path (String.length prefix)
             (String.length path - String.length prefix))
      else Ok path
  | exception Unix.Unix_error (code, _, _) -> Error (Unix.error_message code)

(* The first file of [files] that two packs read. *)
let two_packs packs files =
  List.find_map
    (fun file ->
      match
        List.filter
          (fun (pack : Manifest.pack) -> Path_set.mem pack.files file)
          packs
      with
      | first :: second :: _ ->
          Some (Two_packs { file; pack = first.name; other = second.name })
      | _ -> None)
    files

let markdown_files packs =
  List.find_map
    (fun (pack : Manifest.pack) ->
      if String.equal pack.name "markdown" then Some pack.files else None)
    packs

type base =
  | Given of { revision : string; commit : string }
  | Merge_base of { refname : string; commit : string }

let base_commit = function
  | Given { commit; _ } | Merge_base { commit; _ } -> commit

let base_message = function
  | Given { revision; commit } ->
      Printf.sprintf "the base is %s, %s" revision commit
  | Merge_base { refname; commit } ->
      Printf.sprintf "the base is the merge base of HEAD and %s, %s" refname
        commit

let find_base repo manifest base =
  match base with
  | Some revision -> (
      match Git.commit_of repo revision with
      | Ok commit -> Ok (Given { revision; commit })
      | Error (Git.Bad_revision _) -> Error (Bad_base revision)
      | Error error -> Error (Repository error))
  | None -> (
      let name = Manifest.target manifest in
      match Git.resolve_target repo name with
      | Error (Git.Target_not_found _) -> Error (Target_not_found name)
      | Error error -> Error (Repository error)
      | Ok target -> (
          match Git.merge_base repo "HEAD" target.commit with
          | Ok commit -> Ok (Merge_base { refname = target.refname; commit })
          | Error (Git.Bad_revision _) -> Error No_head
          | Error (Git.No_merge_base _) -> Error (No_merge_base name)
          | Error error -> Error (Repository error)))

(* The documents of [files], read from [root] with a new engine, and
   the files that are not UTF-8 text, each list in the order of [files]. *)
let documents ~root files =
  let engine = Sinter_bridge.create () in
  Fun.protect
    ~finally:(fun () -> Sinter_bridge.close engine)
    (fun () ->
      match Markdown.create engine with
      | Error error -> Error (Reader error)
      | Ok reader ->
          Fun.protect
            ~finally:(fun () -> Markdown.close reader)
            (fun () ->
              List.fold_left
                (fun found file ->
                  let* documents, not_text = found in
                  match Text_file.read (Filename.concat root file) with
                  | Error error -> Error (Unreadable_file { file; error })
                  | Ok content -> (
                      match Markdown.read reader content with
                      | Ok document ->
                          Ok ((file, document) :: documents, not_text)
                      | Error (Markdown.Not_utf_8 _) ->
                          Ok (documents, file :: not_text)
                      | Error (Markdown.No_tree error) ->
                          Error (Unparsed_file { file; error })))
                (Ok ([], []))
                files
              |> Result.map (fun (documents, not_text) ->
                  (List.rev documents, List.rev not_text))))

let changed_paths repo commit =
  let* changes = repository (Git.diff repo ~base:commit) in
  Ok
    (List.filter_map
       (fun (path, change) ->
         match change with
         | Git.Modified [] -> None
         | Git.Added | Git.Deleted | Git.Binary | Git.Modified (_ :: _) ->
             Some path)
       changes)

type tree = {
  repo : Git.t;
  manifest : Manifest.t;
  location : string;
  base : base;
  documents : (string * Markdown.t) list;
  not_text : string list;
  warnings : string list;
}

let load ~env ~dir ~manifest ~base =
  let* repo = repository (Git.open_repo ~env dir) in
  let root = Git.root repo in
  let path, shown, missing =
    match manifest with
    | None -> (Filename.concat root "sinter.toml", "sinter.toml", No_manifest)
    | Some given ->
        ( (if Filename.is_relative given then Filename.concat dir given
           else given),
          given,
          Missing_manifest given )
  in
  let* manifest_value = load_manifest ~path ~shown ~missing in
  let* location =
    Result.map_error
      (fun reason -> Unreadable_manifest { path = shown; reason })
      (manifest_location ~root path)
  in
  let* all = repository (Git.files repo) in
  let files, not_utf_8 = List.partition Sinter_bridge.Utf_8.is_valid all in
  let packs = Manifest.packs manifest_value in
  let* () =
    match two_packs packs files with Some e -> Error e | None -> Ok ()
  in
  let markdown = markdown_files packs in
  let read_by_markdown file =
    Option.fold ~none:false ~some:(fun set -> Path_set.mem set file) markdown
  in
  let* () =
    match
      List.find_opt
        (fun file -> is_plan_path file && not (read_by_markdown file))
        files
    with
    | Some file -> Error (Plan_not_read file)
    | None -> Ok ()
  in
  let* () =
    match
      List.find_opt
        (fun (pack : Manifest.pack) -> not (String.equal pack.name "markdown"))
        packs
    with
    | Some pack -> Error (Pack_not_available pack.name)
    | None -> Ok ()
  in
  let* base = find_base repo manifest_value base in
  let* documents, not_text =
    documents ~root (List.filter read_by_markdown files)
  in
  Ok
    {
      repo;
      manifest = manifest_value;
      location;
      base;
      documents;
      not_text;
      warnings =
        List.map
          (fun path ->
            Printf.sprintf
              "warning: the path %s is not UTF-8, so sinter does not read the \
               file"
              (escape_path path))
          not_utf_8
        @ [ ledger_warning ];
    }

let index tree ~tool =
  let* key = repository (Git.tree_key tree.repo) in
  Ok
    (Facts.index ~tree:key ~base:(base_commit tree.base)
       ~target_branch:(Manifest.target tree.manifest)
       ~manifest:tree.location ~tool)

let run ~env ~dir ~manifest ~base ~tool =
  let* tree = load ~env ~dir ~manifest ~base in
  let* index = index tree ~tool in
  let facts = Facts.make tree.manifest tree.documents in
  let* changed =
    if Facts.needs_changes facts then
      changed_paths tree.repo (base_commit tree.base)
    else Ok []
  in
  Ok
    {
      warnings = tree.warnings;
      records = index :: Facts.records facts ~changed;
    }
