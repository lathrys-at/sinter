(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

let specification = Major_minor.make 1 0

(* Each setting, by its key path, with the version that added it. A
   name in angle brackets varies. *)
let settings =
  List.map
    (fun (path, major, minor) ->
      (String.split_on_char '.' path, Major_minor.make major minor))
    [
      ("spec", 1, 0);
      ("target", 1, 0);
      ("scan.packs.<name>.files", 1, 0);
      ("scan.packs.<name>.version", 1, 0);
      ("scan.refs.<ns>", 1, 0);
      ("check.rollout-cap", 1, 0);
      ("check.historical", 1, 0);
      ("check.tiers.<gate>.<class>", 1, 0);
      ("plan.ambient", 1, 0);
      ("plan.shared", 1, 0);
      ("plan.locations.<kind>", 1, 0);
      ("ledger.approval-required", 1, 0);
      ("ledger.harness-markers", 1, 0);
      ("evidence.coverage-attribution", 1, 0);
    ]

let varies name = String.starts_with ~prefix:"<" name

let rec path_matches pattern path =
  match (pattern, path) with
  | [], [] -> true
  | p :: ps, n :: ns -> (varies p || p = n) && path_matches ps ns
  | _ -> false

let since path =
  List.find_map
    (fun (pattern, version) ->
      if path_matches pattern path then Some version else None)
    settings

(* Each fixed name of the layout, with the key path of the table that
   holds it. Each fixed name occurs at one place. *)
let fixed_places =
  List.concat_map
    (fun (pattern, _) ->
      List.mapi
        (fun i name -> (name, List.filteri (fun j _ -> j < i) pattern))
        pattern)
    settings
  |> List.filter (fun (name, _) -> not (varies name))
  |> List.sort_uniq compare

(* A name that a setting's key path holds before its last name. *)
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

type coverage_attribution = Optional | Required
type expected = A_string | A_version | True_or_false | Strings | A_table

type problem =
  | Syntax of Toml.error
  | Not_a_version of { key : string list; text : string }
  | Spec_too_new of Major_minor.t
  | Spec_major_too_old of Major_minor.t
  | Key_too_new of {
      key : string list;
      since : Major_minor.t;
      spec : Major_minor.t;
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
  | Unknown_kind of { name : string; nearest : string option }
  | Plan_location
  | Markdown_version
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

type error = At of Toml.position * problem | No_pack

(* Messages. *)

let quoted name = "'" ^ name ^ "'"

(* A string as a TOML basic string writes it. *)
let toml_string text =
  let escape = function
    | '"' -> "\\\""
    | '\\' -> "\\\\"
    | '\n' -> "\\n"
    | '\t' -> "\\t"
    | c when c < ' ' || c = '\127' -> Printf.sprintf "\\u%04X" (Char.code c)
    | c -> String.make 1 c
  in
  "\""
  ^ String.concat "" (List.map escape (List.of_seq (String.to_seq text)))
  ^ "\""

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

(* "a", "a or b", "a, b, or c" *)
let choice words =
  match List.rev words with
  | [] -> ""
  | [ only ] -> only
  | [ b; a ] -> a ^ " or " ^ b
  | final :: rest -> String.concat ", " (List.rev rest) ^ ", or " ^ final

let did_you_mean ~quote = function
  | None -> ""
  | Some name -> "; did you mean " ^ quote name ^ "?"

let expected_text = function
  | A_string -> "a string"
  | A_version -> "a version of the form MAJOR.MINOR, such as \"1.0\""
  | True_or_false -> "true or false"
  | Strings -> "an array of strings"
  | A_table -> "a table"

let name_rule ~examples =
  "lower-case letters and digits, in words joined by '-', such as " ^ examples

let problem_message = function
  | Syntax error -> Toml.error_message error
  | Not_a_version { key; text } ->
      Printf.sprintf "%s takes %s, not %s"
        (quoted (last key))
        (expected_text A_version) (toml_string text)
  | Spec_too_new version ->
      Printf.sprintf
        "this manifest needs specification %s, and this sinter implements %s; \
         install a newer sinter"
        (Major_minor.to_string version)
        (Major_minor.to_string specification)
  | Spec_major_too_old version ->
      Printf.sprintf
        "this manifest is for specification %s, and this sinter implements %s, \
         a new major version that can change the meaning of a key; read the \
         notes on the changes in specification %s, then update the manifest \
         and its 'spec'"
        (Major_minor.to_string version)
        (Major_minor.to_string specification)
        (Major_minor.to_string specification)
  | Key_too_new { key; since; spec } ->
      Printf.sprintf
        "%s needs specification %s, and the manifest states spec = %s; write \
         spec = %s"
        (quoted (Toml.render_path key))
        (Major_minor.to_string since)
        (toml_string (Major_minor.to_string spec))
        (toml_string (Major_minor.to_string since))
  | Unknown_key { name; table; nearest } ->
      Printf.sprintf "unknown key %s %s%s" (quoted name) (in_table table)
        (did_you_mean ~quote:quoted nearest)
  | Misplaced_key { name; place = [] } when is_table_name name ->
      Printf.sprintf
        "%s is a table of the top level; write its keys under the header [%s]"
        (quoted name) name
  | Misplaced_key { name; place = [] } ->
      Printf.sprintf "%s belongs at the top level, above the first table header"
        (quoted name)
  | Misplaced_key { name; place } ->
      Printf.sprintf "%s belongs in %s" (quoted name) (table_name place)
  | Bad_pack_name name ->
      Printf.sprintf "%s is not a pack name; a pack name is %s" (quoted name)
        (name_rule ~examples:"'ocaml' or 'tree-sitter'")
  | Bad_namespace name ->
      Printf.sprintf "%s is not a ref namespace; a namespace is %s"
        (quoted name)
        (name_rule ~examples:"'gh' or 'jira'")
  | Unknown_gate { name; nearest } ->
      Printf.sprintf "unknown gate %s in [check.tiers]%s" (quoted name)
        (match nearest with
        | Some _ -> did_you_mean ~quote:quoted nearest
        | None ->
            "; the gates are "
            ^ choice
                (List.map
                   (fun gate -> quoted (Finding_class.gate_name gate))
                   Finding_class.gates))
  | Unknown_class { name; gate; nearest } ->
      Printf.sprintf "unknown finding class %s in [check.tiers.%s]%s"
        (quoted name)
        (Finding_class.gate_name gate)
        (match nearest with
        | Some _ -> did_you_mean ~quote:quoted nearest
        | None -> "; 'tiers' names built-in finding classes only")
  | No_tier_at_gate { finding_class; gate } ->
      Printf.sprintf "%s takes no tier at the gate %s"
        (quoted (Finding_class.name finding_class))
        (quoted (Finding_class.gate_name gate))
  | Never_blocks ->
      "'config-changed' takes no tier; it always reports and never blocks"
  | No_tier_at_any_gate -> "'pack-drift' takes no tier at any gate"
  | Unknown_kind { name; nearest } ->
      Printf.sprintf "unknown kind %s in [plan.locations]%s" (quoted name)
        (match nearest with
        | Some _ -> did_you_mean ~quote:quoted nearest
        | None ->
            "; the kinds are "
            ^ choice (List.map (fun k -> quoted (kind_name k)) location_kinds))
  | Plan_location ->
      "'plan' takes no location; plan files always live under .plans/"
  | Markdown_version ->
      "the pack markdown is built into sinter and takes no version"
  | Wrong_type { key; expected; found } ->
      Printf.sprintf "%s takes %s, not %s"
        (quoted (last key))
        (expected_text expected) (Toml.Kind.name found)
  | Wrong_member_type { key; found } ->
      Printf.sprintf "%s takes an array of strings, and this member is %s"
        (quoted (last key))
        (Toml.Kind.name found)
  | Not_a_branch { name; error } ->
      Printf.sprintf "%s is not a branch name; %s" (toml_string name)
        (Branch_name.message error)
  | Bad_glob { member; error } ->
      Printf.sprintf "%s is not a glob: %s" (toml_string member)
        (Glob.message error)
  | Repeated_member { key; member } ->
      Printf.sprintf "%s occurs twice in %s" (toml_string member)
        (quoted (last key))
  | No_plain_glob key ->
      Printf.sprintf
        "%s holds only '!' globs, so it holds no path; add a glob without '!'"
        (quoted (last key))
  | Missing_files pack ->
      Printf.sprintf
        "the pack %s needs 'files', the globs of the files that it reads"
        (quoted pack)
  | Missing_version pack ->
      Printf.sprintf
        "the pack %s needs 'version', the release that the repository uses, \
         such as \"1.0\""
        (quoted pack)
  | Bad_id_pattern { error; _ } -> Id_pattern.message error
  | Unknown_value { key; value; choices; nearest } ->
      Printf.sprintf "%s takes %s, not %s%s"
        (quoted (last key))
        (choice (List.map toml_string choices))
        (toml_string value)
        (did_you_mean ~quote:toml_string nearest)
  | Bad_marker name ->
      Printf.sprintf
        "%s is not a name of an environment variable; a name holds letters, \
         digits, and '_', and does not start with a digit"
        (toml_string name)

let no_pack_advice =
  "add a line such as packs.markdown.files = [\"**/*.md\"] under [scan]"

let message = function
  | At (_, problem) -> problem_message problem
  | No_pack -> "the manifest names no pack; " ^ no_pack_advice

let render ~path = function
  | At (position, problem) ->
      Printf.sprintf "%s:%d:%d: %s" path position.Toml.line position.column
        (problem_message problem)
  | No_pack -> Printf.sprintf "%s names no pack; %s" path no_pack_advice

(* The manifest. *)

type pack = {
  name : string;
  files : Path_set.t;
  version : Major_minor.t option;
}

type t = {
  spec : Major_minor.t option;
  target : string;
  packs : pack list;
  refs : (string * Id_pattern.t) list;
  rollout_cap : bool;
  tiers : (Finding_class.gate * Finding_class.t * Finding_class.tier) list;
  historical : Path_set.t;
  ambient : Path_set.t;
  shared : Path_set.t;
  locations : (kind * Path_set.t) list;
  approval_required : kind list;
  harness_markers : string list;
  coverage_attribution : coverage_attribution;
}

(* The state of one reading. [names_errors] are the errors of the step
   of names and types; [value_errors] those of the step of values. *)
type reading = {
  mutable names_errors : (Toml.position * problem) list;
  mutable value_errors : (Toml.position * problem) list;
  mutable target : string option;
  mutable pack_keys : (string * Toml.position) list;
  mutable files : (string * Path_set.t option) list;
  mutable versions : (string * Major_minor.t option) list;
  mutable refs : (string * Id_pattern.t) list;
  mutable rollout_cap : bool;
  mutable tiers :
    (Finding_class.gate * Finding_class.t * Finding_class.tier) list;
  mutable historical : Path_set.t;
  mutable ambient : Path_set.t;
  mutable shared : Path_set.t;
  mutable locations : (kind * Path_set.t) list;
  mutable approval_required : kind list;
  mutable harness_markers : string list;
  mutable coverage_attribution : coverage_attribution;
}

(* A place of the layout. [Fixed] is a table of fixed names. [Varying]
   is a table of names that vary: the function checks the key of one
   name, and gives the place of its value. [Refused] is a fixed name
   that this table does not take. The three leaves take the value of
   their type. *)
type place =
  | Fixed of (string * place) list
  | Varying of (Toml.key -> (place, problem) result)
  | Refused of problem
  | Text of (Toml.node -> string -> unit)
  | Flag of (bool -> unit)
  | Texts of (Toml.node -> (Toml.node * string) list -> unit)

let names_error reading position problem =
  reading.names_errors <- (position, problem) :: reading.names_errors

let value_error reading position problem =
  reading.value_errors <- (position, problem) :: reading.value_errors

let start node = (Toml.span node).start

(* The place of byte [offset] of the string of [node], or the start of
   the node when the text does not write the string as it is. *)
let inside node offset =
  match Toml.string_position node offset with
  | Some position -> position
  | None -> start node

let is_name_char c = (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9')

(* [a-z][a-z0-9]*(-[a-z0-9]+)* *)
let is_layout_name name =
  name <> ""
  && name.[0] >= 'a'
  && name.[0] <= 'z'
  && List.for_all
       (fun word -> word <> "" && String.for_all is_name_char word)
       (String.split_on_char '-' name)

(* [A-Za-z_][A-Za-z0-9_]* *)
let is_variable_name name =
  let letter c = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c = '_' in
  name <> ""
  && letter name.[0]
  && String.for_all (fun c -> letter c || (c >= '0' && c <= '9')) name

let misplaced name =
  List.assoc_opt name fixed_places
  |> Option.map (fun place -> Misplaced_key { name; place })

let first_repeated texts =
  let rec go seen = function
    | [] -> []
    | (node, text) :: rest ->
        if List.mem text seen then (node, text) :: go seen rest
        else go (text :: seen) rest
  in
  go [] texts

let read_path_set reading ~key array members set =
  match Path_set.of_strings (List.map snd members) with
  | Ok path_set -> set path_set
  | Error errors ->
      List.iter
        (fun error ->
          match error with
          | Path_set.Bad_glob { index; start = offset; error } ->
              let node, member = List.nth members index in
              value_error reading
                (inside node (offset + Glob.error_offset error))
                (Bad_glob { member; error })
          | Path_set.Repeated { index; member } ->
              value_error reading
                (start (fst (List.nth members index)))
                (Repeated_member { key; member })
          | Path_set.No_plain_glob ->
              value_error reading (start array) (No_plain_glob key))
        errors

let path_set reading key set =
  Texts (fun array members -> read_path_set reading ~key array members set)

(* A string that must be one of [choices]. *)
let word reading ~key choices name_of found =
  Text
    (fun node value ->
      match List.find_opt (fun choice -> name_of choice = value) choices with
      | Some choice -> found choice
      | None ->
          let names = List.map name_of choices in
          value_error reading (start node)
            (Unknown_value
               {
                 key;
                 value;
                 choices = names;
                 nearest = Edit_distance.nearest value names;
               }))

(* An array of strings that must each be one of [choices], with no
   member twice. *)
let words reading ~key choices name_of found =
  Texts
    (fun _ members ->
      let names = List.map name_of choices in
      let read =
        List.filter_map
          (fun (node, value) ->
            match List.find_opt (fun c -> name_of c = value) choices with
            | Some choice -> Some choice
            | None ->
                value_error reading (start node)
                  (Unknown_value
                     {
                       key;
                       value;
                       choices = names;
                       nearest = Edit_distance.nearest value names;
                     });
                None)
          members
      in
      List.iter
        (fun (node, member) ->
          value_error reading (start node) (Repeated_member { key; member }))
        (first_repeated members);
      found read)

let pack_place reading (key : Toml.key) =
  let name = key.name in
  let files_key = [ "scan"; "packs"; name; "files" ] in
  let version =
    if name = "markdown" then ("version", Refused Markdown_version)
    else
      ( "version",
        Text
          (fun node value ->
            let version = Major_minor.of_string value in
            reading.versions <- (name, version) :: reading.versions;
            if version = None then
              value_error reading (start node)
                (Not_a_version
                   { key = [ "scan"; "packs"; name; "version" ]; text = value }))
      )
  in
  Fixed
    [
      ( "files",
        Texts
          (fun array members ->
            let files = ref None in
            read_path_set reading ~key:files_key array members (fun set ->
                files := Some set);
            if members <> [] then
              reading.files <- (name, !files) :: reading.files) );
      version;
    ]

let tier_place reading gate =
  Varying
    (fun key ->
      match Finding_class.of_name key.name with
      | Some Finding_class.Config_changed -> Error Never_blocks
      | Some Finding_class.Pack_drift -> Error No_tier_at_any_gate
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

let layout reading =
  [
    ("spec", Text (fun _ _ -> ()));
    ( "target",
      Text
        (fun node value ->
          match Branch_name.check value with
          | Ok () -> reading.target <- Some value
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
                if is_layout_name key.name then begin
                  reading.pack_keys <-
                    (key.name, key.at.start) :: reading.pack_keys;
                  Ok (pack_place reading key)
                end
                else Error (Bad_pack_name key.name)) );
          ( "refs",
            Varying
              (fun key ->
                if is_layout_name key.name then
                  Ok
                    (Text
                       (fun node value ->
                         match Id_pattern.of_string value with
                         | Ok pattern ->
                             reading.refs <- (key.name, pattern) :: reading.refs
                         | Error error ->
                             value_error reading
                               (inside node (Id_pattern.error_offset error))
                               (Bad_id_pattern { namespace = key.name; error })))
                else Error (Bad_namespace key.name)) );
        ] );
    ( "check",
      Fixed
        [
          ("rollout-cap", Flag (fun value -> reading.rollout_cap <- value));
          ( "historical",
            path_set reading [ "check"; "historical" ] (fun set ->
                reading.historical <- set) );
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
    ( "plan",
      Fixed
        [
          ( "ambient",
            path_set reading [ "plan"; "ambient" ] (fun set ->
                reading.ambient <- set) );
          ( "shared",
            path_set reading [ "plan"; "shared" ] (fun set ->
                reading.shared <- set) );
          ( "locations",
            Varying
              (fun key ->
                match
                  List.find_opt (fun k -> kind_name k = key.name) location_kinds
                with
                | Some kind ->
                    Ok
                      (path_set reading [ "plan"; "locations"; key.name ]
                         (fun set ->
                           if not (Path_set.is_empty set) then
                             reading.locations <-
                               (kind, set) :: reading.locations))
                | None when key.name = "plan" -> Error Plan_location
                | None -> (
                    match misplaced key.name with
                    | Some problem -> Error problem
                    | None ->
                        Error
                          (Unknown_kind
                             {
                               name = key.name;
                               nearest =
                                 Edit_distance.nearest key.name
                                   (List.map kind_name location_kinds);
                             }))) );
        ] );
    ( "ledger",
      Fixed
        [
          ( "approval-required",
            words reading ~key:[ "ledger"; "approval-required" ] kinds kind_name
              (fun found -> reading.approval_required <- found) );
          ( "harness-markers",
            Texts
              (fun _ members ->
                List.iter
                  (fun (node, name) ->
                    if not (is_variable_name name) then
                      value_error reading (start node) (Bad_marker name))
                  members;
                List.iter
                  (fun (node, member) ->
                    value_error reading (start node)
                      (Repeated_member
                         { key = [ "ledger"; "harness-markers" ]; member }))
                  (first_repeated members);
                reading.harness_markers <- List.map snd members) );
        ] );
    ( "evidence",
      Fixed
        [
          ( "coverage-attribution",
            word reading
              ~key:[ "evidence"; "coverage-attribution" ]
              [ Optional; Required ]
              (function Optional -> "optional" | Required -> "required")
              (fun value -> reading.coverage_attribution <- value) );
        ] );
  ]

(* The step of names and types, which also runs the checks of values
   on each value of the right type. [path] is the key path of [node]. *)
let rec walk reading ~path ~(key : Toml.key) place node =
  let wrong expected =
    names_error reading (start node)
      (Wrong_type
         { key = path; expected; found = Toml.Kind.of_value (Toml.value node) })
  in
  match (place, Toml.value node) with
  | Fixed fields, Toml.Table table -> walk_fixed reading ~path fields table
  | Varying check, Toml.Table table -> walk_varying reading ~path check table
  | (Fixed _ | Varying _), _ -> wrong A_table
  | Refused problem, _ -> names_error reading key.at.start problem
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
                names_error reading (start member)
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
          let problem =
            match misplaced key.name with
            | Some problem -> problem
            | None ->
                Unknown_key
                  {
                    name = key.name;
                    table = path;
                    nearest =
                      Edit_distance.nearest key.name (List.map fst fields);
                  }
          in
          names_error reading key.at.start problem)
    table

and walk_varying reading ~path check table =
  List.iter
    (fun ((key : Toml.key), child) ->
      match check key with
      | Ok place -> walk reading ~path:(path @ [ key.name ]) ~key place child
      | Error problem -> names_error reading key.at.start problem)
    table

(* The errors in the order of their places, by line and then by
   column, with no error twice. *)
let sort errors =
  List.sort_uniq
    (fun ((a : Toml.position), p) ((b : Toml.position), q) ->
      compare (a.line, a.column, p) (b.line, b.column, q))
    errors
  |> List.map (fun (position, problem) -> At (position, problem))

(* The step of [spec]: its type, its form, and the three rules of the
   version. *)
let check_spec document =
  match
    List.find_opt (fun ((key : Toml.key), _) -> key.name = "spec") document
  with
  | None -> Ok None
  | Some (_, node) -> (
      match Toml.value node with
      | Toml.String text -> (
          match Major_minor.of_string text with
          | None -> Error (start node, Not_a_version { key = [ "spec" ]; text })
          | Some spec when Major_minor.newer spec ~than:specification ->
              Error (start node, Spec_too_new spec)
          | Some spec when Major_minor.older_major spec ~than:specification ->
              Error (start node, Spec_major_too_old spec)
          | Some spec -> Ok (Some spec))
      | other ->
          Error
            ( start node,
              Wrong_type
                {
                  key = [ "spec" ];
                  expected = A_version;
                  found = Toml.Kind.of_value other;
                } ))

let rec keys_newer ~spec ~path table =
  List.concat_map
    (fun ((key : Toml.key), node) ->
      let path = path @ [ key.name ] in
      let here =
        match since path with
        | Some version when Major_minor.newer version ~than:spec ->
            [
              (key.at.start, Key_too_new { key = path; since = version; spec });
            ]
        | _ -> []
      in
      match Toml.value node with
      | Toml.Table table -> here @ keys_newer ~spec ~path table
      | _ -> here)
    table

let newer_keys ~spec document = sort (keys_newer ~spec ~path:[] document)

let new_reading () =
  {
    names_errors = [];
    value_errors = [];
    target = None;
    pack_keys = [];
    files = [];
    versions = [];
    refs = [];
    rollout_cap = false;
    tiers = [];
    historical = Path_set.empty;
    ambient = Path_set.empty;
    shared = Path_set.empty;
    locations = [];
    approval_required = [];
    harness_markers = [];
    coverage_attribution = Optional;
  }

(* The packs, each with its files and its version, and an error for a
   pack that lacks one of them. A value that the manifest writes and
   that is not valid is [Some None]: its error is already reported. *)
let packs_of reading =
  let lacks position problem =
    value_error reading position problem;
    None
  in
  List.sort compare reading.pack_keys
  |> List.filter_map (fun (name, position) ->
      match
        ( List.assoc_opt name reading.files,
          List.assoc_opt name reading.versions,
          name = "markdown" )
      with
      | None, _, _ -> lacks position (Missing_files name)
      | Some None, _, _ | _, Some None, _ -> None
      | Some (Some files), None, true -> Some { name; files; version = None }
      | Some (Some _), None, false -> lacks position (Missing_version name)
      | Some (Some files), Some (Some version), _ ->
          Some { name; files; version = Some version })

let of_string text =
  match Toml.parse text with
  | Error error -> Error (sort [ (Toml.error_position error, Syntax error) ])
  | Ok document -> (
      match check_spec document with
      | Error error -> Error (sort [ error ])
      | Ok spec ->
          let newer =
            match spec with
            | Some spec -> newer_keys ~spec document
            | None -> []
          in
          if newer <> [] then Error newer
          else
            let reading = new_reading () in
            walk_fixed reading ~path:[] (layout reading) document;
            if reading.names_errors <> [] then Error (sort reading.names_errors)
            else
              let packs = packs_of reading in
              if reading.value_errors <> [] then
                Error (sort reading.value_errors)
              else if packs = [] then Error [ No_pack ]
              else
                Ok
                  {
                    spec;
                    target = Option.value reading.target ~default:"main";
                    packs;
                    refs = List.sort compare reading.refs;
                    rollout_cap = reading.rollout_cap;
                    tiers = List.sort compare reading.tiers;
                    historical = reading.historical;
                    ambient = reading.ambient;
                    shared = reading.shared;
                    locations = reading.locations;
                    approval_required = reading.approval_required;
                    harness_markers = reading.harness_markers;
                    coverage_attribution = reading.coverage_attribution;
                  })

type load_error = Missing | Unreadable of string | Invalid of error list

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
      | Error errors -> Error (Invalid errors))

let spec (manifest : t) = manifest.spec
let target (manifest : t) = manifest.target
let packs (manifest : t) = manifest.packs
let ref_namespaces (manifest : t) = manifest.refs
let rollout_cap (manifest : t) = manifest.rollout_cap
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
      | None when manifest.rollout_cap && builtin = Finding_class.Block ->
          Some Finding_class.Warn
      | None -> Some builtin)

let historical (manifest : t) = manifest.historical
let builtin_historical = ".plans/**/*.log.md"
let builtin_historical_glob = Result.get_ok (Glob.of_string builtin_historical)

let is_historical (manifest : t) path =
  Glob.matches builtin_historical_glob path
  || Path_set.mem manifest.historical path

let ambient (manifest : t) = manifest.ambient
let lock_file = "sinter.lock"

let is_ambient (manifest : t) ~plan_file ~manifest:location path =
  plan_file path || location = Some path || path = lock_file
  || Path_set.mem manifest.ambient path

let shared (manifest : t) = manifest.shared
let location (manifest : t) kind = List.assoc_opt kind manifest.locations
let approval_required (manifest : t) = manifest.approval_required
let harness_markers (manifest : t) = manifest.harness_markers
let coverage_attribution (manifest : t) = manifest.coverage_attribution
