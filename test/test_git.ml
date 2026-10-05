(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

open Sinter_core
module Gen = QCheck2.Gen
module Fixture = Git_fixture

let property ?(count = 200) ~name ~print generator check =
  QCheck_alcotest.to_alcotest ~speed_level:`Quick
    (QCheck2.Test.make ~count ~name ~print generator check)

let holds name condition = Alcotest.(check bool) name true condition

let print_status = function
  | Unix.WEXITED code -> Printf.sprintf "exit %d" code
  | Unix.WSIGNALED signal -> Printf.sprintf "signal %d" signal
  | Unix.WSTOPPED signal -> Printf.sprintf "stopped by %d" signal

let print_error : Git.error -> string = function
  | Git_not_found detail -> "Git_not_found " ^ detail
  | Not_a_repository { dir; detail } ->
      Printf.sprintf "Not_a_repository %S: %s" dir detail
  | Bad_revision rev -> Printf.sprintf "Bad_revision %S" rev
  | Target_not_found name -> Printf.sprintf "Target_not_found %S" name
  | No_merge_base (a, b) -> Printf.sprintf "No_merge_base %S %S" a b
  | Command_failed { args; status; stderr } ->
      Printf.sprintf "Command_failed [%s] %s: %s" (String.concat " " args)
        (print_status status) stderr
  | Malformed_output { args; detail } ->
      Printf.sprintf "Malformed_output [%s]: %s" (String.concat " " args) detail
  | File_error detail -> "File_error " ^ detail

let ok = function
  | Ok value -> value
  | Error error -> Alcotest.fail (print_error error)

let error = function
  | Ok _ -> Alcotest.fail "the call gave a value, and an error was expected"
  | Error error -> error

let strings = Alcotest.(list string)
let pairs = Alcotest.(list (pair string string))

(* Generators. *)

let hex_digit = Gen.oneof_list (String.to_seq "0123456789abcdef" |> List.of_seq)

let object_id =
  Gen.(
    bind
      (oneof_list [ 40; 64 ])
      (fun length -> string_size ~gen:hex_digit (return length)))

(* A path of one to twelve bytes, none of them NUL. Tabs, spaces, and
   line feeds come up often, because the decoders split on them. *)
let path =
  let byte =
    Gen.(
      oneof_weighted
        [
          (6, char_range 'a' 'z');
          (1, oneof_list [ '\t'; ' '; '\n'; '/'; '"' ]);
          (2, map Char.chr (int_range 1 255));
        ])
  in
  Gen.string_size ~gen:byte (Gen.int_range 1 12)

let mode =
  Gen.(
    oneof
      [
        oneof_list [ 0o100644; 0o100755; 0o120000; 0o160000; 0o040000 ];
        int_range 0 0o777777;
      ])

let kinds =
  Git.Decode.
    [ (Blob, "blob"); (Tree, "tree"); (Commit, "commit"); (Tag, "tag") ]

let kind = Gen.oneof_list (List.map fst kinds)
let kind_name kind = List.assoc kind kinds

let stage_entry =
  Gen.(
    map
      (fun (mode, id, stage, path) -> { Git.Decode.mode; id; stage; path })
      (quad mode object_id (int_range 0 3) path))

let tree_entry =
  Gen.(
    map
      (fun (mode, kind, id, path) -> { Git.Decode.mode; kind; id; path })
      (quad mode kind object_id path))

let encode_stage_entry (entry : Git.Decode.stage_entry) =
  Printf.sprintf "%06o %s %d\t%s\000" entry.mode entry.id entry.stage entry.path

let encode_tree_entry (entry : Git.Decode.tree_entry) =
  Printf.sprintf "%06o %s %s\t%s\000" entry.mode (kind_name entry.kind) entry.id
    entry.path

let batch_header =
  Gen.(
    oneof
      [
        map
          (fun (id, kind, size) -> Git.Decode.Object { id; kind; size })
          (triple object_id kind
             (oneof [ int_range 0 100; int_range 0 max_int ]));
        map (fun id -> Git.Decode.Missing id) object_id;
      ])

let encode_batch_header = function
  | Git.Decode.Object { id; kind; size } ->
      Printf.sprintf "%s %s %d" id (kind_name kind) size
  | Git.Decode.Missing name -> name ^ " missing"

(* [damaged text] is [text] with one change: a byte replaced, a byte
   removed, a byte added, or the end cut off. *)
let damaged text =
  let open Gen in
  let length = String.length text in
  let at = int_range 0 (max 0 (length - 1)) in
  let byte = map Char.chr (int_range 0 255) in
  let replace =
    map2
      (fun at byte ->
        if length = 0 then String.make 1 byte
        else String.mapi (fun index c -> if index = at then byte else c) text)
      at byte
  in
  let remove =
    map
      (fun at ->
        if length = 0 then ""
        else String.sub text 0 at ^ String.sub text (at + 1) (length - at - 1))
      at
  in
  let add =
    map2
      (fun at byte ->
        String.sub text 0 at ^ String.make 1 byte
        ^ String.sub text at (length - at))
      at byte
  in
  let cut = map (fun at -> String.sub text 0 at) at in
  oneof [ replace; remove; add; cut ]

let any_bytes =
  Gen.(string_size ~gen:(map Char.chr (int_range 0 255)) (int_range 0 40))

let gives_a_value_or_an_error decode input =
  match decode input with Ok _ | Error _ -> true

let print_pair (label, text) = Printf.sprintf "%s %S" label text

(* Properties of the decoders. *)

let nul_list_gives_back_the_records =
  property ~name:"nul_list gives back the records that were joined"
    ~print:QCheck2.Print.(list string)
    Gen.(list_size (int_range 0 5) path)
    (fun records ->
      let output = String.concat "" (List.map (fun r -> r ^ "\000") records) in
      Git.Decode.nul_list output = Ok records)

let nul_list_needs_a_final_nul =
  property ~name:"nul_list refuses an output that does not end with NUL"
    ~print:QCheck2.Print.string any_bytes (fun output ->
      let ends_with_nul =
        output <> "" && output.[String.length output - 1] = '\000'
      in
      Result.is_ok (Git.Decode.nul_list output) = (output = "" || ends_with_nul))

let line_takes_off_one_line_feed =
  property ~name:"line gives back the text in front of one final line feed"
    ~print:QCheck2.Print.string any_bytes (fun text ->
      Git.Decode.line (text ^ "\n") = Ok text)

let line_needs_a_final_line_feed =
  property ~name:"line refuses an output that does not end with a line feed"
    ~print:QCheck2.Print.string any_bytes (fun output ->
      let ends_with_line_feed =
        output <> "" && output.[String.length output - 1] = '\n'
      in
      Result.is_ok (Git.Decode.line output) = ends_with_line_feed)

let object_id_reads_an_id =
  property ~name:"object_id reads an id on one line" ~print:QCheck2.Print.string
    object_id (fun id -> Git.Decode.object_id (id ^ "\n") = Ok id)

let object_id_refuses_a_damaged_id =
  property ~name:"object_id refuses an id with one damaged byte"
    ~print:QCheck2.Print.(pair string string)
    Gen.(pair object_id (bind object_id (fun id -> damaged id)))
    (fun (_, damaged) ->
      let valid =
        (String.length damaged = 40 || String.length damaged = 64)
        && String.for_all
             (function '0' .. '9' | 'a' .. 'f' -> true | _ -> false)
             damaged
      in
      Result.is_ok (Git.Decode.object_id (damaged ^ "\n")) = valid
      && Git.Decode.is_object_id damaged = valid)

let format_name = function Git.Sha1 -> "sha1" | Git.Sha256 -> "sha256"

let repository_output =
  Gen.(
    map
      (fun (format, root) -> (format, "/" ^ root))
      (pair (oneof_list [ Git.Sha1; Git.Sha256 ]) path))

let repository_reads_its_output =
  property ~name:"repository reads the format and the root, a line feed in it"
    ~print:(fun (format, root) ->
      Printf.sprintf "%s %S" (format_name format) root)
    repository_output
    (fun (format, root) ->
      Git.Decode.repository (format_name format ^ "\n" ^ root ^ "\n")
      = Ok (format, root))

let repository_is_total =
  property ~count:500
    ~name:"repository gives a value or an error for damaged output"
    ~print:QCheck2.Print.string
    Gen.(
      bind repository_output (fun (format, root) ->
          damaged (format_name format ^ "\n" ^ root ^ "\n")))
    (gives_a_value_or_an_error Git.Decode.repository)

let ls_files_stage_reads_its_output =
  property ~name:"ls_files_stage gives back the entries that were encoded"
    ~print:(fun entries ->
      String.concat "" (List.map encode_stage_entry entries))
    Gen.(list_size (int_range 0 4) stage_entry)
    (fun entries ->
      Git.Decode.ls_files_stage
        (String.concat "" (List.map encode_stage_entry entries))
      = Ok entries)

let ls_files_stage_is_total =
  property ~count:500
    ~name:"ls_files_stage gives a value or an error for damaged output"
    ~print:QCheck2.Print.string
    Gen.(
      bind
        (list_size (int_range 1 3) stage_entry)
        (fun entries ->
          damaged (String.concat "" (List.map encode_stage_entry entries))))
    (gives_a_value_or_an_error Git.Decode.ls_files_stage)

let ls_tree_reads_its_output =
  property ~name:"ls_tree gives back the entries that were encoded"
    ~print:(fun entries ->
      String.concat "" (List.map encode_tree_entry entries))
    Gen.(list_size (int_range 0 4) tree_entry)
    (fun entries ->
      Git.Decode.ls_tree (String.concat "" (List.map encode_tree_entry entries))
      = Ok entries)

let ls_tree_is_total =
  property ~count:500
    ~name:"ls_tree gives a value or an error for damaged output"
    ~print:QCheck2.Print.string
    Gen.(
      bind
        (list_size (int_range 1 3) tree_entry)
        (fun entries ->
          damaged (String.concat "" (List.map encode_tree_entry entries))))
    (gives_a_value_or_an_error Git.Decode.ls_tree)

let batch_header_reads_a_header =
  property ~name:"batch_header gives back the header that was encoded"
    ~print:encode_batch_header batch_header (fun header ->
      Git.Decode.batch_header (encode_batch_header header) = Ok header)

let batch_header_is_total =
  property ~count:500
    ~name:"batch_header gives a value or an error for damaged output"
    ~print:QCheck2.Print.string
    Gen.(bind batch_header (fun header -> damaged (encode_batch_header header)))
    (gives_a_value_or_an_error Git.Decode.batch_header)

let decoders_are_total_on_any_bytes =
  property ~count:500
    ~name:"every decoder gives a value or an error for any bytes"
    ~print:QCheck2.Print.string any_bytes (fun output ->
      gives_a_value_or_an_error Git.Decode.nul_list output
      && gives_a_value_or_an_error Git.Decode.line output
      && gives_a_value_or_an_error Git.Decode.object_id output
      && gives_a_value_or_an_error Git.Decode.repository output
      && gives_a_value_or_an_error Git.Decode.ls_files_stage output
      && gives_a_value_or_an_error Git.Decode.ls_tree output
      && gives_a_value_or_an_error Git.Decode.batch_header output)

(* Examples of the decoders. *)

let id = String.make 40 'a'
let refuses name decode input () = holds name (Result.is_error (decode input))

let decoder_examples =
  let stage text = Git.Decode.ls_files_stage (text ^ "\000") in
  let tree text = Git.Decode.ls_tree (text ^ "\000") in
  let header = Git.Decode.batch_header in
  let case name decode input =
    Alcotest.test_case name `Quick (refuses name decode input)
  in
  [
    case "ls_files_stage refuses a mode of five digits" stage
      ("10064 " ^ id ^ " 0\ta");
    case "ls_files_stage refuses a mode with the digit 8" stage
      ("100648 " ^ id ^ " 0\ta");
    case "ls_files_stage refuses the stage 4" stage ("100644 " ^ id ^ " 4\ta");
    case "ls_files_stage refuses an empty path" stage ("100644 " ^ id ^ " 0\t");
    case "ls_files_stage refuses an entry with no tab" stage
      ("100644 " ^ id ^ " 0 a");
    case "ls_files_stage refuses an id in capitals" stage
      ("100644 " ^ String.uppercase_ascii (String.make 40 'f') ^ " 0\ta");
    case "ls_tree refuses an unknown kind" tree ("100644 file " ^ id ^ "\ta");
    case "ls_tree refuses an empty path" tree ("100644 blob " ^ id ^ "\t");
    case "ls_tree refuses an id of 41 digits" tree ("100644 blob " ^ id ^ "a\ta");
    case "batch_header refuses a size with a sign" header (id ^ " blob +5");
    case "batch_header refuses a hexadecimal size" header (id ^ " blob 0x10");
    case "batch_header refuses an empty size" header (id ^ " blob ");
    case "batch_header refuses a size too large for an integer" header
      (id ^ " blob 99999999999999999999");
    case "batch_header refuses an empty name before missing" header " missing";
    case "repository refuses a relative root" Git.Decode.repository
      "sha1\nrelative/root\n";
    case "repository refuses an empty root" Git.Decode.repository "sha1\n\n";
    case "repository refuses an unknown format" Git.Decode.repository
      "md5\n/root\n";
    case "repository refuses an output with no root line" Git.Decode.repository
      "sha1\n";
  ]

let reads_an_ambiguous_name_as_missing () =
  holds "the header is Missing"
    (Git.Decode.batch_header "abc ambiguous" = Ok (Git.Decode.Missing "abc"))

let reads_the_mode_as_octal () =
  holds "the mode is 0o100755"
    (Git.Decode.ls_tree ("100755 blob " ^ id ^ "\trun.sh\000")
    = Ok [ { Git.Decode.mode = 0o100755; kind = Blob; id; path = "run.sh" } ])

let splits_at_the_first_tab () =
  holds "the path holds the second tab"
    (Git.Decode.ls_files_stage ("100644 " ^ id ^ " 2\ta\tb\000")
    = Ok [ { Git.Decode.mode = 0o100644; id; stage = 2; path = "a\tb" } ])

(* The shared repository: {!Git_fixture.shared} lists what it holds. *)

let shared = lazy (Fixture.shared ())
let hello_id = "ce013625030ba8dba906f756967f9e9ca394464a"

let opened =
  lazy
    (ok
       (Git.open_repo
          ~env:(Fixture.env (Lazy.force shared))
          (Fixture.root (Lazy.force shared))))

(* The file set of the shared repository, and the state of its index
   before and after the call. *)
let file_set =
  lazy
    (let repo = Lazy.force shared in
     let t = Lazy.force opened in
     let before = Fixture.index_state repo in
     let files = ok (Git.files t) in
     (files, before, Fixture.index_state repo))

let files () =
  let files, _, _ = Lazy.force file_set in
  files

(* Fake gits. *)

let path_of env =
  Array.to_list env
  |> List.find_map (fun entry ->
      if String.starts_with ~prefix:"PATH=" entry then
        Some (String.sub entry 5 (String.length entry - 5))
      else None)
  |> Option.value ~default:""

let without_path env =
  Array.of_list
    (List.filter
       (fun entry -> not (String.starts_with ~prefix:"PATH=" entry))
       (Array.to_list env))

let lines_of path =
  String.split_on_char '\n' (In_channel.with_open_bin path In_channel.input_all)

(* A fake git that writes its arguments and its environment beside its
   script, and prints what [open_repo] reads. *)
let recording_script =
  "dir=${0%/*}\n\
   printf '%s\\n' \"$@\" >| \"$dir/args\"\n\
   /usr/bin/env >| \"$dir/env\"\n\
   printf 'sha256\\n%s\\n' \"$0\"\n"

let caller_variables =
  [|
    "GIT_DIR=/elsewhere/.git";
    "GIT_WORK_TREE=/elsewhere";
    "GIT_INDEX_FILE=/elsewhere/index";
    "GIT_DIFF_OPTS=--unified=9";
    "GIT_EXTERNAL_DIFF=/elsewhere/diff";
    "GIT_OPTIONAL_LOCKS=1";
    "GIT_TERMINAL_PROMPT=1";
    "SINTER_TEST_KEPT=yes";
  |]

let recorded =
  lazy
    (let env, script = Fixture.fake_git recording_script in
     let t =
       ok (Git.open_repo ~env:(Array.append env caller_variables) script)
     in
     let dir = Filename.dirname script in
     ( t,
       script,
       lines_of (Filename.concat dir "args"),
       lines_of (Filename.concat dir "env") ))

(* A fake git for the decoders of [fold_blobs] and [files]. The id that
   [fold_blobs] asks for chooses the output of [cat-file]. For the id of
   eights, a megabyte follows the header [missing]: more than a pipe
   holds, so git waits until the reader takes it. *)
let id_of digit = String.make 40 digit

let faking_script =
  Printf.sprintf
    "case \"$1\" in\n\
     rev-parse) printf 'sha1\\n%%s\\n' \"$0\" ;;\n\
     ls-files) printf 'junk' ;;\n\
     cat-file)\n\
    \  read id\n\
    \  case \"$id\" in\n\
    \  %s) printf '%%s blob 10\\nabc' \"$id\" ;;\n\
    \  %s) printf '%%s blob 3\\nabcX' \"$id\" ;;\n\
    \  %s) printf '%s blob 3\\nabc\\n' ;;\n\
    \  %s) printf 'garbage\\n' ;;\n\
    \  %s) printf '%%s blob 3\\nabc\\n' \"$id\"; exit 2 ;;\n\
    \  %s) printf '%%s missing\\n' \"$id\"; printf '%%01000000d' 0 ;;\n\
    \  esac ;;\n\
     esac\n"
    (id_of '2') (id_of '3') (id_of '4') (id_of '5') (id_of '6') (id_of '7')
    (id_of '8')

let faked =
  lazy
    (let env, script = Fixture.fake_git faking_script in
     ok (Git.open_repo ~env script))

(* Repositories. *)

let open_repo_finds_the_root () =
  let t = Lazy.force opened in
  Alcotest.(check string)
    "the root"
    (Fixture.root (Lazy.force shared))
    (Git.root t);
  holds "the format is SHA-1" (Git.object_format t = Git.Sha1)

let open_repo_finds_the_root_from_a_subdirectory () =
  let repo = Lazy.force shared in
  let t =
    ok
      (Git.open_repo ~env:(Fixture.env repo)
         (Filename.concat (Fixture.root repo) "src"))
  in
  Alcotest.(check string) "the root" (Fixture.root repo) (Git.root t)

let open_repo_refuses_a_directory_outside_a_repository () =
  let dir = Fixture.temp_dir () in
  let repo = Lazy.force shared in
  let env =
    Array.append (Fixture.env repo)
      [| "GIT_CEILING_DIRECTORIES=" ^ Filename.dirname dir |]
  in
  match error (Git.open_repo ~env dir) with
  | Not_a_repository { dir = named; detail } ->
      Alcotest.(check string) "the directory" dir named;
      holds "git said why" (detail <> "")
  | other -> Alcotest.fail (print_error other)

let open_repo_refuses_a_missing_directory () =
  let repo = Lazy.force shared in
  let dir = Filename.concat (Fixture.root repo) "no-such-directory" in
  match error (Git.open_repo ~env:(Fixture.env repo) dir) with
  | Not_a_repository { dir = named; _ } ->
      Alcotest.(check string) "the directory" dir named
  | other -> Alcotest.fail (print_error other)

let open_repo_refuses_an_empty_directory_name () =
  let repo = Lazy.force shared in
  match error (Git.open_repo ~env:(Fixture.env repo) "") with
  | Not_a_repository { dir = ""; _ } -> ()
  | other -> Alcotest.fail (print_error other)

let open_repo_needs_git_on_path () =
  let repo = Lazy.force shared in
  let empty = Fixture.temp_dir () in
  let env =
    Array.append (without_path (Fixture.env repo)) [| "PATH=" ^ empty |]
  in
  match error (Git.open_repo ~env (Fixture.root repo)) with
  | Git_not_found _ -> ()
  | other -> Alcotest.fail (print_error other)

let open_repo_needs_a_path_variable () =
  let repo = Lazy.force shared in
  match
    error
      (Git.open_repo ~env:(without_path (Fixture.env repo)) (Fixture.root repo))
  with
  | Git_not_found _ -> ()
  | other -> Alcotest.fail (print_error other)

let open_repo_reads_the_root_and_the_format () =
  let t, script, _, _ = Lazy.force recorded in
  Alcotest.(check string) "the root" script (Git.root t);
  holds "the format is SHA-256" (Git.object_format t = Git.Sha256)

let open_repo_asks_rev_parse_for_the_format_and_the_root () =
  let _, _, args, _ = Lazy.force recorded in
  Alcotest.check strings "the arguments after -C <dir>"
    [ "rev-parse"; "--show-object-format"; "--show-toplevel"; "" ]
    args

let child_environment_drops_the_variables_that_redirect_git () =
  let _, _, _, env = Lazy.force recorded in
  List.iter
    (fun name ->
      holds (name ^ " is not set")
        (not (List.exists (String.starts_with ~prefix:(name ^ "=")) env)))
    [
      "GIT_DIR";
      "GIT_WORK_TREE";
      "GIT_INDEX_FILE";
      "GIT_DIFF_OPTS";
      "GIT_EXTERNAL_DIFF";
    ]

let child_environment_sets_no_locks_and_no_prompt () =
  let _, _, _, env = Lazy.force recorded in
  let values name = List.filter (String.starts_with ~prefix:(name ^ "=")) env in
  Alcotest.check strings "GIT_OPTIONAL_LOCKS" [ "GIT_OPTIONAL_LOCKS=0" ]
    (values "GIT_OPTIONAL_LOCKS");
  Alcotest.check strings "GIT_TERMINAL_PROMPT"
    [ "GIT_TERMINAL_PROMPT=0" ]
    (values "GIT_TERMINAL_PROMPT")

let child_environment_keeps_the_other_variables () =
  let _, _, _, env = Lazy.force recorded in
  holds "SINTER_TEST_KEPT is set" (List.mem "SINTER_TEST_KEPT=yes" env)

(* The directories of PATH, in order: one that does not exist, an empty
   entry, one whose git is not executable, one whose git is a directory,
   the fake git, and a git that always fails. *)
let open_repo_takes_the_first_executable_git_on_path () =
  let env, script = Fixture.fake_git "printf 'sha1\\n%s\\n' \"$0\"\n" in
  let not_executable = Fixture.temp_dir () in
  Out_channel.with_open_bin (Filename.concat not_executable "git")
    (fun channel -> Out_channel.output_string channel "exit 9\n");
  let directory = Fixture.temp_dir () in
  Unix.mkdir (Filename.concat directory "git") 0o755;
  let failing = Fixture.temp_dir () in
  Unix.symlink "/usr/bin/false" (Filename.concat failing "git");
  let path =
    String.concat ":"
      [ "/no/such/dir"; ""; not_executable; directory; path_of env; failing ]
  in
  let env = Array.append (without_path env) [| "PATH=" ^ path |] in
  let t = ok (Git.open_repo ~env script) in
  Alcotest.(check string)
    "the root that the fake git printed" script (Git.root t)

let open_repo_reports_output_it_cannot_read () =
  let env, script = Fixture.fake_git "printf 'sha1\\n'\n" in
  match error (Git.open_repo ~env script) with
  | Malformed_output { args; _ } ->
      Alcotest.check strings "the arguments"
        [ "-C"; script; "rev-parse"; "--show-object-format"; "--show-toplevel" ]
        args
  | other -> Alcotest.fail (print_error other)

let open_repo_gives_what_git_wrote_when_it_fails () =
  let env, script = Fixture.fake_git "echo 'no repository' >&2; exit 128\n" in
  match error (Git.open_repo ~env script) with
  | Not_a_repository { dir; detail } ->
      Alcotest.(check string) "the directory" script dir;
      Alcotest.(check string) "the detail" "no repository\n" detail
  | other -> Alcotest.fail (print_error other)

(* Files. *)

let files_holds path () =
  holds (path ^ " is in the set") (List.mem path (files ()))

let files_leaves_out path () =
  holds (path ^ " is not in the set") (not (List.mem path (files ())))

let expected_files =
  [
    ".gitignore";
    "README.md";
    "bytes.bin";
    "run.sh";
    "second.txt";
    "src/main.ml";
    "tracked.log";
    "untracked.txt";
  ]

let files_is_the_expected_set_in_byte_order () =
  Alcotest.check strings "the file set" expected_files (files ())

let files_leaves_the_index_unchanged () =
  let _, before, after = Lazy.force file_set in
  Alcotest.(check string) "the index" before after

let files_ignores_the_variables_of_the_caller_that_redirect_git () =
  let repo = Lazy.force shared in
  let t =
    ok
      (Git.open_repo
         ~env:(Array.append (Fixture.env repo) caller_variables)
         (Fixture.root repo))
  in
  Alcotest.check strings "the file set" expected_files (ok (Git.files t))

(* A copy of the shared repository whose index holds three stages of
   one path, as a merge with a conflict leaves them. *)
let conflicted =
  lazy
    (let repo = Fixture.copy (Lazy.force shared) in
     let stages =
       String.concat ""
         (List.map
            (fun stage ->
              Printf.sprintf "100644 %s %d\tconflict.txt\n" hello_id stage)
            [ 1; 2; 3 ])
     in
     ignore (Fixture.git_input repo [ "update-index"; "--index-info" ] stages);
     Fixture.write repo "conflict.txt" "<<<<<<<\n";
     (repo, ok (Git.open_repo ~env:(Fixture.env repo) (Fixture.root repo))))

let files_names_a_conflicted_path_once () =
  let _, t = Lazy.force conflicted in
  let files = ok (Git.files t) in
  Alcotest.(check int)
    "the number of conflict.txt" 1
    (List.length (List.filter (String.equal "conflict.txt") files))

let files_reports_a_path_whose_type_it_cannot_read () =
  let repo, t = Lazy.force conflicted in
  let src = Filename.concat (Fixture.root repo) "src" in
  Unix.chmod src 0o000;
  let result =
    Fun.protect
      ~finally:(fun () -> Unix.chmod src 0o755)
      (fun () -> Git.files t)
  in
  match error result with
  | File_error detail ->
      holds "the error names the file"
        (String.ends_with ~suffix:"src/main.ml: Permission denied" detail)
  | other -> Alcotest.fail (print_error other)

let files_reports_output_it_cannot_read () =
  match error (Git.files (Lazy.force faked)) with
  | Malformed_output { args; _ } ->
      holds "the arguments name ls-files" (List.mem "ls-files" args)
  | other -> Alcotest.fail (print_error other)

(* The base tree and blobs. *)

let base = lazy (ok (Git.base_tree (Lazy.force opened) "main"))

let contents_of_main =
  [
    (".gitignore", "*.log\nbuild/\n");
    ("README.md", "hello\n");
    ("bytes.bin", "\000\001\n\255");
    ("gone.txt", "deleted on disk\n");
    ("run.sh", "#!/bin/sh\n");
    ("second.txt", "second\n");
    ("src/main.ml", "let () = ()\n");
    ("tracked.log", "kept although ignored\n");
  ]

let base_tree_holds_the_files_of_the_commit () =
  Alcotest.check strings "the paths"
    (List.map fst contents_of_main)
    (List.map fst (Lazy.force base))

let base_tree_gives_the_blob_of_each_file () =
  Alcotest.(check string)
    "the blob of README.md" hello_id
    (List.assoc "README.md" (Lazy.force base))

let base_tree_refuses rev () =
  match error (Git.base_tree (Lazy.force opened) rev) with
  | Bad_revision named -> Alcotest.(check string) "the revision" rev named
  | other -> Alcotest.fail (print_error other)

(* The ids and the contents that [fold_blobs] gave for the files of
   [main], in the order it gave them. *)
let blobs =
  lazy
    (let t = Lazy.force opened in
     let ids = List.map snd (Lazy.force base) in
     List.rev
       (ok
          (Git.fold_blobs t ids ~init:[] ~f:(fun acc id content ->
               (id, content) :: acc))))

let fold_blobs_reads_the_content_of_each_blob () =
  let read = Lazy.force blobs in
  Alcotest.check pairs "the contents" contents_of_main
    (List.map (fun (path, id) -> (path, List.assoc id read)) (Lazy.force base))

let fold_blobs_calls_f_in_order () =
  Alcotest.check strings "the ids"
    (List.map snd (Lazy.force base))
    (List.map fst (Lazy.force blobs))

let fold_blobs_reads_no_blob_for_an_empty_list () =
  let t = Lazy.force opened in
  Alcotest.(check int)
    "the value" 7
    (ok (Git.fold_blobs t [] ~init:7 ~f:(fun _ _ _ -> 0)))

let fold_blobs_refuses_a_name_that_is_not_an_id name () =
  let t = Lazy.force opened in
  let called = ref false in
  match
    error
      (Git.fold_blobs t [ hello_id; name ] ~init:() ~f:(fun () _ _ ->
           called := true))
  with
  | Bad_revision named ->
      Alcotest.(check string) "the name" name named;
      holds "f saw nothing" (not !called)
  | other -> Alcotest.fail (print_error other)

let fold_blobs_stops_at_an_id_that_names_no_object () =
  let t = Lazy.force opened in
  let absent = id_of 'e' in
  let seen = ref [] in
  match
    error
      (Git.fold_blobs t [ hello_id; absent ] ~init:() ~f:(fun () id _ ->
           seen := id :: !seen))
  with
  | Bad_revision named ->
      Alcotest.(check string) "the id" absent named;
      Alcotest.check strings "f saw the id in front" [ hello_id ] !seen
  | other -> Alcotest.fail (print_error other)

let key = lazy (ok (Git.tree_key (Lazy.force opened)))

let fold_blobs_refuses_an_id_that_names_a_tree () =
  let t = Lazy.force opened in
  let tree = Lazy.force key in
  match error (Git.fold_blobs t [ tree ] ~init:() ~f:(fun () _ _ -> ())) with
  | Bad_revision named -> Alcotest.(check string) "the id" tree named
  | other -> Alcotest.fail (print_error other)

let fold_blobs_reports_output_it_cannot_read digit () =
  match
    error
      (Git.fold_blobs (Lazy.force faked)
         [ id_of digit ]
         ~init:()
         ~f:(fun () _ _ -> ()))
  with
  | Malformed_output { args; _ } ->
      holds "the arguments name cat-file" (List.mem "cat-file" args)
  | other -> Alcotest.fail (print_error other)

let fold_blobs_reports_a_failed_git () =
  match
    error
      (Git.fold_blobs (Lazy.force faked)
         [ id_of '7' ]
         ~init:()
         ~f:(fun () _ _ -> ()))
  with
  | Command_failed { status; _ } ->
      holds "the status is 2" (status = Unix.WEXITED 2)
  | other -> Alcotest.fail (print_error other)

(* The tree key. *)

(* [in_temp_dir f] calls [f] while the temporary directory of the
   process is a new empty one, and gives what [f] gave and the names in
   that directory after [f]. *)
let in_temp_dir f =
  let dir = Fixture.temp_dir () in
  let previous = Filename.get_temp_dir_name () in
  Filename.set_temp_dir_name dir;
  let value =
    Fun.protect ~finally:(fun () -> Filename.set_temp_dir_name previous) f
  in
  (value, Array.to_list (Sys.readdir dir))

(* The tree key of the shared repository, the state of its index before
   and after, and the names left in the temporary directory. *)
let key_run =
  lazy
    (let repo = Lazy.force shared in
     let before = Fixture.index_state repo in
     let key, left = in_temp_dir (fun () -> Lazy.force key) in
     (key, before, Fixture.index_state repo, left))

(* A copy of the shared repository, after a real [git add -A] in it, and
   the tree that [git write-tree] then writes. *)
let added =
  lazy
    (let repo = Fixture.copy (Lazy.force shared) in
     ignore (Fixture.git repo [ "add"; "-A" ]);
     (repo, String.trim (Fixture.git repo [ "write-tree" ])))

let tree_key_is_the_tree_of_git_add_all () =
  let key, _, _, _ = Lazy.force key_run in
  let _, tree = Lazy.force added in
  Alcotest.(check string) "the tree" tree key

let tree_key_leaves_the_index_unchanged () =
  let _, before, after, _ = Lazy.force key_run in
  Alcotest.(check string) "the index" before after

let tree_key_leaves_no_temporary_file () =
  let _, _, _, left = Lazy.force key_run in
  Alcotest.check strings "the temporary directory" [] left

(* A copy of the shared repository, and its tree keys: with a new
   ignored file, then also with a new untracked file. Last, the result of
   [tree_key] when git cannot read the untracked file, and the names left
   in the temporary directory after that call. *)
let copy_run =
  lazy
    (let repo = Fixture.copy (Lazy.force shared) in
     let t = ok (Git.open_repo ~env:(Fixture.env repo) (Fixture.root repo)) in
     Fixture.write repo "more.log" "ignored\n";
     let with_ignored = ok (Git.tree_key t) in
     Fixture.write repo "more.txt" "new\n";
     let with_untracked = ok (Git.tree_key t) in
     let file = Filename.concat (Fixture.root repo) "more.txt" in
     Unix.chmod file 0o000;
     let failed, left =
       Fun.protect
         ~finally:(fun () -> Unix.chmod file 0o644)
         (fun () -> in_temp_dir (fun () -> Git.tree_key t))
     in
     (with_ignored, with_untracked, failed, left))

let tree_key_does_not_change_with_an_ignored_file () =
  let key, _, _, _ = Lazy.force key_run in
  let with_ignored, _, _, _ = Lazy.force copy_run in
  Alcotest.(check string) "the tree" key with_ignored

let tree_key_changes_with_an_untracked_file () =
  let with_ignored, with_untracked, _, _ = Lazy.force copy_run in
  holds "the key differs" (with_untracked <> with_ignored)

let tree_key_reports_a_failed_git_add () =
  let _, _, failed, _ = Lazy.force copy_run in
  match error failed with
  | Command_failed { args; _ } -> holds "git add failed" (List.mem "add" args)
  | other -> Alcotest.fail (print_error other)

let tree_key_removes_its_files_when_git_fails () =
  let _, _, _, left = Lazy.force copy_run in
  Alcotest.check strings "the temporary directory" [] left

(* A broken repository: a copy whose .git directory went away after it
   was opened. *)
let broken =
  lazy
    (let repo = Fixture.copy (Lazy.force shared) in
     let t = ok (Git.open_repo ~env:(Fixture.env repo) (Fixture.root repo)) in
     Fixture.break repo;
     t)

let reports_a_failed_git call () =
  match (error (call (Lazy.force broken)) : Git.error) with
  | Command_failed { args; status; stderr } ->
      holds "the arguments start with -C and the root"
        (match args with
        | "-C" :: root :: _ -> root = Git.root (Lazy.force broken)
        | _ -> false);
      holds "the status is 128" (status = Unix.WEXITED 128);
      holds "git said why" (stderr <> "")
  | other -> Alcotest.fail (print_error other)

(* A SHA-256 repository with one commit, no index, and no file in its
   working tree. *)
let sha256 =
  lazy
    (let repo = Fixture.init ~object_format:"sha256" () in
     Fixture.import repo
       [
         Fixture.commit ~ref:"refs/heads/main" ~mark:1 ~message:"first"
           [ Fixture.File ("README.md", "hello\n") ];
       ];
     (repo, ok (Git.open_repo ~env:(Fixture.env repo) (Fixture.root repo))))

(* The tree key of the SHA-256 repository, and the state of its index
   before and after. *)
let sha256_key =
  lazy
    (let repo, t = Lazy.force sha256 in
     let before = Fixture.index_state repo in
     let key = ok (Git.tree_key t) in
     (key, before, Fixture.index_state repo))

let sha256_repository_has_the_sha256_format () =
  let _, t = Lazy.force sha256 in
  holds "the format is SHA-256" (Git.object_format t = Git.Sha256)

let sha256_base_tree_gives_ids_of_64_digits () =
  let _, t = Lazy.force sha256 in
  let base = ok (Git.base_tree t "main") in
  Alcotest.check strings "the paths" [ "README.md" ] (List.map fst base);
  let id = List.assoc "README.md" base in
  Alcotest.(check int) "the length of the blob id" 64 (String.length id);
  Alcotest.(check string)
    "the content" "hello\n"
    (ok (Git.fold_blobs t [ id ] ~init:"" ~f:(fun _ _ content -> content)))

let empty_sha256_tree =
  "6ef19b41225c5369f1c104d45d8d85efa9b057b53b14b4b9b939dd74decc5321"

let tree_key_of_a_repository_with_no_index_is_the_empty_tree () =
  let key, _, _ = Lazy.force sha256_key in
  Alcotest.(check string) "the tree" empty_sha256_tree key

let tree_key_leaves_a_missing_index_missing () =
  let _, before, after = Lazy.force sha256_key in
  Alcotest.(check string) "the index before" "absent" before;
  Alcotest.(check string) "the index after" "absent" after

let fold_blobs_refuses_a_sha1_id_in_a_sha256_repository () =
  let _, t = Lazy.force sha256 in
  match
    error (Git.fold_blobs t [ hello_id ] ~init:() ~f:(fun () _ _ -> ()))
  with
  | Bad_revision named -> Alcotest.(check string) "the id" hello_id named
  | other -> Alcotest.fail (print_error other)

(* Resources. *)

let open_descriptors () = Array.length (Sys.readdir "/dev/fd")

(* [no_child_left ()] is [true] when the process has no child that it has
   not waited for. *)
let no_child_left () =
  match Unix.waitpid [ Unix.WNOHANG ] (-1) with
  | exception Unix.Unix_error (Unix.ECHILD, _, _) -> true
  | _ -> false

let too_long = String.make 2_000_000 'a'

(* Calls that end early: [fold_blobs] whose output ends too early,
   [base_tree] whose git does not start, and [fold_blobs] whose [f]
   raises. The result says whether the exception came through, and gives
   the names left in the temporary directory, the number of open
   descriptors before and after, and whether a child is left. *)
let raising_run =
  lazy
    (let t = Lazy.force opened in
     let before = open_descriptors () in
     let raised, left =
       in_temp_dir (fun () ->
           ignore
             (Git.fold_blobs (Lazy.force faked)
                [ id_of '2' ]
                ~init:()
                ~f:(fun () _ _ -> ()));
           ignore (Git.base_tree t too_long);
           match
             Git.fold_blobs t [ hello_id ] ~init:() ~f:(fun () _ _ ->
                 raise Exit)
           with
           | _ -> false
           | exception Exit -> true)
     in
     (raised, left, before, open_descriptors (), no_child_left ()))

let fold_blobs_passes_an_exception_of_f_through () =
  let raised, _, _, _, _ = Lazy.force raising_run in
  holds "the exception came through" raised

let no_call_leaves_a_temporary_file () =
  let _, left, _, _, _ = Lazy.force raising_run in
  Alcotest.check strings "the temporary directory" [] left

let no_call_leaves_a_descriptor_open () =
  let _, _, before, after, _ = Lazy.force raising_run in
  Alcotest.(check int) "the open descriptors" before after

let no_call_leaves_a_child () =
  let _, _, _, _, no_child = Lazy.force raising_run in
  holds "no child is left" no_child

let base_tree_reports_a_git_that_does_not_start () =
  match error (Git.base_tree (Lazy.force opened) too_long) with
  | Git_not_found _ -> ()
  | other -> Alcotest.fail (print_error other)

let fold_blobs_reads_the_output_after_an_error () =
  match
    error
      (Git.fold_blobs (Lazy.force faked)
         [ id_of '8' ]
         ~init:()
         ~f:(fun () _ _ -> ()))
  with
  | Bad_revision named -> Alcotest.(check string) "the id" (id_of '8') named
  | other -> Alcotest.fail (print_error other)

let open_repo_keeps_the_first_4096_bytes_of_the_standard_error () =
  let env, script = Fixture.fake_git "printf '%05000d' 0 >&2; exit 3\n" in
  match error (Git.open_repo ~env script) with
  | Not_a_repository { detail; _ } ->
      Alcotest.(check string) "the detail" (String.make 4096 '0') detail
  | other -> Alcotest.fail (print_error other)

let reports_a_temporary_directory_that_does_not_exist () =
  let env, script = Fixture.fake_git "printf 'sha1\\n%s\\n' \"$0\"\n" in
  let missing = Filename.concat (Fixture.temp_dir ()) "missing" in
  let previous = Filename.get_temp_dir_name () in
  Filename.set_temp_dir_name missing;
  let result =
    Fun.protect
      ~finally:(fun () -> Filename.set_temp_dir_name previous)
      (fun () -> Git.open_repo ~env script)
  in
  match error result with
  | File_error _ -> ()
  | other -> Alcotest.fail (print_error other)

let tree_key_reports_an_index_it_cannot_read () =
  let repo = Fixture.copy (Lazy.force shared) in
  let index = Filename.concat (Fixture.root repo) ".git/index" in
  let t = ok (Git.open_repo ~env:(Fixture.env repo) (Fixture.root repo)) in
  Unix.chmod index 0o000;
  let result =
    Fun.protect
      ~finally:(fun () -> Unix.chmod index 0o644)
      (fun () -> Git.tree_key t)
  in
  match error result with
  | File_error detail ->
      holds "the error names the index"
        (String.starts_with ~prefix:index detail)
  | other -> Alcotest.fail (print_error other)

(* A fake git closes its output and then lives on for 30 ms, so that
   [open_repo] waits for it. A timer interrupts that wait after 10 ms. *)
let open_repo_waits_again_after_a_signal () =
  let env, script =
    Fixture.fake_git
      "printf 'sha1\\n%s\\n' \"$0\"\nexec >&-\nexec /bin/sleep 0.03\n"
  in
  let previous = Sys.signal Sys.sigalrm (Sys.Signal_handle ignore) in
  let stop = { Unix.it_interval = 0.; it_value = 0. } in
  let result =
    Fun.protect
      ~finally:(fun () ->
        ignore (Unix.setitimer Unix.ITIMER_REAL stop);
        Sys.set_signal Sys.sigalrm previous)
      (fun () ->
        ignore
          (Unix.setitimer Unix.ITIMER_REAL
             { Unix.it_interval = 0.; it_value = 0.01 });
        Git.open_repo ~env script)
  in
  Alcotest.(check string) "the root" script (Git.root (ok result))

let quick name f = Alcotest.test_case name `Quick f

let tests =
  [
    nul_list_gives_back_the_records;
    nul_list_needs_a_final_nul;
    line_takes_off_one_line_feed;
    line_needs_a_final_line_feed;
    object_id_reads_an_id;
    object_id_refuses_a_damaged_id;
    repository_reads_its_output;
    repository_is_total;
    ls_files_stage_reads_its_output;
    ls_files_stage_is_total;
    ls_tree_reads_its_output;
    ls_tree_is_total;
    batch_header_reads_a_header;
    batch_header_is_total;
    decoders_are_total_on_any_bytes;
    quick "batch_header reads an ambiguous name as missing"
      reads_an_ambiguous_name_as_missing;
    quick "ls_tree reads the mode as octal" reads_the_mode_as_octal;
    quick "ls_files_stage splits at the first tab" splits_at_the_first_tab;
  ]
  @ decoder_examples
  @ [
      quick "open_repo finds the root" open_repo_finds_the_root;
      quick "open_repo finds the root from a subdirectory"
        open_repo_finds_the_root_from_a_subdirectory;
      quick "open_repo refuses a directory outside a repository"
        open_repo_refuses_a_directory_outside_a_repository;
      quick "open_repo refuses a missing directory"
        open_repo_refuses_a_missing_directory;
      quick "open_repo refuses an empty directory name"
        open_repo_refuses_an_empty_directory_name;
      quick "open_repo needs git on PATH" open_repo_needs_git_on_path;
      quick "open_repo needs a PATH variable" open_repo_needs_a_path_variable;
      quick "open_repo reads the root and the format"
        open_repo_reads_the_root_and_the_format;
      quick "open_repo asks rev-parse for the format and the root"
        open_repo_asks_rev_parse_for_the_format_and_the_root;
      quick "the child environment drops the variables that redirect git"
        child_environment_drops_the_variables_that_redirect_git;
      quick "the child environment sets no locks and no prompt"
        child_environment_sets_no_locks_and_no_prompt;
      quick "the child environment keeps the other variables"
        child_environment_keeps_the_other_variables;
      quick "open_repo takes the first executable git on PATH"
        open_repo_takes_the_first_executable_git_on_path;
      quick "open_repo reports output it cannot read"
        open_repo_reports_output_it_cannot_read;
      quick "open_repo gives what git wrote when it fails"
        open_repo_gives_what_git_wrote_when_it_fails;
      quick "files is the expected set in byte order"
        files_is_the_expected_set_in_byte_order;
      quick "files holds an untracked file" (files_holds "untracked.txt");
      quick "files holds a tracked file that .gitignore matches"
        (files_holds "tracked.log");
      quick "files leaves out an ignored file" (files_leaves_out "ignored.log");
      quick "files leaves out a file in an ignored directory"
        (files_leaves_out "build/out.o");
      quick "files leaves out a tracked file deleted on disk"
        (files_leaves_out "gone.txt");
      quick "files leaves out a tracked symbolic link" (files_leaves_out "link");
      quick "files leaves out a tracked symbolic link that is a file on disk"
        (files_leaves_out "link-as-file");
      quick "files leaves out an untracked symbolic link"
        (files_leaves_out "untracked-link");
      quick "files leaves out a submodule" (files_leaves_out "sub");
      quick "files leaves out a submodule that is a file on disk"
        (files_leaves_out "sub-as-file");
      quick "files leaves out the files of a repository inside the working tree"
        (files_leaves_out "nested/inner.txt");
      quick "files leaves the index unchanged" files_leaves_the_index_unchanged;
      quick "files ignores the variables of the caller that redirect git"
        files_ignores_the_variables_of_the_caller_that_redirect_git;
      quick "files names a conflicted path once"
        files_names_a_conflicted_path_once;
      quick "files reports a path whose type it cannot read"
        files_reports_a_path_whose_type_it_cannot_read;
      quick "files reports output it cannot read"
        files_reports_output_it_cannot_read;
      quick "base_tree holds the files of the commit"
        base_tree_holds_the_files_of_the_commit;
      quick "base_tree gives the blob of each file"
        base_tree_gives_the_blob_of_each_file;
      quick "base_tree refuses an unknown name"
        (base_tree_refuses "no-such-branch");
      quick "base_tree refuses a name that starts with a hyphen"
        (base_tree_refuses "-main");
      quick "base_tree refuses an empty name" (base_tree_refuses "");
      quick "base_tree refuses the id of a blob" (base_tree_refuses hello_id);
      quick "fold_blobs reads the content of each blob"
        fold_blobs_reads_the_content_of_each_blob;
      quick "fold_blobs calls f in the order of the ids"
        fold_blobs_calls_f_in_order;
      quick "fold_blobs reads no blob for an empty list"
        fold_blobs_reads_no_blob_for_an_empty_list;
      quick "fold_blobs refuses a name that is not an id"
        (fold_blobs_refuses_a_name_that_is_not_an_id "HEAD");
      quick "fold_blobs refuses an id in capitals"
        (fold_blobs_refuses_a_name_that_is_not_an_id
           (String.uppercase_ascii hello_id));
      quick "fold_blobs refuses a SHA-256 id in a SHA-1 repository"
        (fold_blobs_refuses_a_name_that_is_not_an_id (String.make 64 'a'));
      quick "fold_blobs stops at an id that names no object"
        fold_blobs_stops_at_an_id_that_names_no_object;
      quick "fold_blobs refuses an id that names a tree"
        fold_blobs_refuses_an_id_that_names_a_tree;
      quick "fold_blobs reports a blob cut short"
        (fold_blobs_reports_output_it_cannot_read '2');
      quick "fold_blobs reports a blob with no line feed after it"
        (fold_blobs_reports_output_it_cannot_read '3');
      quick "fold_blobs reports a blob of another id"
        (fold_blobs_reports_output_it_cannot_read '4');
      quick "fold_blobs reports a header it cannot read"
        (fold_blobs_reports_output_it_cannot_read '6');
      quick "fold_blobs reports an output with no header"
        (fold_blobs_reports_output_it_cannot_read '1');
      quick "fold_blobs reports a failed git" fold_blobs_reports_a_failed_git;
      quick "tree_key is the tree of git add -A"
        tree_key_is_the_tree_of_git_add_all;
      quick "tree_key leaves the index unchanged"
        tree_key_leaves_the_index_unchanged;
      quick "tree_key leaves no temporary file"
        tree_key_leaves_no_temporary_file;
      quick "tree_key does not change with an ignored file"
        tree_key_does_not_change_with_an_ignored_file;
      quick "tree_key changes with an untracked file"
        tree_key_changes_with_an_untracked_file;
      quick "tree_key reports a failed git add"
        tree_key_reports_a_failed_git_add;
      quick "tree_key removes its files when git fails"
        tree_key_removes_its_files_when_git_fails;
      quick "files reports a failed git" (reports_a_failed_git Git.files);
      quick "base_tree reports a failed git"
        (reports_a_failed_git (fun t -> Git.base_tree t "main"));
      quick "tree_key reports a failed git" (reports_a_failed_git Git.tree_key);
      quick "a SHA-256 repository has the SHA-256 format"
        sha256_repository_has_the_sha256_format;
      quick "base_tree gives ids of 64 digits in a SHA-256 repository"
        sha256_base_tree_gives_ids_of_64_digits;
      quick "tree_key of a repository with no index is the empty tree"
        tree_key_of_a_repository_with_no_index_is_the_empty_tree;
      quick "tree_key leaves a missing index missing"
        tree_key_leaves_a_missing_index_missing;
      quick "fold_blobs refuses a SHA-1 id in a SHA-256 repository"
        fold_blobs_refuses_a_sha1_id_in_a_sha256_repository;
      quick "fold_blobs passes an exception of f through"
        fold_blobs_passes_an_exception_of_f_through;
      quick "no call leaves a temporary file" no_call_leaves_a_temporary_file;
      quick "no call leaves a descriptor open" no_call_leaves_a_descriptor_open;
      quick "no call leaves a child" no_call_leaves_a_child;
      quick "base_tree reports a git that does not start"
        base_tree_reports_a_git_that_does_not_start;
      quick "fold_blobs reads the output after an error"
        fold_blobs_reads_the_output_after_an_error;
      quick "open_repo keeps the first 4096 bytes of the standard error"
        open_repo_keeps_the_first_4096_bytes_of_the_standard_error;
      quick "a call reports a temporary directory that does not exist"
        reports_a_temporary_directory_that_does_not_exist;
      quick "tree_key reports an index it cannot read"
        tree_key_reports_an_index_it_cannot_read;
      quick "open_repo waits again after a signal"
        open_repo_waits_again_after_a_signal;
    ]
