(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

type error =
  | Repository of Git.error
  | No_manifest
  | Missing_manifest of string
  | Unreadable_manifest of { path : string; reason : string }
  | Invalid_manifest of {
      path : string;
      text : string;
      errors : Manifest.error list;
    }
  | Two_packs of { file : string; pack : string; other : string }
  | Plan_not_read of string
  | Pack_not_available of string
  | Bad_base of string
  | Default_branch_not_found of string
  | No_merge_base of string
  | Shallow_clone of string
  | No_head
  | Unreadable_file of { file : string; error : Text_file.error }
  | Unparsed_file of { file : string; error : Sinter_bridge.Tree.error }
  | Unparsed_base_file of { file : string; error : Sinter_bridge.Tree.error }
  | Reader of Markdown.load_error

let ( let* ) = Result.bind

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
        "use git 2.43.7 or later; with such a git, "
        ^ Error_text.fault_of_sinter )
  | Git.File_error reason ->
      ( reason,
        "check that you can read and write the file, and that the disk has \
         space" )

let bug = Error_text.fault_of_sinter
let plain (fault, help) = { Error_text.fault; help; place = None }

let explain = function
  | Repository error -> [ plain (git_text error) ]
  | No_manifest ->
      [
        plain
          ( "no sinter.toml at the repository root",
            "create one, or name one with --manifest" );
      ]
  | Missing_manifest path ->
      [
        plain
          ( Printf.sprintf "no manifest at %s" path,
            "name a manifest that exists with --manifest" );
      ]
  | Unreadable_manifest { path; reason } ->
      [
        plain
          ( Printf.sprintf "cannot read the manifest %s: %s" path reason,
            "name a manifest that is a file that you can read" );
      ]
  | Invalid_manifest { path; text; errors } ->
      let lines = Line_index.make text in
      List.map (Manifest.explain ~path ~lines) errors
  | Two_packs { file; pack; other } ->
      [
        plain
          ( Printf.sprintf "%s is in the files of two packs, %s and %s" file
              pack other,
            "add a '!' glob to one of them" );
      ]
  | Plan_not_read file ->
      [
        plain
          ( Printf.sprintf
              "%s is under .plans/, and the pack markdown does not read it" file,
            "add \".plans/\" to the files of the pack markdown" );
      ]
  | Pack_not_available name ->
      [
        plain
          ( Printf.sprintf "the pack %s is not in the cache of packs" name,
            Printf.sprintf "run sinter pack add %s" name );
      ]
  | Bad_base revision ->
      [
        plain
          ( Printf.sprintf "the base '%s' names no commit" revision,
            "give --base a revision that names a commit" );
      ]
  | Default_branch_not_found name ->
      [
        plain
          ( Printf.sprintf "no branch '%s' exists here or on origin" name,
            Printf.sprintf
              "fetch it with git fetch origin %s:refs/remotes/origin/%s, or \
               set 'default-branch' in sinter.toml to the name of the default \
               branch"
              name name );
      ]
  | No_merge_base name ->
      [
        plain
          ( Printf.sprintf "HEAD and the branch '%s' have no common ancestor"
              name,
            "name a base with --base" );
      ]
  | Shallow_clone name ->
      [
        plain
          ( Printf.sprintf
              "this clone is shallow, so the merge base of HEAD and the branch \
               '%s' is not here"
              name,
            Printf.sprintf
              "fetch the whole history with git fetch --unshallow origin \
               %s:refs/remotes/origin/%s"
              name name );
      ]
  | No_head ->
      [
        plain
          ("HEAD names no commit", "make a commit, or name a base with --base");
      ]
  | Unreadable_file { file; error } ->
      [
        plain
          ( Text_file.message file error,
            "make the file readable, or leave it out of the files of the pack \
             markdown with a '!' glob" );
      ]
  | Unparsed_file { file; error } ->
      [
        plain
          ( file ^ ": " ^ Sinter_bridge.Tree.message error,
            "leave the file out of the files of the pack markdown with a '!' \
             glob" );
      ]
  | Unparsed_base_file { file; error } ->
      [
        plain
          ( file ^ " at the base: " ^ Sinter_bridge.Tree.message error,
            "name another base with --base" );
      ]
  | Reader (Markdown.Grammar error) ->
      [
        plain
          ( "the built-in grammar of markdown does not load: "
            ^ Sinter_bridge.Language.message error,
            bug );
      ]
  | Reader (Markdown.Query error) ->
      [
        plain
          ( "the built-in query of markdown does not compile: "
            ^ Sinter_bridge.Query.message error,
            bug );
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

let is_plan_path path =
  String.starts_with ~prefix:".plans/" path
  && String.ends_with ~suffix:".md" path

let load_manifest ~path ~shown ~missing =
  match Manifest.load path with
  | Ok manifest -> Ok manifest
  | Error Manifest.Missing -> Error missing
  | Error (Manifest.Unreadable reason) ->
      Error (Unreadable_manifest { path = shown; reason })
  | Error (Manifest.Invalid { text; errors }) ->
      Error (Invalid_manifest { path = shown; text; errors })

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

let short commit = String.sub commit 0 (min 7 (String.length commit))

let without_prefix refname =
  match
    List.find_opt
      (fun prefix -> String.starts_with ~prefix refname)
      [ "refs/remotes/"; "refs/heads/" ]
  with
  | Some prefix ->
      String.sub refname (String.length prefix)
        (String.length refname - String.length prefix)
  | None -> refname

let base_note = function
  | Given { revision; commit } ->
      Printf.sprintf "base %s, from --base %s" (short commit)
        (Display.clean revision)
  | Merge_base { refname; commit } ->
      Printf.sprintf "base %s, the merge base of HEAD and %s" (short commit)
        (Display.clean (without_prefix refname))

let unless_shallow repo name error =
  match Git.is_shallow repo with
  | Ok true -> Error (Shallow_clone name)
  | Ok false -> Error error
  | Error failure -> Error (Repository failure)

let find_base repo manifest base =
  match base with
  | Some revision -> (
      match Git.commit_of repo revision with
      | Ok commit -> Ok (Given { revision; commit })
      | Error (Git.Bad_revision _) -> Error (Bad_base revision)
      | Error error -> Error (Repository error))
  | None -> (
      let name = Manifest.default_branch manifest in
      match Git.resolve_default_branch repo name with
      | Error (Git.Default_branch_not_found _) ->
          unless_shallow repo name (Default_branch_not_found name)
      | Error error -> Error (Repository error)
      | Ok branch -> (
          match Git.merge_base repo "HEAD" branch.commit with
          | Ok commit -> Ok (Merge_base { refname = branch.refname; commit })
          | Error (Git.Bad_revision _) -> Error No_head
          | Error (Git.No_merge_base _) ->
              unless_shallow repo name (No_merge_base name)
          | Error error -> Error (Repository error)))

let with_reader f =
  let engine = Sinter_bridge.create () in
  Fun.protect
    ~finally:(fun () -> Sinter_bridge.close engine)
    (fun () ->
      match Markdown.create engine with
      | Error error -> Error (Reader error)
      | Ok reader ->
          Fun.protect
            ~finally:(fun () -> Markdown.close reader)
            (fun () -> f reader))

let documents ?phases reader ~root files =
  List.fold_left
    (fun found file ->
      let* documents, not_text = found in
      match
        Allocation.measure phases "read" (fun () ->
            Text_file.read (Filename.concat root file))
      with
      | Error error -> Error (Unreadable_file { file; error })
      | Ok content -> (
          match
            Allocation.measure phases "parse" (fun () ->
                Markdown.read reader content)
          with
          | Ok document -> Ok ((file, document) :: documents, not_text)
          | Error (Markdown.Not_utf_8 offset) ->
              Ok (documents, (file, offset) :: not_text)
          | Error (Markdown.No_tree error) ->
              Error (Unparsed_file { file; error })))
    (Ok ([], []))
    files
  |> Result.map (fun (documents, not_text) ->
      (List.rev documents, List.rev not_text))

let changed_paths repo ~files commit =
  let* base = repository (Git.read_base repo commit) in
  let* changes = repository (Git.diff repo ~files ~base) in
  Ok
    (List.filter_map
       (fun (path, change) ->
         match change with
         | Git.Modified (Git.Text []) -> None
         | Git.Added _ | Git.Deleted _
         | Git.Modified (Git.Binary | Git.Text (_ :: _)) ->
             Some path)
       changes)

type tree = {
  repo : Git.t;
  file_set : Git.file_set;
  manifest : Manifest.t;
  location : string;
  base : base;
  documents : (string * Markdown.t) list;
  not_text : (string * int) list;
  warnings : string list;
}

let prepare ~env ~dir ~manifest ~base =
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
  let* file_set = repository (Git.files repo) in
  let files, not_utf_8 =
    List.partition Sinter_bridge.Utf_8.is_valid (Git.paths file_set)
  in
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
  Ok
    ( repo,
      file_set,
      root,
      manifest_value,
      location,
      base,
      read_by_markdown,
      List.filter read_by_markdown files,
      not_utf_8 )

let not_utf_8_warning path =
  Printf.sprintf "the path %s is not UTF-8, so sinter does not read the file"
    (Display.clean (escape_path path))

type base_manifest = Outside | Absent | Unchanged | Changed of string

type compared = {
  diff : (string * Git.change) list;
  base_documents : (string * Markdown.t) list;
  base_not_text : (string * int) list;
  base_manifest : base_manifest;
}

module Paths = Map.Make (String)

type held = Document of Markdown.t | Not_text of int

let changes_content = function
  | Git.Modified (Git.Text []) -> false
  | Git.Added _ | Git.Deleted _ | Git.Modified (Git.Binary | Git.Text (_ :: _))
    ->
      true

let read_blobs reader repo wanted ~manifest =
  let parse acc _ content =
    match acc with
    | Error _ -> acc
    | Ok (documents, not_text, [], _) ->
        Ok (documents, not_text, [], Some content)
    | Ok (documents, not_text, file :: rest, found) -> (
        match Markdown.read reader content with
        | Ok document ->
            Ok ((file, document) :: documents, not_text, rest, found)
        | Error (Markdown.Not_utf_8 offset) ->
            Ok (documents, (file, offset) :: not_text, rest, found)
        | Error (Markdown.No_tree error) ->
            Error (Unparsed_base_file { file; error }))
  in
  let* read =
    repository
      (Git.fold_blobs repo
         (List.map snd wanted @ Option.to_list manifest)
         ~init:(Ok ([], [], List.map fst wanted, None))
         ~f:parse)
  in
  Result.map
    (fun (documents, not_text, _, found) -> (documents, not_text, found))
    read

let base_files ~repo ~file_set ~commit ~read_by_markdown ~location =
  let* base = repository (Git.read_base repo commit) in
  let* diff = repository (Git.diff repo ~files:file_set ~base) in
  let files = Git.base_files base in
  let manifest = List.assoc_opt location files in
  let files, not_utf_8 =
    List.partition (fun (path, _) -> Sinter_bridge.Utf_8.is_valid path) files
  in
  Ok
    ( diff,
      List.filter (fun (path, _) -> read_by_markdown path) files,
      List.map fst not_utf_8,
      manifest )

let read_base reader ~repo ~diff ~files ~documents ~not_text ~location ~manifest
    =
  let changed =
    List.fold_left
      (fun changed (path, change) ->
        if changes_content change then Paths.add path () changed else changed)
      Paths.empty diff
  in
  let held =
    List.fold_left
      (fun held (path, offset) -> Paths.add path (Not_text offset) held)
      (List.fold_left
         (fun held (path, document) -> Paths.add path (Document document) held)
         Paths.empty documents)
      not_text
  in
  let reused, wanted =
    List.partition_map
      (fun (path, id) ->
        match Paths.find_opt path held with
        | Some found when not (Paths.mem path changed) -> Left (path, found)
        | Some _ | None -> Right (path, id))
      files
  in
  let* read_documents, read_not_text, found =
    read_blobs reader repo wanted
      ~manifest:(if Paths.mem location changed then manifest else None)
  in
  let by_path list = List.sort (fun (a, _) (b, _) -> String.compare a b) list in
  Ok
    {
      diff;
      base_documents =
        by_path
          (read_documents
          @ List.filter_map
              (function
                | path, Document document -> Some (path, document)
                | _, Not_text _ -> None)
              reused);
      base_not_text =
        by_path
          (read_not_text
          @ List.filter_map
              (function
                | path, Not_text offset -> Some (path, offset)
                | _, Document _ -> None)
              reused);
      base_manifest =
        (if Filename.is_relative location then
           match (manifest, found) with
           | None, _ -> Absent
           | Some _, Some text -> Changed text
           | Some _, None -> Unchanged
         else Outside);
    }

let assemble ~repo ~file_set ~manifest ~location ~base ~documents ~not_text
    ~not_utf_8 =
  {
    repo;
    file_set;
    manifest;
    location;
    base;
    documents;
    not_text;
    warnings =
      List.map not_utf_8_warning (List.sort_uniq String.compare not_utf_8);
  }

let load ?phases ~env ~dir ~manifest ~base () =
  let* repo, file_set, root, manifest, location, base, _, files, not_utf_8 =
    Allocation.measure phases "repository" (fun () ->
        prepare ~env ~dir ~manifest ~base)
  in
  let* documents, not_text =
    with_reader (fun reader -> documents ?phases reader ~root files)
  in
  Ok
    (assemble ~repo ~file_set ~manifest ~location ~base ~documents ~not_text
       ~not_utf_8)

let load_with_base ?phases ~env ~dir ~manifest ~base () =
  let* ( repo,
         file_set,
         root,
         manifest,
         location,
         base,
         read_by_markdown,
         files,
         not_utf_8 ) =
    Allocation.measure phases "repository" (fun () ->
        prepare ~env ~dir ~manifest ~base)
  in
  let* diff, base_files, base_not_utf_8, base_manifest =
    Allocation.measure phases "base-read" (fun () ->
        base_files ~repo ~file_set ~commit:(base_commit base) ~read_by_markdown
          ~location)
  in
  let* documents, not_text, compared =
    with_reader (fun reader ->
        let* documents, not_text = documents ?phases reader ~root files in
        let* compared =
          Allocation.measure phases "base-read" (fun () ->
              read_base reader ~repo ~diff ~files:base_files ~documents
                ~not_text ~location ~manifest:base_manifest)
        in
        Ok (documents, not_text, compared))
  in
  Ok
    ( assemble ~repo ~file_set ~manifest ~location ~base ~documents ~not_text
        ~not_utf_8:(not_utf_8 @ base_not_utf_8),
      compared )

let ledger_ref = "refs/sinter/ledger"

let ledger_warning tree facts =
  match Facts.plans facts with
  | [] -> None
  | _ :: _ -> (
      match Git.commit_of tree.repo ledger_ref with
      | Error (Git.Bad_revision _) ->
          Some "no ledger found, so every plan counts as open"
      | Ok _ | Error _ -> None)

let index ?(mode = Mode.Tree) tree ~tool =
  let* key = repository (Git.tree_key tree.repo) in
  Ok
    (Facts.index ~tree:key ~base:(base_commit tree.base)
       ~default_branch:(Manifest.default_branch tree.manifest)
       ~manifest:tree.location ~tool ~mode)

let run ?phases ~env ~dir ~manifest ~base ~tool () =
  let* tree = load ?phases ~env ~dir ~manifest ~base () in
  let* index =
    Allocation.measure phases "repository" (fun () -> index tree ~tool)
  in
  let facts =
    Allocation.measure phases "facts" (fun () ->
        Facts.make tree.manifest tree.documents)
  in
  let* changed =
    Allocation.measure phases "repository" (fun () ->
        if Facts.needs_changes facts then
          changed_paths tree.repo ~files:tree.file_set (base_commit tree.base)
        else Ok [])
  in
  let records =
    Allocation.measure phases "records" (fun () -> Facts.records facts ~changed)
  in
  Ok
    {
      warnings = tree.warnings @ Option.to_list (ledger_warning tree facts);
      records = index :: records;
    }
