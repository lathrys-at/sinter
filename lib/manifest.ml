(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

let specification = Major_minor.make 1 0

let settings =
  List.map
    (fun (path, major, minor) ->
      (String.split_on_char '.' path, Major_minor.make major minor))
    [
      ("sinter-spec", 1, 0);
      ("default-branch", 1, 0);
      ("scan.packs.<name>.files", 1, 0);
      ("scan.packs.<name>.version", 1, 0);
      ("scan.packs.<name>.runners.<runner>", 1, 0);
      ("scan.packs.<name>.runners.<runner>.<key>", 1, 0);
      ("scan.namespaces.<ns>", 1, 0);
      ("paths.exempt", 1, 0);
      ("paths.historical", 1, 0);
      ("paths.<kind>", 1, 0);
      ("proof.<kind>", 1, 0);
      ("proof.agent-markers", 1, 0);
      ("proof.verifies", 1, 0);
      ("proof.step", 1, 0);
      ("check.warn-only", 1, 0);
      ("check.tiers.<gate>.<class>", 1, 0);
    ]

let varies name = String.starts_with ~prefix:"<" name

let fixed_places =
  List.concat_map
    (fun (pattern, _) ->
      List.mapi
        (fun i name -> (name, List.filteri (fun j _ -> j < i) pattern))
        pattern)
    settings
  |> List.filter (fun (name, _) -> not (varies name))
  |> List.sort_uniq compare

let rec path_matches ~table pattern path =
  match (pattern, path) with
  | [], [] -> true
  | p :: ps, n :: ns ->
      (if varies p then not (List.mem (n, table) fixed_places) else p = n)
      && path_matches ~table:(table @ [ p ]) ps ns
  | _ -> false

let since path =
  List.find_map
    (fun (pattern, version) ->
      if path_matches ~table:[] pattern path then Some version else None)
    settings

let is_table_name name =
  List.exists
    (fun (pattern, _) ->
      List.exists (String.equal name)
        (List.filteri (fun i _ -> i < List.length pattern - 1) pattern))
    settings

type kind = Req | Design | Decision | Plan

let kind_name = function
  | Req -> "req"
  | Design -> "design"
  | Decision -> "decision"
  | Plan -> "plan"

let kinds = [ Req; Design; Decision; Plan ]
let location_kinds = [ Req; Design; Decision ]

type approval = Declaration | Approval

let approval_name = function
  | Declaration -> "declaration"
  | Approval -> "approval"

type verifies = Whole_run | Each_test

let verifies_name = function
  | Whole_run -> "whole-run"
  | Each_test -> "each-test"

type step = Change | Step_approval | Promises

let step_name = function
  | Change -> "change"
  | Step_approval -> "approval"
  | Promises -> "promises"

type expected = A_string | A_version | True_or_false | Strings | A_table

type problem =
  | Syntax of Toml.error
  | Not_a_version of { key : string list; text : string }
  | Sinter_spec_too_new of Major_minor.t
  | Sinter_spec_major_too_old of Major_minor.t
  | Key_too_new of {
      key : string list;
      since : Major_minor.t;
      sinter_spec : Major_minor.t;
    }
  | Unknown_key of {
      name : string;
      table : string list;
      nearest : string option;
    }
  | Misplaced_key of { name : string; place : string list }
  | Bad_pack_name of string
  | Bad_namespace of string
  | Unknown_gate of { name : string; nearest : string option }
  | Unknown_class of {
      name : string;
      gate : Finding_class.gate;
      nearest : string option;
    }
  | No_tier_at_gate of {
      finding_class : Finding_class.t;
      gate : Finding_class.gate;
    }
  | Never_blocks
  | No_tier_at_any_gate
  | Plan_location
  | Markdown_version
  | Markdown_runners
  | Bad_runner_name of string
  | Runner_in_two_packs of { runner : string; pack : string; other : string }
  | Wrong_type of {
      key : string list;
      expected : expected;
      found : Toml.Kind.t;
    }
  | Wrong_member_type of { key : string list; found : Toml.Kind.t }
  | Not_a_branch of { name : string; error : Branch_name.error }
  | Bad_glob of { member : string; error : Glob.error }
  | Repeated_member of { key : string list; member : string }
  | No_plain_glob of string list
  | Missing_files of string
  | Missing_version of string
  | Bad_id_pattern of { namespace : string; error : Id_pattern.error }
  | Unknown_value of {
      key : string list;
      value : string;
      choices : string list;
      nearest : string option;
    }
  | Bad_marker of string

type error = At of Toml.span * problem | No_pack

let last key = match List.rev key with name :: _ -> name | [] -> ""

let table_name path =
  "["
  ^ String.concat "."
      (List.map
         (fun name -> if varies name then name else Toml.render_path [ name ])
         path)
  ^ "]"

let in_table = function
  | [] -> "at the top level"
  | path -> "in " ^ table_name path

let choice words =
  match List.rev words with
  | [] -> ""
  | [ only ] -> only
  | [ b; a ] -> a ^ " or " ^ b
  | final :: rest -> String.concat ", " (List.rev rest) ^ ", or " ^ final

let did_you_mean ~quote name = "did you mean " ^ quote name ^ "?"

let expected_text = function
  | A_string -> "a string"
  | A_version -> "a version of the form MAJOR.MINOR, such as \"1.0\""
  | True_or_false -> "true or false"
  | Strings -> "an array of strings"
  | A_table -> "a table"

let name_rule ~examples =
  "lower-case letters and digits, in words joined by '-', such as " ^ examples

let nearest_or ~quote nearest otherwise =
  match nearest with Some name -> did_you_mean ~quote name | None -> otherwise

let remove = "remove this key"

let split ~otherwise message =
  let length = String.length message in
  let rec find index =
    if index + 1 >= length then (message, otherwise)
    else if message.[index] = ';' && message.[index + 1] = ' ' then
      ( String.sub message 0 index,
        String.sub message (index + 2) (length - index - 2) )
    else find (index + 1)
  in
  find 0

let problem_text = function
  | Syntax error ->
      split ~otherwise:"write the text here as TOML 1.1.0 allows"
        (Toml.error_message error)
  | Not_a_version { key; text } ->
      ( Printf.sprintf "%s takes %s, not %s"
          (Toml.quote (last key))
          (expected_text A_version) (Toml.basic_string text),
        "write the version as two numbers joined by '.'" )
  | Sinter_spec_too_new version ->
      ( Printf.sprintf
          "this manifest needs specification %s, and this sinter implements %s"
          (Major_minor.to_string version)
          (Major_minor.to_string specification),
        "install a newer sinter" )
  | Sinter_spec_major_too_old version ->
      ( Printf.sprintf
          "this manifest is for specification %s, and this sinter implements \
           %s, a new major version that can change the meaning of a key"
          (Major_minor.to_string version)
          (Major_minor.to_string specification),
        Printf.sprintf
          "read the notes on the changes in specification %s, then update the \
           manifest and its 'sinter-spec'"
          (Major_minor.to_string specification) )
  | Key_too_new { key; since; sinter_spec } ->
      ( Printf.sprintf
          "%s needs specification %s, and the manifest states sinter-spec = %s"
          (Toml.quote (Toml.render_path key))
          (Major_minor.to_string since)
          (Toml.basic_string (Major_minor.to_string sinter_spec)),
        Printf.sprintf "write sinter-spec = %s"
          (Toml.basic_string (Major_minor.to_string since)) )
  | Unknown_key { name; table; nearest } ->
      ( Printf.sprintf "unknown key %s %s" (Toml.quote name) (in_table table),
        nearest_or ~quote:Toml.quote nearest
          "remove this key, or correct its name" )
  | Misplaced_key { name; place = [] } when is_table_name name ->
      ( Printf.sprintf "%s is a table of the top level" (Toml.quote name),
        Printf.sprintf "write its keys under the header [%s]" name )
  | Misplaced_key { name; place = [] } ->
      ( Printf.sprintf "%s belongs at the top level" (Toml.quote name),
        "write it above the first table header" )
  | Misplaced_key { name; place } ->
      ( Printf.sprintf "%s belongs in %s" (Toml.quote name) (table_name place),
        Printf.sprintf "move it to %s" (table_name place) )
  | Bad_pack_name name ->
      ( Printf.sprintf "%s is not a pack name" (Toml.quote name),
        "write a pack name of " ^ name_rule ~examples:"'ocaml' or 'tree-sitter'"
      )
  | Bad_namespace name ->
      ( Printf.sprintf "%s is not a namespace" (Toml.quote name),
        "write a namespace of " ^ name_rule ~examples:"'gh' or 'jira'" )
  | Unknown_gate { name; nearest } ->
      ( Printf.sprintf "unknown gate %s in [check.tiers]" (Toml.quote name),
        nearest_or ~quote:Toml.quote nearest
          ("write one of the gates "
          ^ choice
              (List.map
                 (fun gate -> Toml.quote (Finding_class.gate_name gate))
                 Finding_class.gates)) )
  | Unknown_class { name; gate; nearest } ->
      ( Printf.sprintf "unknown finding class %s in [check.tiers.%s]"
          (Toml.quote name)
          (Finding_class.gate_name gate),
        nearest_or ~quote:Toml.quote nearest
          "write the name of a built-in finding class" )
  | No_tier_at_gate { finding_class; gate } ->
      ( Printf.sprintf "%s takes no tier at the gate %s"
          (Toml.quote (Finding_class.name finding_class))
          (Toml.quote (Finding_class.gate_name gate)),
        remove )
  | Never_blocks ->
      ( "'config-changed' takes no tier; it always reports and never blocks",
        remove )
  | No_tier_at_any_gate -> ("'pack-mismatch' takes no tier at any gate", remove)
  | Plan_location ->
      ("'plan' takes no location; plan files always live under .plans/", remove)
  | Markdown_version ->
      ( "the pack markdown is built into sinter and takes no version",
        "remove the version" )
  | Markdown_runners ->
      ( "the pack markdown is built into sinter and has no runner",
        "remove the runners" )
  | Bad_runner_name name ->
      ( Printf.sprintf "%s is not a runner name" (Toml.quote name),
        "write a runner name of "
        ^ name_rule ~examples:"'vitest' or 'cargo-nextest'" )
  | Runner_in_two_packs { runner; pack; other } ->
      ( Printf.sprintf "%s is in the runners of two packs, %s and %s"
          (Toml.quote runner)
          (Toml.render_path [ other ])
          (Toml.render_path [ pack ]),
        "remove it from one of them" )
  | Wrong_type { key; expected; found } ->
      ( Printf.sprintf "%s takes %s, not %s"
          (Toml.quote (last key))
          (expected_text expected) (Toml.Kind.name found),
        "write " ^ expected_text expected )
  | Wrong_member_type { key; found } ->
      ( Printf.sprintf "%s takes an array of strings, and this member is %s"
          (Toml.quote (last key))
          (Toml.Kind.name found),
        "write the member as a string" )
  | Not_a_branch { name; error } ->
      let reason, help =
        split ~otherwise:"write the name of the default branch"
          (Branch_name.message error)
      in
      ( Printf.sprintf "%s is not a branch name; %s" (Toml.basic_string name)
          reason,
        help )
  | Bad_glob { member; error } ->
      let reason, help =
        split ~otherwise:"write a glob such as \"docs/**/*.md\""
          (Glob.message error)
      in
      ( Printf.sprintf "%s is not a glob: %s" (Toml.basic_string member) reason,
        help )
  | Repeated_member { key; member } ->
      ( Printf.sprintf "%s occurs twice in %s" (Toml.basic_string member)
          (Toml.quote (last key)),
        "remove this member" )
  | No_plain_glob key ->
      ( Printf.sprintf "%s holds only '!' globs, so it holds no path"
          (Toml.quote (last key)),
        "add a glob without '!'" )
  | Missing_files pack ->
      ( Printf.sprintf
          "the pack %s needs 'files', the globs of the files that it reads"
          (Toml.render_path [ pack ]),
        Printf.sprintf "add 'files' to the pack %s" (Toml.render_path [ pack ])
      )
  | Missing_version pack ->
      ( Printf.sprintf
          "the pack %s needs 'version', the release that the repository uses"
          (Toml.render_path [ pack ]),
        Printf.sprintf "add 'version' to the pack %s, such as \"1.0\""
          (Toml.render_path [ pack ]) )
  | Bad_id_pattern { namespace; error } ->
      split
        ~otherwise:
          (Printf.sprintf "correct the id pattern of the namespace %s"
             (Toml.quote namespace))
        (Id_pattern.message error)
  | Unknown_value { key; value; choices; nearest } ->
      ( Printf.sprintf "%s takes %s, not %s"
          (Toml.quote (last key))
          (choice (List.map Toml.basic_string choices))
          (Toml.basic_string value),
        nearest_or ~quote:Toml.basic_string nearest
          ("write " ^ choice (List.map Toml.basic_string choices)) )
  | Bad_marker name ->
      ( Printf.sprintf "%s is not a name of an environment variable"
          (Toml.basic_string name),
        "write a name of letters, digits, and '_' that does not start with a \
         digit" )

let line_of lines number =
  Option.bind lines (fun lines ->
      if number >= 1 && number <= Line_index.count lines then
        Some (Line_index.content lines number)
      else None)

let explain ~path ?lines = function
  | At (span, problem) ->
      let fault, help = problem_text problem in
      {
        Error_text.fault;
        help;
        place =
          Some { Error_text.path; span; line = line_of lines span.start.line };
      }
  | No_pack ->
      {
        Error_text.fault = path ^ " names no pack";
        help =
          "add a line such as packs.markdown.files = [\"**/*.md\"] under [scan]";
        place = None;
      }

type runner = {
  name : string;
  at : Toml.span;
  settings : (Toml.key * Toml.node) list;
}

type pack = {
  name : string;
  files : Path_set.t;
  version : Major_minor.t option;
  runners : runner list;
}

type t = {
  document : Toml.table;
  sinter_spec : Major_minor.t option;
  default_branch : string;
  packs : pack list;
  namespaces : (string * Id_pattern.t) list;
  warn_only : bool;
  tiers : (Finding_class.gate * Finding_class.t * Finding_class.tier) list;
  historical : Path_set.t;
  exempt : Path_set.t;
  locations : (kind * Path_set.t) list;
  approvals : (kind * approval) list;
  agent_markers : string list;
  verifies : verifies;
  step : step;
}

type reading = {
  mutable names_errors : (Toml.span * problem) list;
  mutable value_errors : (Toml.span * problem) list;
  mutable default_branch : string option;
  mutable pack_keys : (string * Toml.span) list;
  mutable files : (string * Path_set.t option) list;
  mutable versions : (string * Major_minor.t option) list;
  mutable runners : (string * (Toml.key * Toml.table)) list;
  mutable namespaces : (string * Id_pattern.t) list;
  mutable warn_only : bool;
  mutable tiers :
    (Finding_class.gate * Finding_class.t * Finding_class.tier) list;
  mutable historical : Path_set.t;
  mutable exempt : Path_set.t;
  mutable locations : (kind * Path_set.t) list;
  mutable approvals : (kind * approval) list;
  mutable agent_markers : string list;
  mutable verifies : verifies;
  mutable step : step;
}

type place =
  | Fixed of (string * place) list
  | Varying of (Toml.key -> (place, problem) result)
  | Refused of problem
  | Kept of (Toml.table -> unit)
  | Text of (Toml.node -> string -> unit)
  | Flag of (bool -> unit)
  | Texts of (Toml.node -> (Toml.node * string) list -> unit)

let names_error reading span problem =
  reading.names_errors <- (span, problem) :: reading.names_errors

let value_error reading span problem =
  reading.value_errors <- (span, problem) :: reading.value_errors

let one_character (position : Toml.position) =
  {
    Toml.start = position;
    stop = { position with column = position.column + 1 };
  }

let inside node offset =
  match Toml.string_position node offset with
  | Some position -> one_character position
  | None -> Toml.span node

let is_name_char c = (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9')

let is_name name =
  name <> ""
  && name.[0] >= 'a'
  && name.[0] <= 'z'
  && List.for_all
       (fun word -> word <> "" && String.for_all is_name_char word)
       (String.split_on_char '-' name)

let is_variable_name name =
  let letter c = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c = '_' in
  name <> ""
  && letter name.[0]
  && String.for_all (fun c -> letter c || (c >= '0' && c <= '9')) name

let misplaced name =
  List.assoc_opt name fixed_places
  |> Option.map (fun place -> Misplaced_key { name; place })

let unknown_key ~table ~valid name =
  match misplaced name with
  | Some problem -> problem
  | None ->
      Unknown_key { name; table; nearest = Edit_distance.nearest name valid }

module Names = Set.Make (String)
module By_name = Map.Make (String)

let first_repeated texts =
  let rec go seen = function
    | [] -> []
    | (node, text) :: rest ->
        if Names.mem text seen then (node, text) :: go seen rest
        else go (Names.add text seen) rest
  in
  go Names.empty texts

let read_path_set reading ~key array members set =
  match Path_set.of_strings (List.map snd members) with
  | Ok path_set -> set path_set
  | Error errors ->
      let members = Array.of_list members in
      List.iter
        (fun error ->
          match error with
          | Path_set.Bad_glob { index; start = offset; error } ->
              let node, member = members.(index) in
              value_error reading
                (inside node (offset + Glob.error_offset error))
                (Bad_glob { member; error })
          | Path_set.Repeated { index; member } ->
              value_error reading
                (Toml.span (fst members.(index)))
                (Repeated_member { key; member })
          | Path_set.No_plain_glob ->
              value_error reading (Toml.span array) (No_plain_glob key))
        errors

let path_set reading key set =
  Texts (fun array members -> read_path_set reading ~key array members set)

let word reading ~key choices name_of found =
  Text
    (fun node value ->
      match List.find_opt (fun choice -> name_of choice = value) choices with
      | Some choice -> found choice
      | None ->
          let names = List.map name_of choices in
          value_error reading (Toml.span node)
            (Unknown_value
               {
                 key;
                 value;
                 choices = names;
                 nearest = Edit_distance.nearest value names;
               }))

let pack_place reading (key : Toml.key) =
  let name = key.name in
  let files_key = [ "scan"; "packs"; name; "files" ] in
  let files =
    ( "files",
      Texts
        (fun array members ->
          let files = ref None in
          read_path_set reading ~key:files_key array members (fun set ->
              files := Some set);
          if members <> [] then reading.files <- (name, !files) :: reading.files)
    )
  in
  if name = "markdown" then
    Fixed
      [
        files;
        ("version", Refused Markdown_version);
        ("runners", Refused Markdown_runners);
      ]
  else
    let version =
      ( "version",
        Text
          (fun node value ->
            let version = Major_minor.of_string value in
            reading.versions <- (name, version) :: reading.versions;
            if version = None then
              value_error reading (Toml.span node)
                (Not_a_version
                   { key = [ "scan"; "packs"; name; "version" ]; text = value }))
      )
    and runners =
      ( "runners",
        Varying
          (fun key ->
            if is_name key.name then
              Ok
                (Kept
                   (fun settings ->
                     reading.runners <-
                       (name, (key, settings)) :: reading.runners))
            else Error (Bad_runner_name key.name)) )
    in
    Fixed [ files; version; runners ]

let tier_place reading gate =
  Varying
    (fun key ->
      match Finding_class.of_name key.name with
      | Some Finding_class.Config_changed -> Error Never_blocks
      | Some Finding_class.Pack_mismatch -> Error No_tier_at_any_gate
      | Some finding_class -> (
          match Finding_class.builtin_tier finding_class gate with
          | None -> Error (No_tier_at_gate { finding_class; gate })
          | Some _ ->
              Ok
                (word reading
                   ~key:
                     [
                       "check"; "tiers"; Finding_class.gate_name gate; key.name;
                     ]
                   Finding_class.[ Off; Warn; Block ]
                   Finding_class.tier_name
                   (fun tier ->
                     reading.tiers <-
                       (gate, finding_class, tier) :: reading.tiers)))
      | None -> (
          match misplaced key.name with
          | Some problem -> Error problem
          | None ->
              let valid =
                List.filter
                  (fun c ->
                    c <> Finding_class.Config_changed
                    && Finding_class.builtin_tier c gate <> None)
                  Finding_class.all
                |> List.map Finding_class.name
              in
              Error
                (Unknown_class
                   {
                     name = key.name;
                     gate;
                     nearest = Edit_distance.nearest key.name valid;
                   })))

let kind_of_name choices name =
  List.find_opt (fun kind -> String.equal (kind_name kind) name) choices

let paths_place reading =
  let valid = [ "exempt"; "historical" ] @ List.map kind_name location_kinds in
  Varying
    (fun (key : Toml.key) ->
      match key.name with
      | "exempt" ->
          Ok
            (path_set reading [ "paths"; "exempt" ] (fun set ->
                 reading.exempt <- set))
      | "historical" ->
          Ok
            (path_set reading [ "paths"; "historical" ] (fun set ->
                 reading.historical <- set))
      | "plan" -> Error Plan_location
      | name -> (
          match kind_of_name location_kinds name with
          | Some kind ->
              Ok
                (path_set reading [ "paths"; name ] (fun set ->
                     if not (Path_set.is_empty set) then
                       reading.locations <- (kind, set) :: reading.locations))
          | None -> Error (unknown_key ~table:[ "paths" ] ~valid name)))

let proof_place reading =
  let valid =
    [ "agent-markers"; "step"; "verifies" ] @ List.map kind_name kinds
  in
  Varying
    (fun (key : Toml.key) ->
      match key.name with
      | "verifies" ->
          Ok
            (word reading ~key:[ "proof"; "verifies" ] [ Whole_run; Each_test ]
               verifies_name (fun value -> reading.verifies <- value))
      | "step" ->
          Ok
            (word reading ~key:[ "proof"; "step" ]
               [ Change; Step_approval; Promises ] step_name (fun value ->
                 reading.step <- value))
      | "agent-markers" ->
          Ok
            (Texts
               (fun _ members ->
                 List.iter
                   (fun (node, name) ->
                     if not (is_variable_name name) then
                       value_error reading (Toml.span node) (Bad_marker name))
                   members;
                 List.iter
                   (fun (node, member) ->
                     value_error reading (Toml.span node)
                       (Repeated_member
                          { key = [ "proof"; "agent-markers" ]; member }))
                   (first_repeated members);
                 reading.agent_markers <- List.map snd members))
      | name -> (
          match kind_of_name kinds name with
          | Some kind ->
              Ok
                (word reading ~key:[ "proof"; name ] [ Declaration; Approval ]
                   approval_name (fun value ->
                     reading.approvals <- (kind, value) :: reading.approvals))
          | None -> Error (unknown_key ~table:[ "proof" ] ~valid name)))

let layout reading =
  [
    ("sinter-spec", Text (fun _ _ -> ()));
    ( "default-branch",
      Text
        (fun node value ->
          match Branch_name.check value with
          | Ok () -> reading.default_branch <- Some value
          | Error error ->
              value_error reading
                (inside node (Branch_name.error_offset error))
                (Not_a_branch { name = value; error })) );
    ( "scan",
      Fixed
        [
          ( "packs",
            Varying
              (fun key ->
                if is_name key.name then begin
                  reading.pack_keys <- (key.name, key.at) :: reading.pack_keys;
                  Ok (pack_place reading key)
                end
                else Error (Bad_pack_name key.name)) );
          ( "namespaces",
            Varying
              (fun key ->
                if is_name key.name then
                  Ok
                    (Text
                       (fun node value ->
                         match Id_pattern.of_string value with
                         | Ok pattern ->
                             reading.namespaces <-
                               (key.name, pattern) :: reading.namespaces
                         | Error error ->
                             value_error reading
                               (inside node (Id_pattern.error_offset error))
                               (Bad_id_pattern { namespace = key.name; error })))
                else Error (Bad_namespace key.name)) );
        ] );
    ("paths", paths_place reading);
    ("proof", proof_place reading);
    ( "check",
      Fixed
        [
          ("warn-only", Flag (fun value -> reading.warn_only <- value));
          ( "tiers",
            Varying
              (fun key ->
                match Finding_class.gate_of_name key.name with
                | Some gate -> Ok (tier_place reading gate)
                | None -> (
                    match misplaced key.name with
                    | Some problem -> Error problem
                    | None ->
                        Error
                          (Unknown_gate
                             {
                               name = key.name;
                               nearest =
                                 Edit_distance.nearest key.name
                                   (List.map Finding_class.gate_name
                                      Finding_class.gates);
                             }))) );
        ] );
  ]

let rec walk reading ~path ~(key : Toml.key) place node =
  let wrong expected =
    names_error reading (Toml.span node)
      (Wrong_type
         { key = path; expected; found = Toml.Kind.of_value (Toml.value node) })
  in
  match (place, Toml.value node) with
  | Fixed fields, Toml.Table table -> walk_fixed reading ~path fields table
  | Varying check, Toml.Table table -> walk_varying reading ~path check table
  | Kept found, Toml.Table table -> found table
  | (Fixed _ | Varying _ | Kept _), _ -> wrong A_table
  | Refused problem, _ -> names_error reading key.at problem
  | Text found, Toml.String value -> found node value
  | Text _, _ -> wrong A_string
  | Flag found, Toml.Boolean value -> found value
  | Flag _, _ -> wrong True_or_false
  | Texts found, Toml.Array members ->
      let strings =
        List.filter_map
          (fun member ->
            match Toml.value member with
            | Toml.String value -> Some (member, value)
            | other ->
                names_error reading (Toml.span member)
                  (Wrong_member_type
                     { key = path; found = Toml.Kind.of_value other });
                None)
          members
      in
      if List.length strings = List.length members then found node strings
  | Texts _, _ -> wrong Strings

and walk_fixed reading ~path fields table =
  List.iter
    (fun ((key : Toml.key), child) ->
      match List.assoc_opt key.name fields with
      | Some place -> walk reading ~path:(path @ [ key.name ]) ~key place child
      | None ->
          names_error reading key.at
            (unknown_key ~table:path ~valid:(List.map fst fields) key.name))
    table

and walk_varying reading ~path check table =
  List.iter
    (fun ((key : Toml.key), child) ->
      match check key with
      | Ok place -> walk reading ~path:(path @ [ key.name ]) ~key place child
      | Error problem -> names_error reading key.at problem)
    table

let sort errors =
  List.sort_uniq
    (fun ((a : Toml.span), p) ((b : Toml.span), q) ->
      compare (a.start.line, a.start.column, p) (b.start.line, b.start.column, q))
    errors
  |> List.map (fun (span, problem) -> At (span, problem))

let check_sinter_spec document =
  match
    List.find_opt
      (fun ((key : Toml.key), _) -> key.name = "sinter-spec")
      document
  with
  | None -> Ok None
  | Some (_, node) -> (
      match Toml.value node with
      | Toml.String text -> (
          match Major_minor.of_string text with
          | None ->
              Error
                (Toml.span node, Not_a_version { key = [ "sinter-spec" ]; text })
          | Some sinter_spec
            when Major_minor.newer sinter_spec ~than:specification ->
              Error (Toml.span node, Sinter_spec_too_new sinter_spec)
          | Some sinter_spec
            when Major_minor.older_major sinter_spec ~than:specification ->
              Error (Toml.span node, Sinter_spec_major_too_old sinter_spec)
          | Some sinter_spec -> Ok (Some sinter_spec))
      | other ->
          Error
            ( Toml.span node,
              Wrong_type
                {
                  key = [ "sinter-spec" ];
                  expected = A_version;
                  found = Toml.Kind.of_value other;
                } ))

let rec keys_newer ~sinter_spec ~path table =
  List.concat_map
    (fun ((key : Toml.key), node) ->
      let path = path @ [ key.name ] in
      let here =
        match since path with
        | Some version when Major_minor.newer version ~than:sinter_spec ->
            [
              (key.at, Key_too_new { key = path; since = version; sinter_spec });
            ]
        | _ -> []
      in
      match Toml.value node with
      | Toml.Table table -> here @ keys_newer ~sinter_spec ~path table
      | _ -> here)
    table

let newer_keys ~sinter_spec document =
  sort (keys_newer ~sinter_spec ~path:[] document)

let new_reading () =
  {
    names_errors = [];
    value_errors = [];
    default_branch = None;
    pack_keys = [];
    files = [];
    versions = [];
    runners = [];
    namespaces = [];
    warn_only = false;
    tiers = [];
    historical = Path_set.empty;
    exempt = Path_set.empty;
    locations = [];
    approvals = [];
    agent_markers = [];
    verifies = Whole_run;
    step = Change;
  }

let check_runners_of_packs reading =
  let owners = ref By_name.empty in
  List.iter
    (fun (pack, ((key : Toml.key), _)) ->
      match By_name.find_opt key.name !owners with
      | None -> owners := By_name.add key.name pack !owners
      | Some other ->
          value_error reading key.at
            (Runner_in_two_packs { runner = key.name; pack; other }))
    (List.stable_sort
       (fun (a, _) (b, _) -> String.compare a b)
       (List.rev reading.runners))

let runners_of reading pack =
  List.rev reading.runners
  |> List.filter_map (fun (owner, ((key : Toml.key), settings)) ->
      if String.equal owner pack then
        Some ({ name = key.name; at = key.at; settings } : runner)
      else None)

let packs_of reading =
  let by_name pairs = By_name.of_seq (List.to_seq pairs) in
  let files_by_name = by_name reading.files
  and versions_by_name = by_name reading.versions in
  List.sort compare reading.pack_keys
  |> List.filter_map (fun (name, span) ->
      let files = By_name.find_opt name files_by_name
      and version = By_name.find_opt name versions_by_name
      and builtin = name = "markdown" in
      if files = None then value_error reading span (Missing_files name);
      if version = None && not builtin then
        value_error reading span (Missing_version name);
      match (files, version) with
      | Some (Some files), None when builtin ->
          Some { name; files; version = None; runners = [] }
      | Some (Some files), Some (Some version) ->
          Some
            {
              name;
              files;
              version = Some version;
              runners = runners_of reading name;
            }
      | _ -> None)

let of_string text =
  match Toml.parse text with
  | Error error ->
      Error (sort [ (one_character (Toml.error_position error), Syntax error) ])
  | Ok document -> (
      match check_sinter_spec document with
      | Error error -> Error (sort [ error ])
      | Ok sinter_spec ->
          let newer =
            match sinter_spec with
            | Some sinter_spec -> newer_keys ~sinter_spec document
            | None -> []
          in
          if newer <> [] then Error newer
          else
            let reading = new_reading () in
            walk_fixed reading ~path:[] (layout reading) document;
            if reading.names_errors <> [] then Error (sort reading.names_errors)
            else
              let () = check_runners_of_packs reading in
              let packs = packs_of reading in
              if reading.value_errors <> [] then
                Error (sort reading.value_errors)
              else if packs = [] then Error [ No_pack ]
              else
                Ok
                  {
                    document;
                    sinter_spec;
                    default_branch =
                      Option.value reading.default_branch ~default:"main";
                    packs;
                    namespaces = List.sort compare reading.namespaces;
                    warn_only = reading.warn_only;
                    tiers = List.sort compare reading.tiers;
                    historical = reading.historical;
                    exempt = reading.exempt;
                    locations = reading.locations;
                    approvals = reading.approvals;
                    agent_markers = reading.agent_markers;
                    verifies = reading.verifies;
                    step = reading.step;
                  })

type load_error =
  | Missing
  | Unreadable of string
  | Invalid of { text : string; errors : error list }

let read_all path =
  if not (Sys.file_exists path) then Error Missing
  else
    match In_channel.with_open_bin path In_channel.input_all with
    | text -> Ok text
    | exception Sys_error reason -> Error (Unreadable reason)

let load path =
  match read_all path with
  | Error error -> Error error
  | Ok text -> (
      match of_string text with
      | Ok manifest -> Ok manifest
      | Error errors -> Error (Invalid { text; errors }))

let document (manifest : t) = manifest.document
let sinter_spec (manifest : t) = manifest.sinter_spec
let default_branch (manifest : t) = manifest.default_branch
let packs (manifest : t) = manifest.packs
let namespaces (manifest : t) = manifest.namespaces
let warn_only (manifest : t) = manifest.warn_only
let written_tiers (manifest : t) = manifest.tiers

let tier (manifest : t) gate finding_class =
  match Finding_class.builtin_tier finding_class gate with
  | None -> None
  | Some builtin -> (
      match
        List.find_opt
          (fun (g, c, _) -> g = gate && c = finding_class)
          manifest.tiers
      with
      | Some (_, _, written) -> Some written
      | None when manifest.warn_only && builtin = Finding_class.Block ->
          Some Finding_class.Warn
      | None -> Some builtin)

let historical (manifest : t) = manifest.historical
let builtin_historical = ".plans/**/*.log.md"
let builtin_historical_glob = Result.get_ok (Glob.of_string builtin_historical)

let is_historical (manifest : t) path =
  Glob.matches builtin_historical_glob path
  || Path_set.mem manifest.historical path

let exempt (manifest : t) = manifest.exempt
let lock_file = "sinter.lock"

let is_exempt (manifest : t) ~plan_file ~manifest:location path =
  plan_file path || location = Some path || path = lock_file
  || Path_set.mem manifest.exempt path

let location (manifest : t) kind = List.assoc_opt kind manifest.locations

let approval (manifest : t) kind =
  Option.value (List.assoc_opt kind manifest.approvals) ~default:Declaration

let agent_markers (manifest : t) = manifest.agent_markers
let verifies (manifest : t) = manifest.verifies
let step (manifest : t) = manifest.step
