(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

type error =
  | Repository of Git.error
  | No_manifest
  | Missing_manifest of string
  | Unreadable_manifest of { path : string; reason : string }
  | Manifest_is_a_link of string
  | Manifest_not_regular of string
  | Manifest_not_utf_8 of string
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
  | Unreadable_file of { file : string; error : Repo_file.error }
  | Unparsed_file of { file : string; error : Sinter_bridge.Tree.error }
  | Unparsed_base_file of { file : string; error : Sinter_bridge.Tree.error }
  | Reader of Markdown.load_error
  | Ledger of Ledger.error

let ( let* ) = Result.bind

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

let bug = Error_text.fault_of_sinter
let plain (fault, help) = { Error_text.fault; help; place = None }

let explain = function
  | Repository error -> [ Error_text.of_git error ]
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
  | Manifest_is_a_link path ->
      [
        plain
          ( Repo_file.message path Repo_file.Symbolic_link,
            "commit the manifest as a regular file" );
      ]
  | Manifest_not_regular path ->
      [
        plain
          ( Repo_file.message path Repo_file.Not_regular,
            "commit the manifest as a regular file" );
      ]
  | Manifest_not_utf_8 path ->
      [
        plain
          ( Printf.sprintf "the path of the manifest %s is not UTF-8"
              (Display.clean (escape_path path)),
            "move the manifest to a path that is UTF-8" );
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
          ( Repo_file.message file error,
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
  | Ledger error -> [ Ledger.explain error ]

type outcome = { warnings : string list; records : Jsonl.record list }

let repository result = Result.map_error (fun error -> Repository error) result

let is_plan_path path =
  String.starts_with ~prefix:".plans/" path
  && String.ends_with ~suffix:".md" path

let load_manifest ~root ~place ~shown ~missing =
  let unreadable reason =
    Error (Unreadable_manifest { path = shown; reason })
  in
  let invalid text errors =
    Error (Invalid_manifest { path = shown; text; errors })
  in
  match place with
  | Repo_file.Inside path -> (
      match Repo_file.read ~root path with
      | Ok text -> (
          match Manifest.of_string text with
          | Ok manifest -> Ok manifest
          | Error errors -> invalid text errors)
      | Error (Repo_file.Nothing_at_path | Repo_file.Not_a_repository_path) ->
          Error missing
      | Error Repo_file.Symbolic_link -> Error (Manifest_is_a_link shown)
      | Error Repo_file.Not_regular -> Error (Manifest_not_regular shown)
      | Error (Repo_file.Cannot_open reason | Repo_file.Cannot_read reason) ->
          unreadable reason)
  | Repo_file.Outside path -> (
      match Manifest.load path with
      | Ok manifest -> Ok manifest
      | Error Manifest.Missing -> Error missing
      | Error (Manifest.Unreadable reason) -> unreadable reason
      | Error (Manifest.Invalid { text; errors }) -> invalid text errors)

let real_path path =
  match Unix.realpath path with
  | real -> real
  | exception Unix.Unix_error (Unix.ENOENT, _, _) ->
      Filename.concat
        (Unix.realpath (Filename.dirname path))
        (Filename.basename path)

let outside_location ~root path =
  match (Unix.realpath root, real_path path) with
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
        Allocation.measure phases "read" (fun () -> Repo_file.read ~root file)
      with
      | Error error -> Error (Unreadable_file { file; error })
      | Ok content -> (
          match
            Allocation.measure phases "parse" (fun () ->
                Markdown.read ~texts:(Facts.may_hold_plan file) reader content)
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

type tree = {
  repo : Git.t;
  file_set : Git.file_set;
  manifest : Manifest.t;
  location : string;
  base : base;
  documents : (string * Markdown.t) list;
  not_text : (string * int) list;
  warnings : string list;
  deliveries : Delivery_line.found list;
}

let prepare ~env ~dir ~manifest ~base =
  let* repo = repository (Git.open_repo ~env dir) in
  let root = Git.root repo in
  let shown = Option.value manifest ~default:"sinter.toml" in
  let unreadable reason = Unreadable_manifest { path = shown; reason } in
  let* place =
    match manifest with
    | None -> Ok (Repo_file.Inside "sinter.toml")
    | Some given ->
        Result.map_error unreadable (Repo_file.place ~root ~dir given)
  in
  let missing =
    match manifest with
    | None -> No_manifest
    | Some given -> Missing_manifest given
  in
  let* manifest_value = load_manifest ~root ~place ~shown ~missing in
  let* location =
    match place with
    | Repo_file.Inside path -> Ok path
    | Repo_file.Outside path ->
        Result.map_error unreadable (outside_location ~root path)
  in
  let* () =
    if Sinter_bridge.Utf_8.is_valid location then Ok ()
    else Error (Manifest_not_utf_8 location)
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
  let* messages = repository (Git.messages repo ~base:(base_commit base)) in
  let deliveries =
    List.concat_map
      (fun (commit, message) -> Delivery_line.read ~commit message)
      messages
  in
  Ok
    ( repo,
      file_set,
      root,
      manifest_value,
      location,
      base,
      read_by_markdown,
      List.filter read_by_markdown files,
      not_utf_8,
      deliveries )

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
        match
          Markdown.read ~texts:(Facts.may_hold_plan file) reader content
        with
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
    ~not_utf_8 ~deliveries =
  {
    deliveries;
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
  let* ( repo,
         file_set,
         root,
         manifest,
         location,
         base,
         _,
         files,
         not_utf_8,
         deliveries ) =
    Allocation.measure phases "repository" (fun () ->
        prepare ~env ~dir ~manifest ~base)
  in
  let* documents, not_text =
    with_reader (fun reader -> documents ?phases reader ~root files)
  in
  Ok
    (assemble ~repo ~file_set ~manifest ~location ~base ~documents ~not_text
       ~not_utf_8 ~deliveries)

let load_with_base ?phases ~env ~dir ~manifest ~base () =
  let* ( repo,
         file_set,
         root,
         manifest,
         location,
         base,
         read_by_markdown,
         files,
         not_utf_8,
         deliveries ) =
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
        ~not_utf_8:(not_utf_8 @ base_not_utf_8)
        ~deliveries,
      compared )

let ledger ?phases tree depth =
  Allocation.measure phases "repository" (fun () ->
      Result.map_error (fun error -> Ledger error) (Ledger.read tree.repo depth))

let ledger_warnings ledger facts =
  match ledger with
  | Some ledger -> Option.to_list (Ledger.warning ledger)
  | None -> (
      match Facts.plans facts with
      | [] -> []
      | _ :: _ -> [ "no ledger found, so every plan counts as open" ])

let entries ledger = Option.fold ~none:[] ~some:Ledger.entries ledger

let index ?(mode = Mode.Tree) tree ~ledger ~tool =
  let* key = repository (Git.tree_key tree.repo) in
  Ok
    (Facts.index ~tree:key ~base:(base_commit tree.base)
       ~default_branch:(Manifest.default_branch tree.manifest)
       ~manifest:tree.location
       ~ledger:(Option.map Ledger.tip ledger)
       ~tool ~mode)

let run ?phases ~env ~dir ~manifest ~base ~tool () =
  let* tree = load ?phases ~env ~dir ~manifest ~base () in
  let* ledger = ledger ?phases tree Ledger.Tip in
  let* index =
    Allocation.measure phases "repository" (fun () -> index tree ~ledger ~tool)
  in
  let facts =
    Allocation.measure phases "facts" (fun () ->
        Facts.make tree.manifest ~ledger:(entries ledger) tree.documents)
  in
  let records =
    Allocation.measure phases "records" (fun () ->
        Facts.records ~deliveries:tree.deliveries facts)
  in
  Ok
    {
      warnings = tree.warnings @ ledger_warnings ledger facts;
      records = index :: records;
    }
