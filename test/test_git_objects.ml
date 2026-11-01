(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

open Sinter_core
module Gen = QCheck2.Gen
module Repo = Git_fixture

let property ?(count = 200) ~name ~print generator check =
  QCheck_alcotest.to_alcotest ~speed_level:`Quick
    (QCheck2.Test.make ~count ~name ~print generator check)

let ( let* ) = Result.bind
let holds name condition = Alcotest.(check bool) name true condition

let print_error : Git.error -> string = function
  | Git_not_found detail -> "Git_not_found " ^ detail
  | Not_a_repository { dir; detail } ->
      Printf.sprintf "Not_a_repository %S: %s" dir detail
  | Bad_revision rev -> Printf.sprintf "Bad_revision %S" rev
  | Default_branch_not_found name ->
      Printf.sprintf "Default_branch_not_found %S" name
  | No_merge_base (a, b) -> Printf.sprintf "No_merge_base %S %S" a b
  | Command_failed { args; stderr; _ } ->
      Printf.sprintf "Command_failed [%s]: %s" (String.concat " " args) stderr
  | Malformed_output { args; detail } ->
      Printf.sprintf "Malformed_output [%s]: %s" (String.concat " " args) detail
  | File_error detail -> "File_error " ^ detail

let ok = function
  | Ok value -> value
  | Error error -> Alcotest.fail (print_error error)

let error = function
  | Ok _ -> Alcotest.fail "the call gave a value, and an error was expected"
  | Error error -> error

let hex_digit = Gen.oneof_list (String.to_seq "0123456789abcdef" |> List.of_seq)
let hex length = Gen.string_size ~gen:hex_digit (Gen.return length)
let format = Gen.oneof_list [ Git.Sha1; Git.Sha256 ]
let id_length = function Git.Sha1 -> 40 | Git.Sha256 -> 64

let bytes_of_hex text =
  String.init
    (String.length text / 2)
    (fun i -> Char.chr (int_of_string ("0x" ^ String.sub text (2 * i) 2)))

let gives_a_value_or_an_error decode input =
  match decode input with Ok _ | Error _ -> true

let damaged text =
  Gen.(
    oneof
      [
        map
          (fun cut -> String.sub text 0 (cut mod (String.length text + 1)))
          nat;
        map
          (fun (at, byte) ->
            let at = at mod max 1 (String.length text) in
            if text = "" then String.make 1 byte
            else String.mapi (fun i c -> if i = at then byte else c) text)
          (pair nat char);
        map (fun extra -> text ^ extra) string_small;
      ])

(* Commit objects *)

let commit_header =
  Gen.(
    bind format (fun format ->
        let id = hex (id_length format) in
        map2
          (fun tree parents -> { Git.Decode.tree; parents })
          id
          (list_size (int_range 0 3) id)))

let encode_commit ?(extra = "") ({ tree; parents } : Git.Decode.commit_object) =
  String.concat ""
    (("tree " ^ tree ^ "\n")
    :: List.map (fun parent -> "parent " ^ parent ^ "\n") parents)
  ^ "author A <a@example.com> 0 +0000\ncommitter A <a@example.com> 0 +0000\n"
  ^ extra ^ "\nthe message\n"

let commit_object_reads_its_header =
  property ~name:"commit_object gives back the tree and the parents"
    ~print:encode_commit commit_header (fun header ->
      Git.Decode.commit_object (encode_commit header) = Ok header)

let commit_object_is_total =
  property ~count:500
    ~name:"commit_object gives a value or an error for damaged content"
    ~print:QCheck2.Print.string
    Gen.(bind commit_header (fun header -> damaged (encode_commit header)))
    (gives_a_value_or_an_error Git.Decode.commit_object)

let tree_id = String.make 40 'a'
let parent_id = String.make 40 'b'

let commit_object_refuses name content () =
  holds name (Result.is_error (Git.Decode.commit_object content))

let commit_object_reads_a_signed_header () =
  let content =
    encode_commit
      ~extra:
        ("gpgsig -----BEGIN-----\n parent " ^ parent_id ^ "\n -----END-----\n")
      { tree = tree_id; parents = [] }
  in
  Alcotest.(check (list string))
    "the parents" []
    (match Git.Decode.commit_object content with
    | Ok { parents; _ } -> parents
    | Error detail -> Alcotest.fail detail)

let commit_object_says_what_is_wrong () =
  Alcotest.(check (list (result unit string)))
    "the errors"
    [
      Error "the header of the commit does not end with an empty line";
      Error "the commit has no tree line";
      Error "\"x\" is not a tree line";
      Error "\"tree abc\" does not name an object id";
    ]
    (List.map
       (fun content -> Result.map ignore (Git.Decode.commit_object content))
       [ ""; "\n"; "x\n\n"; "tree abc\n\n" ])

let commit_object_examples =
  let case name content =
    Alcotest.test_case name `Quick (commit_object_refuses name content)
  in
  [
    Alcotest.test_case "commit_object says what is wrong" `Quick
      commit_object_says_what_is_wrong;
    case "an empty commit" "";
    case "no tree line first"
      ("parent " ^ parent_id ^ "\ntree " ^ tree_id ^ "\n\n");
    case "a tree line with a short id" "tree abc\n\n";
    case "a parent line with an upper-case id"
      ("tree " ^ tree_id ^ "\nparent " ^ String.make 40 'B' ^ "\n\n");
    case "a parent line after the author line"
      ("tree " ^ tree_id ^ "\nauthor A <a> 0 +0000\nparent " ^ parent_id
     ^ "\n\n");
    case "a header with no empty line after it" ("tree " ^ tree_id ^ "\n");
    Alcotest.test_case "a parent line in a continuation line is no parent"
      `Quick commit_object_reads_a_signed_header;
  ]

(* Tree objects *)

let tree_name =
  Gen.(
    string_size ~gen:(map Char.chr (int_range 1 255)) (int_range 1 8)
    |> map (String.map (fun c -> if c = '/' then '-' else c)))

let tree_records format =
  Gen.(
    list_size (int_range 0 4)
      (map3
         (fun mode name id -> { Git.Decode.mode; name; id })
         (oneof_list [ 0o100644; 0o100755; 0o120000; 0o160000; 0o40000 ])
         tree_name
         (hex (id_length format))))

let encode_tree records =
  String.concat ""
    (List.map
       (fun ({ mode; name; id } : Git.Decode.tree_record) ->
         Printf.sprintf "%o %s\000%s" mode name (bytes_of_hex id))
       records)

let tree_object_reads_its_records =
  property ~name:"tree_object gives back the records that were encoded"
    ~print:(fun (_, records) -> encode_tree records)
    Gen.(bind format (fun format -> pair (return format) (tree_records format)))
    (fun (format, records) ->
      Git.Decode.tree_object format (encode_tree records) = Ok records)

let tree_object_is_total =
  property ~count:500
    ~name:"tree_object gives a value or an error for damaged content"
    ~print:(fun (_, text) -> text)
    Gen.(
      bind format (fun format ->
          pair (return format)
            (bind (tree_records format) (fun records ->
                 damaged (encode_tree records)))))
    (fun (format, content) ->
      gives_a_value_or_an_error (Git.Decode.tree_object format) content)

let raw_id = String.make 20 '\xab'

let tree_object_refuses name content () =
  holds name (Result.is_error (Git.Decode.tree_object Git.Sha1 content))

let tree_object_examples =
  let case name content =
    Alcotest.test_case name `Quick (tree_object_refuses name content)
  in
  [
    case "a mode of seven digits" ("1006440 a\000" ^ raw_id);
    case "a mode that is not octal" ("100648 a\000" ^ raw_id);
    case "an empty mode" (" a\000" ^ raw_id);
    case "a mode with an underscore" ("1_0 a\000" ^ raw_id);
    case "a mode with an eight" ("18 a\000" ^ raw_id);
    Alcotest.test_case "a mode of one digit and one of six" `Quick (fun () ->
        Alcotest.(check (list int))
          "the modes" [ 0o7; 0o100644 ]
          (match
             Git.Decode.tree_object Git.Sha1
               ("7 a\000" ^ raw_id ^ "100644 b\000" ^ raw_id)
           with
          | Ok records ->
              List.map (fun (r : Git.Decode.tree_record) -> r.mode) records
          | Error detail -> Alcotest.fail detail));
    case "an empty name" ("100644 \000" ^ raw_id);
    case "a name with a slash" ("100644 a/b\000" ^ raw_id);
    case "an id cut short" ("100644 a\000" ^ String.sub raw_id 0 19);
    case "an entry with no NUL byte" "100644 a";
    Alcotest.test_case "a SHA-256 tree takes 32 bytes" `Quick (fun () ->
        Alcotest.(check bool)
          "the record" true
          (Git.Decode.tree_object Git.Sha256
             ("40000 entries\000" ^ String.make 32 '\x01')
          = Ok
              [
                {
                  Git.Decode.mode = 0o40000;
                  name = "entries";
                  id = String.concat "" (List.init 32 (fun _ -> "01"));
                };
              ]));
  ]

(* A repository *)

let input repo args text = String.trim (Repo.git_input repo args text)

let made =
  lazy
    (let repo = Repo.init () in
     let blob = input repo [ "hash-object"; "-w"; "--stdin" ] "a line\n" in
     let tree = input repo [ "mktree" ] ("100644 blob " ^ blob ^ "\tchunk\n") in
     let first = input repo [ "commit-tree"; tree; "-m"; "first" ] "" in
     let second =
       input repo [ "commit-tree"; tree; "-p"; first; "-m"; "second" ] ""
     in
     ignore (Repo.git repo [ "update-ref"; "refs/sinter/ledger"; second ]);
     ignore (Repo.git repo [ "tag"; "-a"; "-m"; "a tag"; "a-tag"; second ]);
     let tag = String.trim (Repo.git repo [ "rev-parse"; "refs/tags/a-tag" ]) in
     ignore (Repo.git repo [ "update-ref"; "refs/sinter/tagged"; tag ]);
     ignore (Repo.git repo [ "update-ref"; "refs/sinter/tree"; tree ]);
     ignore (Repo.git repo [ "update-ref"; "refs/sinter/ledgers"; first ]);
     (repo, blob, tree, first, second, tag))

let opened repo = ok (Git.open_repo ~env:(Repo.env repo) (Repo.root repo))

let ref_target_names_an_object () =
  let repo, _, tree, _, second, tag = Lazy.force made in
  let t = opened repo in
  let target name = ok (Git.ref_target t name) in
  holds "the ledger names its commit" (target "refs/sinter/ledger" = Some second);
  holds "a tag is not peeled" (target "refs/sinter/tagged" = Some tag);
  holds "a tree is a tree" (target "refs/sinter/tree" = Some tree);
  holds "an absent ref is None" (target "refs/sinter/none" = None);
  holds "a ref whose name starts with the name is not the ref"
    (target "refs/sinter/ledg" = None)

let write_ref repo name text =
  let path = Filename.concat (Repo.root repo) (".git/" ^ name) in
  Out_channel.with_open_bin path (fun channel ->
      Out_channel.output_string channel text)

let ref_target_names_an_object_that_the_clone_lacks () =
  let repo, _, _, _, _, _ = Lazy.force made in
  let copy = Repo.copy repo in
  let missing = String.make 40 'd' in
  write_ref copy "refs/sinter/missing" (missing ^ "\n");
  holds "the id"
    (ok (Git.ref_target (opened copy) "refs/sinter/missing") = Some missing)

let ref_target_takes_a_broken_ref_as_no_ref () =
  let repo, _, _, _, _, _ = Lazy.force made in
  let copy = Repo.copy repo in
  write_ref copy "refs/sinter/garbage" "garbage\n";
  holds "no ref" (ok (Git.ref_target (opened copy) "refs/sinter/garbage") = None)

let ref_target_refuses name () =
  let repo, _, _, _, _, _ = Lazy.force made in
  match error (Git.ref_target (opened repo) name) with
  | Bad_revision named -> Alcotest.(check string) "the name" name named
  | other -> Alcotest.fail (print_error other)

let read repo id =
  ok
    (Git.with_objects (opened repo) (fun objects -> Git.read_object objects id))

let read_object_reads_each_kind () =
  let repo, blob, tree, first, second, tag = Lazy.force made in
  let kind id =
    match read repo id with
    | Git.Found { kind; _ } -> Some kind
    | Git.Absent -> None
  in
  holds "a blob" (kind blob = Some Git.Decode.Blob);
  holds "a tree" (kind tree = Some Git.Decode.Tree);
  holds "a commit" (kind second = Some Git.Decode.Commit);
  holds "a tag" (kind tag = Some Git.Decode.Tag);
  holds "the content of a blob"
    (read repo blob = Git.Found { kind = Git.Decode.Blob; content = "a line\n" });
  match read repo second with
  | Git.Found { content; _ } ->
      holds "the commit names its parent"
        (Git.Decode.commit_object content
        = Ok { Git.Decode.tree; parents = [ first ] })
  | Git.Absent -> Alcotest.fail "the commit is absent"

let read_object_reads_many_objects_with_one_process () =
  let repo, blob, tree, first, second, _ = Lazy.force made in
  let ids = [ blob; tree; first; second; blob ] in
  let commands =
    Repo.git_commands repo (fun env ->
        let t = ok (Git.open_repo ~env (Repo.root repo)) in
        ignore
          (ok
             (Git.with_objects t (fun objects ->
                  List.fold_left
                    (fun result id ->
                      Result.bind result (fun () ->
                          Result.map ignore (Git.read_object objects id)))
                    (Ok ()) ids))))
  in
  Alcotest.(check int)
    "one cat-file" 1
    (List.length
       (List.filter
          (fun command ->
            List.exists
              (fun word -> word = "cat-file" || word = "'cat-file'")
              (String.split_on_char ' ' command))
          commands))

let read_objects_reads_in_order () =
  let repo, blob, tree, first, second, _ = Lazy.force made in
  let absent = String.make 40 'e' in
  let ids =
    List.concat (List.init 30 (fun _ -> [ blob; tree; absent; first; second ]))
  in
  let found =
    ok
      (Git.with_objects (opened repo) (fun objects ->
           Git.read_objects objects ids))
  in
  let kinds =
    List.map
      (function Git.Found { kind; _ } -> Some kind | Git.Absent -> None)
      found
  in
  Alcotest.(check int) "one answer for each id" 150 (List.length found);
  holds "the answers come in the order of the ids"
    (kinds
    = List.concat
        (List.init 30 (fun _ ->
             [
               Some Git.Decode.Blob;
               Some Git.Decode.Tree;
               None;
               Some Git.Decode.Commit;
               Some Git.Decode.Commit;
             ])))

let read_objects_refuses_a_bad_id_first () =
  let repo, blob, _, _, _, _ = Lazy.force made in
  match
    error
      (Git.with_objects (opened repo) (fun objects ->
           Git.read_objects objects [ blob; "HEAD" ]))
  with
  | Bad_revision "HEAD" -> ()
  | other -> Alcotest.fail (print_error other)

let read_objects_reads_nothing_for_no_id () =
  let repo, _, _, _, _, _ = Lazy.force made in
  holds "no answer"
    (ok
       (Git.with_objects (opened repo) (fun objects ->
            Git.read_objects objects []))
    = [])

let read_objects_refuses_a_use_after_the_end () =
  let repo, blob, _, _, _, _ = Lazy.force made in
  let kept = ok (Git.with_objects (opened repo) (fun objects -> Ok objects)) in
  Alcotest.check_raises "the process has ended"
    (Invalid_argument "Sinter_core.Git.read_objects: the process has ended")
    (fun () -> ignore (Git.read_objects kept [ blob ]))

let read_object_gives_absent_for_an_unknown_id () =
  let repo, _, _, _, _, _ = Lazy.force made in
  holds "absent" (read repo (String.make 40 'e') = Git.Absent)

let read_object_refuses name () =
  let repo, _, _, _, _, _ = Lazy.force made in
  match
    error
      (Git.with_objects (opened repo) (fun objects ->
           Git.read_object objects name))
  with
  | Bad_revision named -> Alcotest.(check string) "the name" name named
  | other -> Alcotest.fail (print_error other)

let read_object_ignores_grafts_and_replacements () =
  let repo, _, tree, first, second, _ = Lazy.force made in
  let copy = Repo.copy repo in
  let other = input copy [ "commit-tree"; tree; "-m"; "another" ] "" in
  let git_dir = Filename.concat (Repo.root copy) ".git" in
  (try Unix.mkdir (Filename.concat git_dir "info") 0o755
   with Unix.Unix_error (Unix.EEXIST, _, _) -> ());
  Out_channel.with_open_bin (Filename.concat git_dir "info/grafts")
    (fun channel ->
      Out_channel.output_string channel (second ^ " " ^ other ^ "\n"));
  ignore (Repo.git copy [ "replace"; "-f"; second; other ]);
  holds "git reads the replacement"
    (String.trim (Repo.git copy [ "cat-file"; "-p"; second ])
    = String.trim (Repo.git copy [ "cat-file"; "-p"; other ]));
  match read copy second with
  | Git.Found { content; _ } ->
      holds "the raw commit names its own parent"
        (Git.Decode.commit_object content
        = Ok { Git.Decode.tree; parents = [ first ] })
  | Git.Absent -> Alcotest.fail "the commit is absent"

let read_object_refuses_a_use_after_the_end () =
  let repo, blob, _, _, _, _ = Lazy.force made in
  let kept = ok (Git.with_objects (opened repo) (fun objects -> Ok objects)) in
  Alcotest.check_raises "the process has ended"
    (Invalid_argument "Sinter_core.Git.read_object: the process has ended")
    (fun () -> ignore (Git.read_object kept blob))

let descriptors () = Array.length (Sys.readdir "/dev/fd")

let with_objects_passes_an_exception_through () =
  let repo, _, _, _, _, _ = Lazy.force made in
  let t = opened repo in
  let before = descriptors () in
  let pipe = Sys.signal Sys.sigpipe Sys.Signal_default in
  Alcotest.check_raises "the exception" Exit (fun () ->
      ignore (Git.with_objects t (fun _ -> raise Exit)));
  let after = Sys.signal Sys.sigpipe pipe in
  holds "the behaviour of SIGPIPE comes back" (after = Sys.Signal_default);
  Alcotest.(check int) "no descriptor stays open" before (descriptors ())

let with_objects_closes_every_descriptor () =
  let repo, blob, _, _, _, _ = Lazy.force made in
  let t = opened repo in
  let before = descriptors () in
  for _ = 1 to 3 do
    ignore
      (Git.with_objects t (fun objects ->
           Result.map ignore (Git.read_object objects blob)))
  done;
  Alcotest.(check int) "the open descriptors" before (descriptors ())

let with_objects_counts_its_waits () =
  let repo, blob, tree, _, _, _ = Lazy.force made in
  let waits =
    ok
      (Git.with_objects (opened repo) (fun objects ->
           let* _ = Git.read_object objects blob in
           let* _ = Git.read_objects objects (List.init 130 (fun _ -> tree)) in
           let* _ = Git.read_objects objects [] in
           Ok (Git.waits objects)))
  in
  Alcotest.(check int) "one and three" 4 waits

let with_objects_gives_the_error_of_f () =
  let repo, _, _, _, _, _ = Lazy.force made in
  match
    error (Git.with_objects (opened repo) (fun _ -> Error (Git.File_error "f")))
  with
  | File_error "f" -> ()
  | other -> Alcotest.fail (print_error other)

let with_objects_reports_a_failed_git () =
  let repo, blob, _, _, _, _ = Lazy.force made in
  let copy = Repo.copy repo in
  let t = opened copy in
  Repo.break copy;
  match
    error (Git.with_objects t (fun objects -> Git.read_object objects blob))
  with
  | Command_failed { args; _ } ->
      holds "the arguments name cat-file" (List.mem "cat-file" args)
  | other -> Alcotest.fail (print_error other)

let faked script =
  let env, path = Repo.fake_git script in
  ok (Git.open_repo ~env path)

let fake_answer answer =
  faked
    (Printf.sprintf
       "while [ \"$1\" = -c ]; do shift 2; done\n\
        case \"$1\" in\n\
        rev-parse) printf 'sha1\\n%%s\\n' \"$0\" ;;\n\
        cat-file) read id; printf '%s' ;;\n\
        esac\n"
       answer)

let read_object_reports_an_answer_it_cannot_read answer () =
  match
    error
      (Git.with_objects (fake_answer answer) (fun objects ->
           Git.read_object objects (String.make 40 '1')))
  with
  | Malformed_output { args; _ } ->
      holds "the arguments name cat-file" (List.mem "cat-file" args)
  | other -> Alcotest.fail (print_error other)

let read_object_survives_a_git_that_ends_at_once () =
  let t =
    faked
      "while [ \"$1\" = -c ]; do shift 2; done\n\
       case \"$1\" in\n\
       rev-parse) printf 'sha1\\n%s\\n' \"$0\" ;;\n\
       cat-file) exec 0<&- ;;\n\
       esac\n"
  in
  let before = Sys.signal Sys.sigpipe Sys.Signal_default in
  let result =
    Git.with_objects t (fun objects ->
        List.fold_left
          (fun result _ ->
            Result.bind result (fun () ->
                Result.map ignore (Git.read_object objects (String.make 40 '1'))))
          (Ok ()) (List.init 50 Fun.id))
  in
  let after = Sys.signal Sys.sigpipe before in
  holds "the read fails" (Result.is_error result);
  holds "the behaviour of SIGPIPE comes back" (after = Sys.Signal_default)

let with_objects_closes_its_pipes_when_git_does_not_start () =
  let env, path =
    Repo.fake_git
      "while [ \"$1\" = -c ]; do shift 2; done\n\
       case \"$1\" in\n\
       rev-parse) printf 'sha1\\n%s\\n' \"$0\" ;;\n\
       esac\n"
  in
  let t = ok (Git.open_repo ~env path) in
  Sys.remove
    (Filename.concat (Filename.concat (Filename.dirname path) "bin") "git");
  let before = descriptors () in
  (match Git.with_objects t (fun _ -> Ok ()) with
  | Error (Git_not_found _) -> ()
  | Ok () -> Alcotest.fail "git started"
  | Error other -> Alcotest.fail (print_error other));
  Alcotest.(check int) "the open descriptors" before (descriptors ())

let with_objects_reads_what_git_writes_after_a_bad_answer () =
  let t =
    faked
      "while [ \"$1\" = -c ]; do shift 2; done\n\
       case \"$1\" in\n\
       rev-parse) printf 'sha1\\n%s\\n' \"$0\" ;;\n\
       cat-file) read id; printf 'junk\\n'; i=0; while [ $i -lt 4000 ]; do \
       printf '%0100d' 0; i=$((i+1)); done ;;\n\
       esac\n"
  in
  match
    error
      (Git.with_objects t (fun objects ->
           Git.read_object objects (String.make 40 '1')))
  with
  | Malformed_output _ -> ()
  | other -> Alcotest.fail (print_error other)

let one = String.make 40 '1'
let two = String.make 40 '2'

let tests =
  [
    commit_object_reads_its_header;
    commit_object_is_total;
    tree_object_reads_its_records;
    tree_object_is_total;
  ]
  @ commit_object_examples @ tree_object_examples
  @ [
      Alcotest.test_case "ref_target names the object of a ref" `Quick
        ref_target_names_an_object;
      Alcotest.test_case "ref_target names an object that the clone lacks"
        `Quick ref_target_names_an_object_that_the_clone_lacks;
      Alcotest.test_case "ref_target takes a broken ref as no ref" `Quick
        ref_target_takes_a_broken_ref_as_no_ref;
      Alcotest.test_case "ref_target refuses a name outside refs/" `Quick
        (ref_target_refuses "HEAD");
      Alcotest.test_case "ref_target refuses a name with a space" `Quick
        (ref_target_refuses "refs/a b");
      Alcotest.test_case "ref_target refuses a name with a line feed" `Quick
        (ref_target_refuses "refs/a\nb");
      Alcotest.test_case "ref_target refuses a name with a NUL byte" `Quick
        (ref_target_refuses "refs/a\000b");
      Alcotest.test_case "read_object reads each kind of object" `Quick
        read_object_reads_each_kind;
      Alcotest.test_case "with_objects runs one cat-file for many reads" `Quick
        read_object_reads_many_objects_with_one_process;
      Alcotest.test_case "read_objects answers each id in order" `Quick
        read_objects_reads_in_order;
      Alcotest.test_case "read_objects refuses a bad id" `Quick
        read_objects_refuses_a_bad_id_first;
      Alcotest.test_case "read_objects reads nothing for no id" `Quick
        read_objects_reads_nothing_for_no_id;
      Alcotest.test_case "read_objects refuses a use after the end" `Quick
        read_objects_refuses_a_use_after_the_end;
      Alcotest.test_case "read_object gives Absent for an unknown id" `Quick
        read_object_gives_absent_for_an_unknown_id;
      Alcotest.test_case "read_object refuses a short id" `Quick
        (read_object_refuses "abc");
      Alcotest.test_case
        "read_object refuses a SHA-256 id in a SHA-1 repository" `Quick
        (read_object_refuses (String.make 64 'a'));
      Alcotest.test_case "read_object refuses a revision" `Quick
        (read_object_refuses "HEAD");
      Alcotest.test_case "read_object reads no graft and no replacement" `Quick
        read_object_ignores_grafts_and_replacements;
      Alcotest.test_case "read_object refuses a use after the end" `Quick
        read_object_refuses_a_use_after_the_end;
      Alcotest.test_case "with_objects passes an exception through" `Quick
        with_objects_passes_an_exception_through;
      Alcotest.test_case "with_objects closes every descriptor" `Quick
        with_objects_closes_every_descriptor;
      Alcotest.test_case "with_objects closes its pipes when git does not start"
        `Quick with_objects_closes_its_pipes_when_git_does_not_start;
      Alcotest.test_case "with_objects reads what git writes after a bad answer"
        `Quick with_objects_reads_what_git_writes_after_a_bad_answer;
      Alcotest.test_case "with_objects counts its waits" `Quick
        with_objects_counts_its_waits;
      Alcotest.test_case "with_objects gives the error of its function" `Quick
        with_objects_gives_the_error_of_f;
      Alcotest.test_case "with_objects reports a git that fails" `Quick
        with_objects_reports_a_failed_git;
      Alcotest.test_case "read_object survives a git that ends at once" `Quick
        read_object_survives_a_git_that_ends_at_once;
      Alcotest.test_case "read_object reports an empty answer" `Quick
        (read_object_reports_an_answer_it_cannot_read "");
      Alcotest.test_case "read_object reports a header it cannot read" `Quick
        (read_object_reports_an_answer_it_cannot_read "junk\\n");
      Alcotest.test_case "read_object reports an answer for another object"
        `Quick
        (read_object_reports_an_answer_it_cannot_read (two ^ " blob 1\\nx\\n"));
      Alcotest.test_case "read_object reports another missing name" `Quick
        (read_object_reports_an_answer_it_cannot_read (two ^ " missing\\n"));
      Alcotest.test_case "read_object reports content cut short" `Quick
        (read_object_reports_an_answer_it_cannot_read (one ^ " blob 9\\nx"));
      Alcotest.test_case "read_object reports content with no line feed" `Quick
        (read_object_reports_an_answer_it_cannot_read (one ^ " blob 1\\nxy"));
    ]
