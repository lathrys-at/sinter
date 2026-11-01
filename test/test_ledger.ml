(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

open Sinter_core
module Gen = QCheck2.Gen
module Repo = Git_fixture

let property ?(count = 200) ~name ~print generator check =
  QCheck_alcotest.to_alcotest ~speed_level:`Quick
    (QCheck2.Test.make ~count ~name ~print generator check)

let holds name condition = Alcotest.(check bool) name true condition
let hash n = Sha256.hex (string_of_int n)
let commit_id = String.make 40 'c'

let common ?(kind = "approval") ?(seq = 1) () =
  [
    ("v", Json.Int 1);
    ("seq", Json.Int seq);
    ("kind", Json.String kind);
    ("by", Json.String "a@example.com");
    ("ts", Json.String "2026-10-31T14:05:09Z");
    ("head", Json.String commit_id);
    ("branch", Json.String "main");
    ("tool", Json.String "sinter 0.1.0");
  ]

let printed value =
  match Json.to_string value with
  | Ok text -> text
  | Error _ -> Alcotest.fail "the value does not print"

let with_id fields =
  match Ledger.id_of (Json.Object fields) with
  | Ok id -> ("id", Json.String id) :: fields
  | Error _ -> Alcotest.fail "the value does not print"

let line_of fields = printed (Json.Object (with_id fields))

let approval =
  common ()
  @ [
      ("subject", Json.String "req:a");
      ("rev", Json.Int 2);
      ("xh", Json.String (hash 1));
    ]

let read line = Ledger.read_line Git.Sha1 line

let fault_of = function
  | Error (Ledger.Fault { fault; _ }) -> Some fault
  | Ok _ | Error (Ledger.Too_new _) -> None

let line_fault name expected line () =
  match fault_of (read line) with
  | Some fault when fault = expected -> ()
  | _ -> Alcotest.fail (name ^ ": the line gives another result")

(* Generated entries of every kind *)

let text = Gen.oneof [ Generators.utf_8_string; Generators.ascii_string ]
let hex64 = Gen.map hash Gen.nat

let id_gen =
  Gen.map
    (fun n -> "e-" ^ String.sub (Sha256.hex (string_of_int n)) 0 12)
    Gen.nat

let body =
  Gen.(
    oneof
      [
        map3
          (fun subject (rev, xh) note ->
            ( "approval",
              [
                ("subject", Json.String subject);
                ("rev", Json.Int rev);
                ("xh", Json.String xh);
              ]
              @
              match note with
              | Some n -> [ ("note", Json.String n) ]
              | None -> [] ))
          text
          (pair (int_range 1 99) hex64)
          (option text);
        map2
          (fun subject csh ->
            ( "approval",
              [ ("subject", Json.String subject); ("csh", Json.String csh) ] ))
          text hex64;
        map3
          (fun csh scopes promises ->
            ( "commitment-set",
              [
                ("csh", Json.String csh);
                ( "scopes",
                  Json.Array
                    (List.map
                       (fun (step, glob) ->
                         Json.Object
                           (("glob", Json.String glob)
                           ::
                           (match step with
                           | Some s -> [ ("step", Json.String s) ]
                           | None -> [])))
                       scopes) );
                ( "promises",
                  Json.Array
                    (List.map
                       (fun (step, word, target) ->
                         Json.Object
                           [
                             ("step", Json.String step);
                             ("target", Json.String target);
                             ("word", Json.String word);
                           ])
                       promises) );
              ] ))
          hex64
          (list_small (pair (option text) text))
          (list_small (triple text text text));
        map2
          (fun dropped reason ->
            ( "void",
              [
                ("dropped", Json.String dropped); ("reason", Json.String reason);
              ] ))
          id_gen text;
        map3
          (fun subject hash reason ->
            ( "decline",
              [
                ("subject", Json.String subject);
                ("hash", Json.String hash);
                ("reason", Json.String reason);
              ] ))
          text hex64 text;
        map2
          (fun subject csh ->
            ( "delivered",
              [
                ("subject", Json.String subject);
                ("csh", Json.String csh);
                ("merge", Json.String commit_id);
              ] ))
          text hex64;
        map3
          (fun subject approval report ->
            ( "completed",
              [
                ("subject", Json.String subject);
                ("merge", Json.String commit_id);
                ("report", Json.String report);
              ]
              @
              match approval with
              | Some a -> [ ("approval", Json.String a) ]
              | None -> [] ))
          text (option id_gen) hex64;
        map2
          (fun subject reason ->
            ( "abandoned",
              [
                ("subject", Json.String subject); ("reason", Json.String reason);
              ] ))
          text text;
      ])

let entry_fields =
  Gen.map3
    (fun (kind, fields) branch seq ->
      List.filter
        (fun (key, _) -> branch || not (String.equal key "branch"))
        (common ~kind ~seq () @ fields))
    body Gen.bool
    (Gen.oneof [ Gen.int_range 1 1000; Gen.int_range 1 ((1 lsl 53) - 1) ])

let accepted_line line =
  match read line with
  | Ok (Ledger.Known _ | Ledger.Unknown _) -> true
  | Error _ -> false

let entries_read_back =
  property ~name:"an entry printed and read back gives its fields"
    ~print:(fun fields -> line_of fields)
    entry_fields
    (fun fields ->
      let line = line_of fields in
      match read line with
      | Ok (Ledger.Known { entry; unknown_fields }) -> (
          let field name =
            match List.assoc_opt name fields with
            | Some (Json.String s) -> Some s
            | _ -> None
          in
          unknown_fields = 0
          && String.equal entry.line line
          && Some (Json.Int entry.seq) = List.assoc_opt "seq" fields
          && Some entry.by = field "by"
          && Some entry.ts = field "ts"
          && Some entry.head = field "head"
          && entry.branch = field "branch"
          && Some entry.tool = field "tool"
          && Some (Ledger.kind_name entry.body) = field "kind"
          && Ledger.subject entry.body = field "subject"
          && Some entry.id
             =
             match Ledger.id_of (Json.Object fields) with
             | Ok id -> Some id
             | Error _ -> None)
      | Ok (Ledger.Unknown _) | Error _ -> false)

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
            String.mapi (fun i c -> if i = at then byte else c) text)
          (pair nat char);
        map
          (fun (at, extra) ->
            let at = at mod (String.length text + 1) in
            String.sub text 0 at ^ extra
            ^ String.sub text at (String.length text - at))
          (pair nat string_small);
      ])

let canonical_after_reading line =
  match Yojson.Safe.from_string line with
  | `Assoc members -> (
      let rec value = function
        | `String s -> Json.String s
        | `Int i -> Json.Int i
        | `Bool b -> Json.Bool b
        | `List items -> Json.Array (List.map value items)
        | `Assoc members ->
            Json.Object (List.map (fun (k, v) -> (k, value v)) members)
        | _ -> Json.Null
      in
      let value = Json.Object (List.map (fun (k, v) -> (k, value v)) members) in
      Json.to_string value = Ok line
      &&
      match List.assoc_opt "id" members with
      | Some (`String id) -> (
          match value with
          | Json.Object members ->
              Ledger.id_of (Json.Object (List.remove_assoc "id" members))
              = Ok id
          | _ -> false)
      | _ -> false)
  | _ -> false
  | exception Yojson.Json_error _ -> false

let accepted_lines_are_canonical =
  property ~count:500 ~name:"every line that read_line accepts is canonical"
    ~print:QCheck2.Print.string
    Gen.(bind entry_fields (fun fields -> damaged (line_of fields)))
    (fun line -> (not (accepted_line line)) || canonical_after_reading line)

let read_line_is_total =
  property ~count:500 ~name:"read_line gives a value or an error for any bytes"
    ~print:QCheck2.Print.string
    Gen.(oneof [ string; bind entry_fields (fun f -> damaged (line_of f)) ])
    (fun line -> match read line with Ok _ | Error _ -> true)

let a_line = line_of approval

let replace_once text ~sub ~by =
  let length = String.length sub in
  let rec find at =
    if at + length > String.length text then
      Alcotest.fail ("no " ^ sub ^ " in " ^ text)
    else if String.sub text at length = sub then at
    else find (at + 1)
  in
  let at = find 0 in
  String.sub text 0 at ^ by
  ^ String.sub text (at + length) (String.length text - at - length)

let unknown_kind_at seq =
  line_of
    (List.remove_assoc "kind" (common ~seq ())
    @ [ ("kind", Json.String "pin"); ("anything", Json.Array [ Json.Int 1 ]) ])

let unknown_kind_line = unknown_kind_at 1
let approval_at seq = ("seq", Json.Int seq) :: List.remove_assoc "seq" approval

let line_examples =
  let case name expected line =
    Alcotest.test_case name `Quick (line_fault name expected line)
  in
  [
    case "an empty line is no JSON" Ledger.Not_json "";
    case "text is no JSON" Ledger.Not_json "approval";
    case "a line with junk after the object is no JSON" Ledger.Not_json
      (a_line ^ "x");
    case "an array is no object" Ledger.Not_an_object "[1]";
    case "a string is no object" Ledger.Not_an_object "\"a\"";
    case "a null is refused" (Ledger.Bad_value "note")
      (replace_once a_line ~sub:"\"rev\":2" ~by:"\"note\":null,\"rev\":2");
    case "a float is refused" (Ledger.Bad_value "rev")
      (replace_once a_line ~sub:"\"rev\":2" ~by:"\"rev\":2.0");
    case "an integer beyond 2^53 is refused" (Ledger.Bad_value "rev")
      (replace_once a_line ~sub:"\"rev\":2" ~by:"\"rev\":9007199254740992");
    case "a big integer literal is refused" (Ledger.Bad_value "rev")
      (replace_once a_line ~sub:"\"rev\":2"
         ~by:"\"rev\":99999999999999999999999");
    case "a nested object is refused" (Ledger.Bad_value "note")
      (replace_once a_line ~sub:"\"rev\":2" ~by:"\"note\":{\"a\":1},\"rev\":2");
    case "an array of arrays is refused" (Ledger.Bad_value "note")
      (replace_once a_line ~sub:"\"rev\":2" ~by:"\"note\":[[1]],\"rev\":2");
    case "a mixed array is refused" (Ledger.Bad_value "note")
      (replace_once a_line ~sub:"\"rev\":2" ~by:"\"note\":[1,\"a\"],\"rev\":2");
    case "an object in an array that is not flat is refused"
      (Ledger.Bad_value "note")
      (replace_once a_line ~sub:"\"rev\":2"
         ~by:"\"note\":[{\"a\":[1]}],\"rev\":2");
    case "an array of an object and a scalar is refused"
      (Ledger.Bad_value "note")
      (replace_once a_line ~sub:"\"rev\":2"
         ~by:"\"note\":[{\"a\":1},1],\"rev\":2");
    case "a repeated key is refused" (Ledger.Repeated_key "rev")
      (replace_once a_line ~sub:"\"rev\":2" ~by:"\"rev\":2,\"rev\":2");
    case "a repeated key in a flat object is refused" (Ledger.Repeated_key "a")
      (replace_once a_line ~sub:"\"rev\":2"
         ~by:"\"note\":[{\"a\":1,\"a\":1}],\"rev\":2");
    case "a string that is not UTF-8 is refused" Ledger.Not_utf_8
      (replace_once a_line ~sub:"req:a" ~by:"req:\xff");
    case "a space is not canonical" Ledger.Not_canonical
      (replace_once a_line ~sub:"\"rev\":2" ~by:"\"rev\": 2");
    case "an escape of a plain character is not canonical" Ledger.Not_canonical
      (replace_once a_line ~sub:"req:a" ~by:"req:\\u0061");
    case "minus zero is not canonical" Ledger.Not_canonical
      (replace_once a_line ~sub:"\"rev\":2" ~by:"\"rev\":-0,\"x\":2");
    case "a carriage return at the end is not canonical" Ledger.Not_canonical
      (a_line ^ "\r");
    case "a line with no id" (Ledger.Missing_field "id")
      (printed (Json.Object approval));
    case "an id that is not a string" (Ledger.Wrong_type "id")
      (printed (Json.Object (("id", Json.Int 1) :: approval)));
    case "a line with no kind" (Ledger.Missing_field "kind")
      (line_of (List.remove_assoc "kind" approval));
    case "a kind that is not a string" (Ledger.Wrong_type "kind")
      (line_of (("kind", Json.Int 1) :: List.remove_assoc "kind" approval));
    case "a line with no v" (Ledger.Missing_field "v")
      (line_of (List.remove_assoc "v" approval));
    case "a v of 0" (Ledger.Wrong_type "v")
      (line_of (("v", Json.Int 0) :: List.remove_assoc "v" approval));
    case "a v that is a string" (Ledger.Wrong_type "v")
      (line_of (("v", Json.String "1") :: List.remove_assoc "v" approval));
    case "a missing by" (Ledger.Missing_field "by")
      (line_of (List.remove_assoc "by" approval));
    case "a missing tool" (Ledger.Missing_field "tool")
      (line_of (List.remove_assoc "tool" approval));
    case "a head of the length of SHA-256" (Ledger.Wrong_type "head")
      (line_of
         (("head", Json.String (String.make 64 'c'))
         :: List.remove_assoc "head" approval));
    case "a head in upper case" (Ledger.Wrong_type "head")
      (line_of
         (("head", Json.String (String.make 40 'C'))
         :: List.remove_assoc "head" approval));
    case "a branch that is not a string" (Ledger.Wrong_type "branch")
      (line_of (("branch", Json.Int 1) :: List.remove_assoc "branch" approval));
    case "an approval with no subject" (Ledger.Missing_field "subject")
      (line_of (List.remove_assoc "subject" approval));
    case "an approval with rev and csh" Ledger.Approval_hashes
      (line_of (("csh", Json.String (hash 2)) :: approval));
    case "an approval with rev and no xh" Ledger.Approval_hashes
      (line_of (List.remove_assoc "xh" approval));
    case "an approval with neither rev nor csh" Ledger.Approval_hashes
      (line_of (List.remove_assoc "rev" (List.remove_assoc "xh" approval)));
    case "an approval with an xh in upper case" (Ledger.Wrong_type "xh")
      (line_of
         (("xh", Json.String (String.uppercase_ascii (hash 1)))
         :: List.remove_assoc "xh" approval));
    case "an approval with a rev of 0" (Ledger.Wrong_type "rev")
      (line_of (("rev", Json.Int 0) :: List.remove_assoc "rev" approval));
    case "a line with no seq" (Ledger.Missing_field "seq")
      (line_of (List.remove_assoc "seq" approval));
    case "a seq of 0" (Ledger.Wrong_type "seq")
      (line_of (("seq", Json.Int 0) :: List.remove_assoc "seq" approval));
    case "a negative seq" (Ledger.Wrong_type "seq")
      (line_of (("seq", Json.Int (-1)) :: List.remove_assoc "seq" approval));
    case "a seq that is a string" (Ledger.Wrong_type "seq")
      (line_of (("seq", Json.String "1") :: List.remove_assoc "seq" approval));
    case "a seq of 2^53 is refused" (Ledger.Bad_value "seq")
      (replace_once a_line ~sub:"\"seq\":1" ~by:"\"seq\":9007199254740992");
    case "a line of an unknown kind with no seq" (Ledger.Missing_field "seq")
      (line_of (List.remove_assoc "seq" (common ~kind:"pin" ())));
    case "a commitment set with no csh" (Ledger.Missing_field "csh")
      (line_of
         (common ~kind:"commitment-set" ()
         @ [ ("scopes", Json.Array []); ("promises", Json.Array []) ]));
    case "a commitment set with no scopes" (Ledger.Missing_field "scopes")
      (line_of
         (common ~kind:"commitment-set" ()
         @ [ ("csh", Json.String (hash 1)); ("promises", Json.Array []) ]));
    case "a commitment set whose scopes is a string"
      (Ledger.Wrong_type "scopes")
      (line_of
         (common ~kind:"commitment-set" ()
         @ [
             ("csh", Json.String (hash 1));
             ("scopes", Json.String "a/**");
             ("promises", Json.Array []);
           ]));
    case "a commitment set whose scopes are strings"
      (Ledger.Wrong_type "scopes")
      (line_of
         (common ~kind:"commitment-set" ()
         @ [
             ("csh", Json.String (hash 1));
             ("scopes", Json.Array [ Json.String "a/**" ]);
             ("promises", Json.Array []);
           ]));
    case "a scope with no glob" (Ledger.Wrong_type "scopes")
      (line_of
         (common ~kind:"commitment-set" ()
         @ [
             ("csh", Json.String (hash 1));
             ("scopes", Json.Array [ Json.Object [ ("step", Json.String "s") ] ]);
             ("promises", Json.Array []);
           ]));
    case "a scope whose glob is no string" (Ledger.Wrong_type "scopes")
      (line_of
         (common ~kind:"commitment-set" ()
         @ [
             ("csh", Json.String (hash 1));
             ("scopes", Json.Array [ Json.Object [ ("glob", Json.Int 1) ] ]);
             ("promises", Json.Array []);
           ]));
    case "a scope whose step is no string" (Ledger.Wrong_type "scopes")
      (line_of
         (common ~kind:"commitment-set" ()
         @ [
             ("csh", Json.String (hash 1));
             ( "scopes",
               Json.Array
                 [
                   Json.Object
                     [ ("glob", Json.String "a/**"); ("step", Json.Bool true) ];
                 ] );
             ("promises", Json.Array []);
           ]));
    case "a promise with no step" (Ledger.Wrong_type "promises")
      (line_of
         (common ~kind:"commitment-set" ()
         @ [
             ("csh", Json.String (hash 1));
             ("scopes", Json.Array []);
             ( "promises",
               Json.Array
                 [
                   Json.Object
                     [
                       ("target", Json.String "a"); ("word", Json.String "req");
                     ];
                 ] );
           ]));
    case "a promise with no word" (Ledger.Wrong_type "promises")
      (line_of
         (common ~kind:"commitment-set" ()
         @ [
             ("csh", Json.String (hash 1));
             ("scopes", Json.Array []);
             ( "promises",
               Json.Array
                 [
                   Json.Object
                     [ ("step", Json.String "s"); ("target", Json.String "a") ];
                 ] );
           ]));
    case "a promise with no target" (Ledger.Wrong_type "promises")
      (line_of
         (common ~kind:"commitment-set" ()
         @ [
             ("csh", Json.String (hash 1));
             ("scopes", Json.Array []);
             ( "promises",
               Json.Array
                 [
                   Json.Object
                     [ ("step", Json.String "s"); ("word", Json.String "req") ];
                 ] );
           ]));
    case "a second scope with no glob" (Ledger.Wrong_type "scopes")
      (line_of
         (common ~kind:"commitment-set" ()
         @ [
             ("csh", Json.String (hash 1));
             ( "scopes",
               Json.Array
                 [
                   Json.Object [ ("glob", Json.String "a/**") ];
                   Json.Object [ ("step", Json.String "s") ];
                 ] );
             ("promises", Json.Array []);
           ]));
    case "a void whose dropped is no entry id" (Ledger.Wrong_type "dropped")
      (line_of
         (common ~kind:"void" ()
         @ [ ("dropped", Json.String "e-123"); ("reason", Json.String "r") ]));
    case "a void whose dropped ends with a letter beyond f"
      (Ledger.Wrong_type "dropped")
      (line_of
         (common ~kind:"void" ()
         @ [
             ("dropped", Json.String "e-aaaaaaaaaaaz");
             ("reason", Json.String "r");
           ]));
    case "a void with no reason" (Ledger.Missing_field "reason")
      (line_of
         (common ~kind:"void" ()
         @ [ ("dropped", Json.String ("e-" ^ String.make 12 'a')) ]));
    case "a decline with no reason" (Ledger.Missing_field "reason")
      (line_of
         (common ~kind:"decline" ()
         @ [ ("subject", Json.String "req:a"); ("hash", Json.String (hash 1)) ]
         ));
    case "a delivery whose merge is short" (Ledger.Wrong_type "merge")
      (line_of
         (common ~kind:"delivered" ()
         @ [
             ("subject", Json.String "step:p/s");
             ("csh", Json.String (hash 1));
             ("merge", Json.String "abc");
           ]));
    case "a completion with no report" (Ledger.Missing_field "report")
      (line_of
         (common ~kind:"completed" ()
         @ [
             ("subject", Json.String "plan:p@1");
             ("merge", Json.String commit_id);
           ]));
    case "an abandoned entry with no reason" (Ledger.Missing_field "reason")
      (line_of
         (common ~kind:"abandoned" () @ [ ("subject", Json.String "plan:p@1") ]));
  ]

let wrong_id_names_the_id () =
  let fields = with_id approval in
  let other =
    ("id", Json.String ("e-" ^ String.make 12 '0'))
    :: List.remove_assoc "id" fields
  in
  let own = match List.assoc "id" fields with Json.String s -> s | _ -> "" in
  match read (printed (Json.Object other)) with
  | Error (Ledger.Fault { id; fault = Ledger.Wrong_id found }) ->
      Alcotest.(check string) "the own id" own found;
      Alcotest.(check (option string))
        "the id of the line"
        (Some ("e-" ^ String.make 12 '0'))
        id
  | _ -> Alcotest.fail "the line gives another result"

let an_id_that_occurs_twice_still_hashes () =
  let fields = with_id approval in
  let id = match List.assoc "id" fields with Json.String s -> s | _ -> "" in
  let line =
    line_of
      (approval
      @ [ ("aaa", Json.Array [ Json.Object [ ("id", Json.String id) ] ]) ])
  in
  holds "the line is read" (accepted_line line)

let keys_out_of_order_are_not_canonical () =
  let line = line_of approval in
  let swapped =
    replace_once line ~sub:"\"by\":\"a@example.com\"," ~by:"" |> fun rest ->
    replace_once rest ~sub:"\"xh\"" ~by:"\"by\":\"a@example.com\",\"xh\""
  in
  match fault_of (read swapped) with
  | Some Ledger.Not_canonical -> ()
  | _ -> Alcotest.fail "the line gives another result"

let a_higher_version_comes_first () =
  let line =
    replace_once
      (line_of (("v", Json.Int 2) :: List.remove_assoc "v" approval))
      ~sub:"\"rev\":2" ~by:"\"rev\": 2"
  in
  match read line with
  | Error (Ledger.Too_new 2) -> ()
  | _ -> Alcotest.fail "the line gives another result"

let an_empty_array_is_a_value () =
  holds "read"
    (match read (line_of (approval @ [ ("later", Json.Array []) ])) with
    | Ok (Ledger.Known { unknown_fields = 1; _ }) -> true
    | _ -> false)

let two_versions_are_a_repeated_key () =
  match read (replace_once a_line ~sub:"\"v\":1" ~by:"\"v\":1,\"v\":2") with
  | Error (Ledger.Fault { fault = Ledger.Repeated_key "v"; _ }) -> ()
  | _ -> Alcotest.fail "the line gives another result"

let an_unknown_kind_counts_for_nothing () =
  match read unknown_kind_line with
  | Ok (Ledger.Unknown { kind; _ }) ->
      Alcotest.(check string) "the kind" "pin" kind
  | _ -> Alcotest.fail "the line gives another result"

let an_unknown_kind_needs_its_id () =
  match
    fault_of
      (read
         (replace_once unknown_kind_line ~sub:"\"anything\":[1]"
            ~by:"\"anything\":[2]"))
  with
  | Some (Ledger.Wrong_id _) -> ()
  | _ -> Alcotest.fail "the line gives another result"

let an_unknown_field_is_counted () =
  match
    read
      (line_of (approval @ [ ("later", Json.Bool true); ("zz", Json.Int 3) ]))
  with
  | Ok (Ledger.Known { unknown_fields; _ }) ->
      Alcotest.(check int) "the count" 2 unknown_fields
  | _ -> Alcotest.fail "the line gives another result"

let ts_case name ts accepted =
  Alcotest.test_case name `Quick (fun () ->
      let line =
        line_of (("ts", Json.String ts) :: List.remove_assoc "ts" approval)
      in
      match (read line, accepted) with
      | Ok (Ledger.Known _), true -> ()
      | Error (Ledger.Fault { fault = Ledger.Wrong_type "ts"; _ }), false -> ()
      | _ -> Alcotest.fail (ts ^ " gives another result"))

let month_ends =
  List.concat_map
    (fun (year, month, last) ->
      [
        ts_case
          (Printf.sprintf "a ts on the last day of %04d-%02d" year month)
          (Printf.sprintf "%04d-%02d-%02dT12:00:00Z" year month last)
          true;
        ts_case
          (Printf.sprintf "a ts after the last day of %04d-%02d" year month)
          (Printf.sprintf "%04d-%02d-%02dT12:00:00Z" year month (last + 1))
          false;
      ])
    [
      (2026, 1, 31);
      (2026, 2, 28);
      (2026, 3, 31);
      (2026, 4, 30);
      (2026, 5, 31);
      (2026, 6, 30);
      (2026, 7, 31);
      (2026, 8, 31);
      (2026, 9, 30);
      (2026, 10, 31);
      (2026, 11, 30);
      (2026, 12, 31);
      (2024, 2, 29);
      (2000, 2, 29);
      (1900, 2, 28);
      (2100, 2, 28);
    ]

let ts_examples =
  month_ends
  @ [
      ts_case "a ts on the 29th of February of a leap year"
        "2024-02-29T00:00:00Z" true;
      ts_case "a ts on the 29th of February of 2000" "2000-02-29T00:00:00Z" true;
      ts_case "a ts at the end of a day" "2026-12-31T23:59:59Z" true;
      ts_case "a ts on the 29th of February of 2026" "2026-02-29T00:00:00Z"
        false;
      ts_case "a ts on the 29th of February of 1900" "1900-02-29T00:00:00Z"
        false;
      ts_case "a ts on the 30th of February" "2026-02-30T00:00:00Z" false;
      ts_case "a ts on the 31st of April" "2026-04-31T00:00:00Z" false;
      ts_case "a ts of month 13" "2026-13-01T00:00:00Z" false;
      ts_case "a ts of month 0" "2026-00-01T00:00:00Z" false;
      ts_case "a ts of day 0" "2026-01-00T00:00:00Z" false;
      ts_case "a ts of hour 24" "2026-01-01T24:00:00Z" false;
      ts_case "a ts of minute 60" "2026-01-01T00:60:00Z" false;
      ts_case "a ts of second 60" "2026-01-01T00:00:60Z" false;
      ts_case "a ts with a fraction" "2026-01-01T00:00:00.5Z" false;
      ts_case "a ts with a lower-case t" "2026-01-01t00:00:00Z" false;
      ts_case "a ts with a lower-case z" "2026-01-01T00:00:00z" false;
      ts_case "a ts with an offset" "2026-01-01T00:00:00+00" false;
      ts_case "a ts with a letter for a digit" "2026-01-0aT00:00:00Z" false;
      ts_case "a ts with a slash" "2026/01/01T00:00:00Z" false;
      ts_case "a ts with a space" "2026-01-01 00:00:00Z" false;
      ts_case "a ts with a dot" "2026-01-01T00.00:00Z" false;
      ts_case "a ts with a colon for a digit" "2026-01-0:T00:00:00Z" false;
    ]

let a_sha256_head_reads_in_a_sha256_repository () =
  let line =
    line_of
      (("head", Json.String (String.make 64 'c'))
      :: List.remove_assoc "head" approval)
  in
  holds "read"
    (match Ledger.read_line Git.Sha256 line with
    | Ok (Ledger.Known _) -> true
    | _ -> false)

let entries_sort_by_seq_whatever_their_ts () =
  let entry ts seq =
    match
      read
        (line_of
           (("ts", Json.String ts) :: ("seq", Json.Int seq)
           :: List.remove_assoc "seq" (List.remove_assoc "ts" approval)))
    with
    | Ok (Ledger.Known { entry; _ }) -> entry
    | _ -> Alcotest.fail "the line does not read"
  in
  let a = entry "2099-01-01T00:00:00Z" 1
  and b = entry "2026-01-01T00:00:00Z" 2
  and c = entry "2025-12-31T23:59:59Z" 3 in
  Alcotest.(check (list int))
    "the seqs" [ 1; 2; 3 ]
    (List.map
       (fun (e : Ledger.entry) -> e.seq)
       (List.sort Ledger.compare [ c; a; b ]))

let the_largest_seq_reads () =
  match
    read
      (line_of
         (("seq", Json.Int ((1 lsl 53) - 1)) :: List.remove_assoc "seq" approval))
  with
  | Ok (Ledger.Known { entry; _ }) ->
      Alcotest.(check int) "the seq" ((1 lsl 53) - 1) entry.seq
  | _ -> Alcotest.fail "the line does not read"

let an_unknown_kind_gives_its_seq () =
  match read (line_of (common ~kind:"pin" ~seq:7 ())) with
  | Ok (Ledger.Unknown { seq; _ }) -> Alcotest.(check int) "the seq" 7 seq
  | _ -> Alcotest.fail "the line gives another result"

let set_fields ~csh scopes promises =
  common ~kind:"commitment-set" ()
  @ [
      ("csh", Json.String csh);
      ( "scopes",
        Json.Array
          (List.map
             (fun (step, glob) ->
               Json.Object
                 (("glob", Json.String glob)
                 ::
                 (match step with
                 | Some s -> [ ("step", Json.String s) ]
                 | None -> [])))
             scopes) );
      ( "promises",
        Json.Array
          (List.map
             (fun (step, word, target) ->
               Json.Object
                 [
                   ("step", Json.String step);
                   ("target", Json.String target);
                   ("word", Json.String word);
                 ])
             promises) );
    ]

let lockout_bytes =
  {|{"promises":[{"scope":["src/**"],"target":"lockout-policy","word":"decision"},{"scope":["src/auth/**"],"target":"auth-lockout","word":"req"},{"scope":["src/auth/**"],"target":"auth-lockout","word":"verifies"}],"scope":["src/**"]}|}

let lockout_scopes =
  [ (None, "src/**"); (Some "lock-the-account", "src/auth/**") ]

let lockout_promises =
  [
    ("lock-the-account", "req", "auth-lockout");
    ("lock-the-account", "verifies", "auth-lockout");
    ("record-the-policy", "decision", "lockout-policy");
  ]

let csh_holds fields =
  match read (line_of fields) with
  | Ok
      (Ledger.Known
         { entry = { body = Ledger.Commitment_set { csh_holds; _ }; _ }; _ }) ->
      csh_holds
  | _ -> Alcotest.fail "the line does not read as a commitment set"

let a_set_whose_csh_holds () =
  holds "the hash holds"
    (csh_holds
       (set_fields ~csh:(Sha256.hex lockout_bytes) lockout_scopes
          lockout_promises))

let a_set_whose_csh_is_wrong_still_reads () =
  holds "the hash does not hold"
    (not (csh_holds (set_fields ~csh:(hash 1) lockout_scopes lockout_promises)))

let a_set_reads_in_its_order () =
  match
    read
      (line_of
         (set_fields ~csh:(hash 1) lockout_scopes (List.rev lockout_promises)))
  with
  | Ok
      (Ledger.Known
         {
           entry = { body = Ledger.Commitment_set { scopes; promises; _ }; _ };
           _;
         }) ->
      Alcotest.(check (list (pair (option string) string)))
        "the scopes" lockout_scopes
        (List.map
           (fun (scope : Ledger.scope) -> (scope.step, scope.glob))
           scopes);
      Alcotest.(check (list (triple string string string)))
        "the promises"
        (List.rev lockout_promises)
        (List.map
           (fun (promise : Ledger.promise) ->
             (promise.step, promise.word, promise.target))
           promises)
  | _ -> Alcotest.fail "the line does not read as a commitment set"

let a_step_without_scopes_takes_the_plan_scope () =
  holds "the hash holds"
    (csh_holds
       (set_fields
          ~csh:
            (Sha256.hex
               {|{"promises":[{"scope":["src/**"],"target":"a","word":"req"}],"scope":["src/**"]}|})
          [ (None, "src/**"); (Some "other", "lib/**") ]
          [ ("s", "req", "a") ]))

let a_step_with_scopes_does_not_take_the_plan_scope () =
  holds "the hash holds"
    (csh_holds
       (set_fields
          ~csh:
            (Sha256.hex
               {|{"promises":[{"scope":["lib/**","src/a/**"],"target":"a","word":"req"}],"scope":["src/**"]}|})
          [
            (Some "s", "src/a/**");
            (None, "src/**");
            (Some "s", "lib/**");
            (Some "s", "lib/**");
          ]
          [ ("s", "req", "a") ]))

let near_the_limit extra =
  let globs = List.init 400 (Printf.sprintf "dir/%04d/**") in
  let promises pad =
    List.init 180 (fun n ->
        ( "s",
          "req",
          Printf.sprintf "t%d" n ^ if n = 0 then String.make pad 'x' else "" ))
  in
  let steps pad =
    [
      {
        Commitment_set.scope = globs;
        promises =
          List.map (fun (_, word, target) -> (word, target)) (promises pad);
      };
    ]
  in
  let pad =
    Ledger.set_limit - Commitment_set.size ~scope:globs (steps 0) + extra
  in
  let csh = Commitment_set.hash ~scope:globs (steps pad) in
  ( Commitment_set.size ~scope:globs (steps pad),
    line_of
      (set_fields ~csh
         (List.map (fun glob -> (None, glob)) globs)
         (promises pad)) )

let a_set_at_the_limit_holds () =
  let size, line = near_the_limit 0 in
  Alcotest.(check int) "the size" Ledger.set_limit size;
  holds "the hash holds"
    (match read line with
    | Ok
        (Ledger.Known
           { entry = { body = Ledger.Commitment_set { csh_holds; _ }; _ }; _ })
      ->
        csh_holds
    | _ -> false)

let a_set_past_the_limit_does_not_hold_and_costs_no_hash () =
  let size, over = near_the_limit 1 in
  let _, under = near_the_limit 0 in
  Alcotest.(check int) "the size" (Ledger.set_limit + 1) size;
  holds "the hash does not hold"
    (match read over with
    | Ok
        (Ledger.Known
           { entry = { body = Ledger.Commitment_set { csh_holds; _ }; _ }; _ })
      ->
        not csh_holds
    | _ -> false);
  let words_over = Counted_work.words (fun () -> read over)
  and words_under = Counted_work.words (fun () -> read under) in
  holds
    (Printf.sprintf
       "a read past the limit allocates %d words, less than a quarter of the \
        %d words of a read at the limit"
       words_over words_under)
    (4 * words_over < words_under)

let many_steps_share_one_plan_scope () =
  let set count =
    let globs = List.init count (Printf.sprintf "dir/%05d/**") in
    line_of
      (set_fields ~csh:(hash 1)
         (List.map (fun glob -> (None, glob)) globs)
         (List.init count (fun n ->
              (Printf.sprintf "s%d" n, "req", Printf.sprintf "t%d" n))))
  in
  Counted_work.check_growth ~margin:3. ~sizes:(200, 3_200) ~input:set read

let an_unknown_key_of_a_set_is_an_unknown_field () =
  let fields = set_fields ~csh:(hash 1) [] [] in
  let fields =
    List.map
      (function
        | "scopes", _ ->
            ( "scopes",
              Json.Array
                [
                  Json.Object
                    [ ("glob", Json.String "a"); ("narrow", Json.Bool true) ];
                ] )
        | "promises", _ ->
            ( "promises",
              Json.Array
                [
                  Json.Object
                    [
                      ("step", Json.String "s");
                      ("target", Json.String "t");
                      ("word", Json.String "req");
                      ("x", Json.Int 1);
                      ("y", Json.Int 1);
                    ];
                ] )
        | field -> field)
      fields
  in
  match read (line_of (fields @ [ ("z", Json.Int 1) ])) with
  | Ok (Ledger.Known { unknown_fields; _ }) ->
      Alcotest.(check int) "the count" 4 unknown_fields
  | _ -> Alcotest.fail "the line gives another result"

let an_unknown_key_of_another_kind_is_not_looked_into () =
  match
    read
      (line_of
         (approval
         @ [ ("scopes", Json.Array [ Json.Object [ ("x", Json.Int 1) ] ]) ]))
  with
  | Ok (Ledger.Known { unknown_fields; _ }) ->
      Alcotest.(check int) "the count" 1 unknown_fields
  | _ -> Alcotest.fail "the line gives another result"

let id_of_refuses_a_value_that_is_no_object () =
  Alcotest.check_raises "not an object"
    (Invalid_argument "Sinter_core.Ledger.id_of: the value is not an object")
    (fun () -> ignore (Ledger.id_of (Json.Int 1)))

let id_of_gives_the_error_of_the_printer () =
  holds "an error"
    (Result.is_error (Ledger.id_of (Json.Object [ ("a", Json.String "\xff") ])))

let kind_names () =
  let names =
    List.map
      (fun fields ->
        match read (line_of fields) with
        | Ok (Ledger.Known { entry; _ }) ->
            (Ledger.kind_name entry.body, Ledger.subject entry.body)
        | _ -> Alcotest.fail "the line does not read")
      [
        approval;
        set_fields ~csh:(hash 1) [] [];
        common ~kind:"decline" ()
        @ [
            ("subject", Json.String "req:b");
            ("hash", Json.String (hash 1));
            ("reason", Json.String "r");
          ];
        common ~kind:"delivered" ()
        @ [
            ("subject", Json.String "step:p@1/s");
            ("csh", Json.String (hash 1));
            ("merge", Json.String commit_id);
          ];
        common ~kind:"completed" ()
        @ [
            ("subject", Json.String "plan:p@1");
            ("merge", Json.String commit_id);
            ("report", Json.String (hash 1));
          ];
        common ~kind:"void" ()
        @ [
            ("dropped", Json.String ("e-" ^ String.make 12 'a'));
            ("reason", Json.String "r");
          ];
        common ~kind:"abandoned" ()
        @ [ ("subject", Json.String "plan:p@1"); ("reason", Json.String "r") ];
      ]
  in
  Alcotest.(check (list (pair string (option string))))
    "the names"
    [
      ("approval", Some "req:a");
      ("commitment-set", None);
      ("decline", Some "req:b");
      ("delivered", Some "step:p@1/s");
      ("completed", Some "plan:p@1");
      ("void", None);
      ("abandoned", Some "plan:p@1");
    ]
    names

let constants () =
  Alcotest.(check string) "the ref" "refs/sinter/ledger" Ledger.ref_name;
  Alcotest.(check int) "the version" 1 Ledger.version;
  Alcotest.(check int) "the size of a chunk" 50 Ledger.chunk_size;
  Alcotest.(check int) "the limit of a set" 1_048_576 Ledger.set_limit

let line_tests =
  [
    entries_read_back;
    accepted_lines_are_canonical;
    read_line_is_total;
    Alcotest.test_case "constants" `Quick constants;
    Alcotest.test_case "a wrong id names the own id" `Quick
      wrong_id_names_the_id;
    Alcotest.test_case "an id in a flat object does not confuse the hash" `Quick
      an_id_that_occurs_twice_still_hashes;
    Alcotest.test_case "keys out of order are not canonical" `Quick
      keys_out_of_order_are_not_canonical;
    Alcotest.test_case "a higher version comes before other faults" `Quick
      a_higher_version_comes_first;
    Alcotest.test_case "an empty array is a value" `Quick
      an_empty_array_is_a_value;
    Alcotest.test_case "two keys v are a repeated key, not a newer version"
      `Quick two_versions_are_a_repeated_key;
    Alcotest.test_case "an unknown kind counts for nothing" `Quick
      an_unknown_kind_counts_for_nothing;
    Alcotest.test_case "an unknown kind needs its own id" `Quick
      an_unknown_kind_needs_its_id;
    Alcotest.test_case "an unknown field is counted" `Quick
      an_unknown_field_is_counted;
    Alcotest.test_case "a SHA-256 head reads in a SHA-256 repository" `Quick
      a_sha256_head_reads_in_a_sha256_repository;
    Alcotest.test_case "entries sort by seq, whatever their ts" `Quick
      entries_sort_by_seq_whatever_their_ts;
    Alcotest.test_case "the largest seq reads" `Quick the_largest_seq_reads;
    Alcotest.test_case "an unknown kind gives its seq" `Quick
      an_unknown_kind_gives_its_seq;
    Alcotest.test_case "a set whose csh holds" `Quick a_set_whose_csh_holds;
    Alcotest.test_case "a set whose csh is wrong still reads" `Quick
      a_set_whose_csh_is_wrong_still_reads;
    Alcotest.test_case "a set reads in the order of its line" `Quick
      a_set_reads_in_its_order;
    Alcotest.test_case "a step without scopes takes the plan scope" `Quick
      a_step_without_scopes_takes_the_plan_scope;
    Alcotest.test_case "a step with scopes does not take the plan scope" `Quick
      a_step_with_scopes_does_not_take_the_plan_scope;
    Alcotest.test_case "a set at the limit holds" `Quick
      a_set_at_the_limit_holds;
    Alcotest.test_case "a set past the limit does not hold and costs no hash"
      `Quick a_set_past_the_limit_does_not_hold_and_costs_no_hash;
    Alcotest.test_case
      "the work of a set grows linearly when many steps share one plan scope"
      `Quick many_steps_share_one_plan_scope;
    Alcotest.test_case "an unknown key of a set is an unknown field" `Quick
      an_unknown_key_of_a_set_is_an_unknown_field;
    Alcotest.test_case "an unknown key of another kind is not looked into"
      `Quick an_unknown_key_of_another_kind_is_not_looked_into;
    Alcotest.test_case "id_of refuses a value that is no object" `Quick
      id_of_refuses_a_value_that_is_no_object;
    Alcotest.test_case "id_of gives the error of the printer" `Quick
      id_of_gives_the_error_of_the_printer;
    Alcotest.test_case "the names of the kinds and their subjects" `Quick
      kind_names;
  ]
  @ line_examples @ ts_examples

(* Ledgers in repositories *)

type file =
  | Chunk of string * string  (** a regular file: the path and the content *)
  | Mode of string * string * string
      (** a file of a mode: the mode, the path, and the content *)
  | Gitlink of string * string  (** a submodule: the path and a commit id *)

let commit_command mark files =
  let data text = Printf.sprintf "data %d\n%s\n" (String.length text) text in
  String.concat ""
    ([
       Printf.sprintf "commit %s\nmark :%d\n" Ledger.ref_name mark;
       "committer C O Mitter <committer@example.com> 1700000000 +0000\n";
       data (Printf.sprintf "write %d" mark);
     ]
    @ (if mark > 1 then [ Printf.sprintf "from :%d\n" (mark - 1) ] else [])
    @ [ "deleteall\n" ]
    @ List.map
        (function
          | Chunk (path, content) ->
              Printf.sprintf "M 100644 inline %s\n%s" path (data content)
          | Mode (mode, path, content) ->
              Printf.sprintf "M %s inline %s\n%s" mode path (data content)
          | Gitlink (path, id) -> Printf.sprintf "M 160000 %s %s\n" id path)
        files)

let build ?repo states =
  let repo = match repo with Some repo -> repo | None -> Repo.init () in
  Repo.import repo
    (List.mapi (fun index files -> commit_command (index + 1) files) states);
  repo

let entry = Sinter_bench.Generated_ledger.entry
let entries first count = List.init count (fun n -> entry (first + n))

let chunked lines =
  List.map
    (fun (path, content) -> Chunk (path, content))
    (Sinter_bench.Generated_ledger.chunks lines)

let opened repo =
  match Git.open_repo ~env:(Repo.env repo) (Repo.root repo) with
  | Ok t -> t
  | Error _ -> Alcotest.fail "the repository does not open"

let commit_of repo back =
  String.trim
    (Repo.git repo [ "rev-parse"; Printf.sprintf "%s~%d" Ledger.ref_name back ])

let fault_name = function
  | Ledger.Not_a_commit _ -> "not a commit"
  | Bad_commit _ -> "bad commit"
  | Merge_commit n -> Printf.sprintf "merge commit %d" n
  | Parent_not_a_commit _ -> "parent not a commit"
  | Bad_tree _ -> "bad tree"
  | Wrong_object _ -> "wrong object"
  | Wrong_path { mode } -> Printf.sprintf "wrong path %o" mode
  | Unordered_tree -> "unordered tree"
  | Empty_folder -> "empty folder"
  | Empty_chunk -> "empty chunk"
  | No_line_feed -> "no line feed"
  | Wrong_name _ -> "wrong name"
  | Bad_line _ -> "bad line"
  | Repeated_id -> "repeated id"
  | Repeated_seq n -> Printf.sprintf "repeated seq %d" n
  | Missing_seq { seq; count } ->
      Printf.sprintf "missing seq %d of %d" seq count
  | Dropped _ -> "dropped"

let describe = function
  | Ok None -> "no ledger"
  | Ok (Some ledger) ->
      Printf.sprintf "ok %d entries %d commits"
        (List.length (Ledger.entries ledger))
        (Ledger.commits ledger)
  | Error (Ledger.Broken { commit; path; line; entry = _; fault }) ->
      Printf.sprintf "broken %s at %s %s %s" (fault_name fault) commit
        (Option.value path ~default:"-")
        (Option.fold ~none:"-" ~some:string_of_int line)
  | Error (Ledger.Newer { commit; path; line; version }) ->
      Printf.sprintf "newer %d at %s %s %d" version commit path line
  | Error (Ledger.Missing_parent { commit; parent }) ->
      Printf.sprintf "missing parent %s of %s" parent commit
  | Error (Ledger.Missing_object { commit; id }) ->
      Printf.sprintf "missing object %s in %s" id commit
  | Error (Ledger.Repository _) -> "git fails"

let reads ?(depth = Ledger.History) repo expected () =
  Alcotest.(check string)
    "the result" (expected repo)
    (describe (Ledger.read (opened repo) depth))

let broken_at ?(back = 0) ?(path = "-") ?(line = "-") fault repo =
  Printf.sprintf "broken %s at %s %s %s" fault (commit_of repo back) path line

let ok entries commits _ =
  Printf.sprintf "ok %d entries %d commits" entries commits

let case name ?depth states expected =
  Alcotest.test_case name `Quick (fun () ->
      reads ?depth (build states) expected ())

let lines_of chunk = String.concat "" (List.map (fun line -> line ^ "\n") chunk)

let chunk_path lines =
  match Sinter_bench.Generated_ledger.chunks lines with
  | (path, _) :: _ -> path
  | [] -> Alcotest.fail "no chunk"

let three = entries 0 3
let path3 = chunk_path three

let tree_cases =
  [
    case "an empty ledger reads" [ [] ] (ok 0 1);
    case "a ledger of three commits reads"
      [ []; chunked (entries 0 1); chunked three ]
      (ok 3 3);
    case "a file at the root is no part of a ledger"
      [ chunked three @ [ Chunk ("README", "x\n") ] ]
      (broken_at ~path:"README" "wrong path 100644");
    case "entries as a file is no part of a ledger"
      [ [ Chunk ("entries", "x\n") ] ]
      (broken_at ~path:"entries" "wrong path 100644");
    case "a folder that is not two hex digits"
      [ [ Chunk ("entries/zz/" ^ Filename.basename path3, lines_of three) ] ]
      (broken_at ~path:"entries/zz" "wrong path 40000");
    case "a folder in upper case"
      [
        [
          Chunk
            ( "entries/"
              ^ String.uppercase_ascii
                  (String.sub (Filename.basename path3) 2 2)
              ^ "/" ^ Filename.basename path3,
              lines_of three );
        ];
      ]
      (fun repo ->
        let folder =
          String.uppercase_ascii (String.sub (Filename.basename path3) 2 2)
        in
        if folder = String.sub (Filename.basename path3) 2 2 then ok 3 1 repo
        else broken_at ~path:("entries/" ^ folder) "wrong path 40000" repo);
    case "a chunk in the wrong folder"
      [ [ Chunk ("entries/00/" ^ Filename.basename path3, lines_of three) ] ]
      (fun repo ->
        if String.sub (Filename.basename path3) 2 2 = "00" then ok 3 1 repo
        else
          broken_at
            ~path:("entries/00/" ^ Filename.basename path3)
            "wrong path 100644" repo);
    case "a chunk that is not named after its first entry"
      [ [ Chunk (path3, lines_of (List.rev three)) ] ]
      (broken_at ~path:path3 "wrong name");
    case "a chunk whose name ends with a letter beyond f"
      [
        [
          Chunk
            ( String.sub path3 0 (String.length path3 - 7) ^ "z.jsonl",
              lines_of three );
        ];
      ]
      (broken_at
         ~path:(String.sub path3 0 (String.length path3 - 7) ^ "z.jsonl")
         "wrong path 100644");
    case "a chunk with another suffix"
      [ [ Chunk (Filename.remove_extension path3 ^ ".json", lines_of three) ] ]
      (broken_at
         ~path:(Filename.remove_extension path3 ^ ".json")
         "wrong path 100644");
    case "a folder inside a folder"
      [ [ Chunk (Filename.dirname path3 ^ "/x/y.jsonl", lines_of three) ] ]
      (broken_at ~path:(Filename.dirname path3 ^ "/x") "wrong path 40000");
    case "an executable chunk"
      [ [ Mode ("100755", path3, lines_of three) ] ]
      (broken_at ~path:path3 "wrong path 100755");
    case "a symbolic link"
      [ [ Mode ("120000", path3, "elsewhere") ] ]
      (broken_at ~path:path3 "wrong path 120000");
    case "a submodule"
      [ [ Gitlink (path3, String.make 40 'a') ] ]
      (broken_at ~path:path3 "wrong path 160000");
    case "an empty chunk"
      [ [ Chunk (path3, "") ] ]
      (broken_at ~path:path3 "empty chunk");
    case "a chunk with no final line feed"
      [
        [
          Chunk
            ( path3,
              String.sub (lines_of three) 0 (String.length (lines_of three) - 1)
            );
        ];
      ]
      (broken_at ~path:path3 "no line feed");
    case "an empty line in a chunk"
      [ [ Chunk (path3, lines_of [ List.hd three; ""; List.nth three 1 ]) ] ]
      (broken_at ~path:path3 ~line:"2" "bad line");
    case "a line that fails its checks"
      [ [ Chunk (path3, lines_of [ List.hd three; List.nth three 1 ^ " " ]) ] ]
      (broken_at ~path:path3 ~line:"2" "bad line");
    case "an id that repeats in a chunk"
      [
        [
          Chunk
            ( path3,
              lines_of [ List.hd three; List.nth three 1; List.nth three 1 ] );
        ];
      ]
      (broken_at ~path:path3 ~line:"3" "repeated id");
    case "an id that repeats in another chunk"
      [ chunked three @ chunked [ List.nth three 1 ] ]
      (fun repo ->
        let other = chunk_path [ List.nth three 1 ] in
        let first, second =
          if path3 < other then (path3, other) else (other, path3)
        in
        let line = if first = path3 then "1" else "2" in
        broken_at ~path:second ~line "repeated id" repo);
    case "a line of a higher version stops the read"
      [
        [
          Chunk
            ( path3,
              lines_of
                [
                  List.hd three;
                  line_of (("v", Json.Int 2) :: List.remove_assoc "v" approval);
                ] );
        ];
      ]
      (fun repo -> Printf.sprintf "newer 2 at %s %s 2" (commit_of repo 0) path3);
  ]

let s seq n = entry ~seq n

let unknown_at seq =
  line_of
    (List.remove_assoc "kind" (common ~seq ()) @ [ ("kind", Json.String "pin") ])

let seq_tip_cases =
  [
    case "a seq that repeats in a chunk" ~depth:Ledger.Tip
      [ chunked [ s 1 0; s 2 1; s 1 2 ] ]
      (broken_at ~path:(chunk_path [ s 1 0 ]) ~line:"3" "repeated seq 1");
    case "a seq that repeats in another chunk" ~depth:Ledger.Tip
      [ chunked [ s 1 0; s 2 1 ] @ chunked [ s 2 2 ] ]
      (fun repo ->
        let one = chunk_path [ s 1 0 ] and other = chunk_path [ s 2 2 ] in
        if one < other then
          broken_at ~path:other ~line:"1" "repeated seq 2" repo
        else broken_at ~path:one ~line:"2" "repeated seq 2" repo);
    case "a gap in the seqs of the tip" ~depth:Ledger.Tip
      [ chunked [ s 1 0; s 3 1; s 4 2 ] ]
      (broken_at "missing seq 2 of 3");
    case "a gap at the last seq of the tip" ~depth:Ledger.Tip
      [ chunked [ s 1 0; s 2 1; s 4 2 ] ]
      (broken_at "missing seq 3 of 3");
    case "a tip that does not start at 1" ~depth:Ledger.Tip
      [ chunked [ s 2 0; s 3 1 ] ]
      (broken_at "missing seq 1 of 2");
    case "the largest seq in a tree of one entry" ~depth:Ledger.Tip
      [ chunked [ s ((1 lsl 53) - 1) 0 ] ]
      (broken_at "missing seq 1 of 1");
    case "a seq above the largest is a bad line" ~depth:Ledger.Tip
      [
        chunked
          [
            replace_once (s 1 0) ~sub:"\"seq\":1" ~by:"\"seq\":9007199254740992";
          ];
      ]
      (fun repo ->
        let line =
          replace_once (s 1 0) ~sub:"\"seq\":1" ~by:"\"seq\":9007199254740992"
        in
        broken_at ~path:(chunk_path [ line ]) ~line:"1" "bad line" repo);
    case "a repeated id comes before a repeated seq" ~depth:Ledger.Tip
      [ chunked [ s 1 0; s 1 0 ] ]
      (broken_at ~path:(chunk_path [ s 1 0 ]) ~line:"2" "repeated id");
    case "a gap that only an unknown kind fills passes at the tip"
      ~depth:Ledger.Tip
      [ chunked [ s 1 0; unknown_at 2; s 3 1 ] ]
      (ok 2 1);
    case "a void holds the seq of an entry"
      [
        chunked
          [
            s 1 0;
            line_of
              (common ~kind:"void" ~seq:2 ()
              @ [
                  ("dropped", Json.String ("e-" ^ String.make 12 'a'));
                  ("reason", Json.String "r");
                ]);
            s 3 1;
          ];
      ]
      (ok 3 1);
  ]

let seq_history_cases =
  [
    case "an insertion below the highest seq of the parent fails at the parent"
      [ chunked [ s 1 0; s 3 2 ]; chunked [ s 1 0; s 3 2; s 2 1 ] ]
      (broken_at ~back:1 "missing seq 2 of 2");
    case "the least of several insertions is the missing seq"
      [
        chunked [ s 1 0; s 2 1; s 5 4 ];
        chunked [ s 1 0; s 2 1; s 5 4; s 4 3; s 3 2 ];
      ]
      (broken_at ~back:1 "missing seq 3 of 3");
    case "an insertion at the highest seq of the parent fails"
      [ chunked [ s 1 0; s 3 2 ]; chunked [ s 1 0; s 2 1; s 3 2 ] ]
      (broken_at ~back:1 "missing seq 2 of 2");
    case "a parent whose seqs do not start at 1 fails"
      [ chunked [ s 2 1 ]; chunked [ s 2 1; s 1 0 ] ]
      (broken_at ~back:1 "missing seq 1 of 1");
    case "entries that a commit adds above its parent verify"
      [ chunked [ s 1 0 ]; chunked [ s 1 0; s 2 1 ] @ chunked [ s 3 2 ] ]
      (ok 3 2);
    case "a gap that only an unknown kind fills passes in the walk"
      [ chunked [ s 1 0 ]; chunked [ s 1 0; unknown_at 2; s 3 1 ] ]
      (ok 2 2);
    case "a repeated id of the parent comes before its missing seq"
      [
        chunked [ s 1 0 ] @ chunked [ s 3 2; s 1 0 ];
        chunked [ s 1 0; s 2 1; s 3 2 ];
      ]
      (fun repo ->
        let first = chunk_path [ s 1 0 ] and other = chunk_path [ s 3 2 ] in
        if first < other then
          broken_at ~back:1 ~path:other ~line:"2" "repeated id" repo
        else broken_at ~back:1 ~path:first ~line:"1" "repeated id" repo);
  ]

let in_chunks_of_one lines =
  List.concat_map (fun line -> chunked [ line ]) lines

let work_of repo depth =
  match Ledger.read (opened repo) depth with
  | Ok (Some ledger) ->
      let { Ledger.waits; listings; lines; matches } = Ledger.work ledger in
      Printf.sprintf "waits %d, listings %d, lines %d, matches %d" waits
        listings lines matches
  | other -> Alcotest.fail (describe other)

let e = entry

let chunk_at name lines =
  match Sinter_bench.Generated_ledger.chunks [ entry name ] with
  | (path, _) :: _ -> Chunk (path, lines_of lines)
  | [] -> Alcotest.fail "no chunk"

let path_of n seq = chunk_path [ entry ~seq n ]

let find_entry ?(from = 0) test =
  let rec go n = if test n then n else go (n + 1) in
  go from

let later_in_a_new_chunk =
  let x1 = find_entry ~from:1 (fun n -> path_of n 2 > path_of 0 1) in
  let a = entry ~seq:1 0
  and b = entry ~seq:2 x1
  and c = entry ~seq:3 (x1 + 1) in
  case "a parent that holds an entry twice, the second in a new chunk, fails"
    [ chunked [ a; b ] @ chunked [ b ]; chunked [ a; b; c ] ]
    (broken_at ~back:1 ~path:(chunk_path [ b ]) ~line:"1" "repeated id")

let later_in_an_older_chunk =
  let x1 = find_entry ~from:3 (fun n -> path_of n 2 < path_of 2 3) in
  let a = entry ~seq:3 2 and b = entry ~seq:2 x1 and c = entry ~seq:1 0 in
  case "a parent that holds an entry twice, the second in an older chunk, fails"
    [ chunked [ a; b ] @ chunked [ b ]; chunked [ a; b; c ] ]
    (broken_at ~back:1 ~path:(chunk_path [ a ]) ~line:"2" "repeated id")

let gap_cases =
  [
    later_in_a_new_chunk;
    later_in_an_older_chunk;
    case "a new chunk of a parent with the name of another entry fails"
      [ [ chunk_at 1 [ e 0; e 1 ] ]; chunked [ e 0; e 1 ] ]
      (broken_at ~back:1 ~path:(chunk_path [ e 1 ]) "wrong name");
    case "a misnamed chunk of a parent is a wrong name before a drop"
      [ [ chunk_at 1 [ e 5 ] ] @ chunked [ e 0 ]; chunked [ e 0 ] ]
      (broken_at ~back:1 ~path:(chunk_path [ e 1 ]) "wrong name");
    case "an entry that a commit drops and a later commit adds again fails"
      [ chunked [ e 0; e 1 ]; chunked [ e 0 ]; chunked [ e 0; e 1 ] ]
      (broken_at ~back:1 ~path:(chunk_path [ e 0 ]) ~line:"2" "dropped");
    case "a chunk that a commit drops and a later commit adds again fails"
      [
        chunked [ e 0 ] @ chunked [ e 1 ];
        chunked [ e 0 ];
        chunked [ e 0 ] @ chunked [ e 1 ];
      ]
      (broken_at ~back:1 ~path:(chunk_path [ e 1 ]) ~line:"1" "dropped");
    case "a chunk that a commit drops and a later commit adds longer fails"
      [
        chunked [ e 0 ] @ chunked [ e 1 ];
        chunked [ e 0 ];
        chunked [ e 0 ] @ chunked [ e 1; e 2 ];
      ]
      (broken_at ~back:1 ~path:(chunk_path [ e 1 ]) ~line:"1" "dropped");
  ]

let folder_of n seq = Filename.basename (Filename.dirname (path_of n seq))

let a_line_of_a_shared_chunk_in_an_earlier_changed_folder () =
  let n_a2 = find_entry ~from:1 (fun n -> folder_of n 3 = folder_of 0 1) in
  let n_b =
    find_entry ~from:1 (fun n -> n <> n_a2 && folder_of n 4 > folder_of 0 1)
  in
  let spare = max n_a2 n_b + 1 in
  let a = entry ~seq:1 0
  and y = entry ~seq:2 spare
  and a2 = entry ~seq:3 n_a2
  and b = entry ~seq:4 n_b
  and z = entry ~seq:5 (spare + 1) in
  let repo =
    build
      [
        chunked [ a; y ] @ chunked [ a2 ] @ chunked [ b; y ];
        chunked [ a; y ] @ chunked [ a2; z ] @ chunked [ b ];
      ]
  in
  Alcotest.(check string)
    "the result"
    (broken_at ~back:1 ~path:(chunk_path [ b ]) ~line:"2" "repeated id" repo)
    (describe (Ledger.read (opened repo) Ledger.History))

let later_folder_case () =
  let n_b2 = find_entry ~from:1 (fun n -> folder_of n 3 = folder_of 0 1) in
  let n_early =
    find_entry ~from:1 (fun n -> n <> n_b2 && folder_of n 4 < folder_of 0 1)
  in
  let spare = max n_b2 n_early + 1 in
  ( entry ~seq:1 0,
    entry ~seq:2 spare,
    entry ~seq:3 n_b2,
    entry ~seq:4 n_early,
    entry ~seq:5 (spare + 1) )

let a_line_of_a_shared_chunk_in_a_later_changed_folder () =
  let b, y, b2, early, z = later_folder_case () in
  let repo =
    build
      [
        chunked [ b; y ] @ chunked [ b2 ] @ chunked [ early; y ];
        chunked [ b; y ] @ chunked [ b2; z ] @ chunked [ early ];
      ]
  in
  Alcotest.(check string)
    "the result"
    (broken_at ~back:1 ~path:(chunk_path [ early ]) ~line:"2" "repeated id" repo)
    (describe (Ledger.read (opened repo) Ledger.History))

let a_later_changed_folder_is_read_once () =
  let b, y, b2, early, z = later_folder_case () in
  let repo =
    build
      [
        chunked [ b ] @ chunked [ b2 ] @ chunked [ early; y ];
        chunked [ b; y ] @ chunked [ b2; z ] @ chunked [ early ];
      ]
  in
  Alcotest.(check string)
    "the work" "waits 13, listings 1, lines 5, matches 2"
    (work_of repo Ledger.History)

let history_cases =
  Alcotest.
    [
      test_case "a line of a shared chunk in an earlier changed folder" `Quick
        a_line_of_a_shared_chunk_in_an_earlier_changed_folder;
      test_case "a line of a shared chunk in a later changed folder" `Quick
        a_line_of_a_shared_chunk_in_a_later_changed_folder;
      test_case "a later changed folder is read once" `Quick
        a_later_changed_folder_is_read_once;
    ]
  @ gap_cases
  @ [
      case "a commit that drops an entry fails"
        [ chunked three; chunked [ List.hd three; List.nth three 1 ] ]
        (broken_at ~path:path3 ~line:"3" "dropped");
      case "a commit that drops a whole chunk fails"
        [ chunked three @ chunked [ entry 9 ]; chunked three ]
        (fun repo ->
          broken_at ~path:(chunk_path [ entry 9 ]) ~line:"1" "dropped" repo);
      case "a commit that moves entries between chunks verifies"
        [ in_chunks_of_one three; chunked three ]
        (ok 3 2);
      case "a commit that splits a chunk verifies"
        [ chunked three; in_chunks_of_one three ]
        (ok 3 2);
      case "a commit that copies an entry fails at the copy"
        [ chunked three @ chunked [ List.nth three 1 ]; chunked three ]
        (broken_at ~back:1
           ~path:(chunk_path [ List.nth three 1 ])
           ~line:"1" "repeated id");
      case "a tip check does not walk the history" ~depth:Ledger.Tip
        [ chunked three; chunked [ List.hd three ] ]
        (ok 1 1);
      case "a parent with a bad tree fails"
        [ chunked three @ [ Chunk ("x", "y\n") ]; chunked three ]
        (broken_at ~back:1 ~path:"x" "wrong path 100644");
    ]

let tag_tree_and_blob () =
  let repo = build [ chunked three ] in
  let tip = commit_of repo 0 in
  let check name target fault =
    ignore (Repo.git repo [ "update-ref"; Ledger.ref_name; target ]);
    Alcotest.(check string)
      name
      (Printf.sprintf "broken %s at %s - -" fault target)
      (describe (Ledger.read (opened repo) Ledger.Tip))
  in
  ignore (Repo.git repo [ "tag"; "-a"; "-m"; "t"; "t"; tip ]);
  check "a tag"
    (String.trim (Repo.git repo [ "rev-parse"; "refs/tags/t" ]))
    "not a commit";
  check "a tree"
    (String.trim (Repo.git repo [ "rev-parse"; tip ^ "^{tree}" ]))
    "not a commit";
  check "a blob"
    (String.trim (Repo.git_input repo [ "hash-object"; "-w"; "--stdin" ] "x"))
    "not a commit"

let no_ref_is_no_ledger () =
  let repo = Repo.init () in
  Alcotest.(check string)
    "the result" "no ledger"
    (describe (Ledger.read (opened repo) Ledger.History))

let a_ref_to_a_missing_object () =
  let repo = build [ chunked three ] in
  let missing = String.make 40 'd' in
  Out_channel.with_open_bin
    (Filename.concat (Repo.root repo) ".git/refs/sinter/ledger")
    (fun channel -> Out_channel.output_string channel (missing ^ "\n"));
  Alcotest.(check string)
    "the result"
    (Printf.sprintf "missing object %s in %s" missing missing)
    (describe (Ledger.read (opened repo) Ledger.Tip))

let literally repo kind content =
  String.trim
    (Repo.git_input repo
       [ "hash-object"; "-t"; kind; "--literally"; "-w"; "--stdin" ]
       content)

let raw_id hex =
  String.init
    (String.length hex / 2)
    (fun i -> Char.chr (int_of_string ("0x" ^ String.sub hex (2 * i) 2)))

let tree_of repo entries =
  literally repo "tree"
    (String.concat ""
       (List.map
          (fun (mode, name, id) ->
            Printf.sprintf "%s %s\000%s" mode name (raw_id id))
          entries))

let blob repo content =
  String.trim (Repo.git_input repo [ "hash-object"; "-w"; "--stdin" ] content)

let commit_raw repo ?(parents = []) tree =
  literally repo "commit"
    (Printf.sprintf
       "tree %s\n%sauthor A <a> 0 +0000\ncommitter A <a> 0 +0000\n\nm\n" tree
       (String.concat "" (List.map (fun p -> "parent " ^ p ^ "\n") parents)))

let point repo commit =
  let folder = Filename.concat (Repo.root repo) ".git/refs/sinter" in
  if not (Sys.file_exists folder) then Unix.mkdir folder 0o755;
  Out_channel.with_open_bin (Filename.concat folder "ledger") (fun channel ->
      Out_channel.output_string channel (commit ^ "\n"))

let read_crafted repo depth commit =
  point repo commit;
  describe (Ledger.read (opened repo) depth)

let ledger_tree repo chunk_name content =
  let folder = String.sub chunk_name 2 2 in
  let chunk = tree_of repo [ ("100644", chunk_name, blob repo content) ] in
  let entries = tree_of repo [ ("40000", folder, chunk) ] in
  tree_of repo [ ("40000", "entries", entries) ]

let crafted_trees () =
  let repo = Repo.init () in
  let name = Filename.basename path3 in
  let folder = String.sub name 2 2 in
  let good = blob repo (lines_of three) in
  let empty = tree_of repo [] in
  let check label tree expected =
    let commit = commit_raw repo tree in
    let words = String.split_on_char ' ' expected in
    let count = List.length words in
    let fault = List.filteri (fun i _ -> i < count - 2) words
    and place = List.filteri (fun i _ -> i >= count - 2) words in
    Alcotest.(check string)
      label
      (Printf.sprintf "broken %s at %s %s" (String.concat " " fault) commit
         (String.concat " " place))
      (read_crafted repo Ledger.Tip commit)
  in
  check "an empty folder of entries"
    (tree_of repo [ ("40000", "entries", empty) ])
    "empty folder entries -";
  check "an empty folder of chunks"
    (tree_of repo
       [ ("40000", "entries", tree_of repo [ ("40000", folder, empty) ]) ])
    (Printf.sprintf "empty folder entries/%s -" folder);
  check "a name twice in the root"
    (tree_of repo
       [
         ( "40000",
           "entries",
           tree_of repo
             [ ("40000", folder, tree_of repo [ ("100644", name, good) ]) ] );
         ("40000", "entries", empty);
       ])
    "unordered tree - -";
  check "a chunk twice in a folder"
    (tree_of repo
       [
         ( "40000",
           "entries",
           tree_of repo
             [
               ( "40000",
                 folder,
                 tree_of repo [ ("100644", name, good); ("100644", name, good) ]
               );
             ] );
       ])
    (Printf.sprintf "unordered tree entries/%s -" folder);
  check "a file beside entries is a wrong path before the order"
    (tree_of repo
       [
         ("100644", "entries.txt", good);
         ( "40000",
           "entries",
           tree_of repo
             [ ("40000", folder, tree_of repo [ ("100644", name, good) ]) ] );
       ])
    "wrong path 100644 entries.txt -";
  check "folders out of order"
    (tree_of repo
       [
         ( "40000",
           "entries",
           tree_of repo [ ("40000", "ff", empty); ("40000", "00", empty) ] );
       ])
    "unordered tree entries -";
  check "a folder that is a blob"
    (tree_of repo
       [ ("40000", "entries", tree_of repo [ ("40000", folder, good) ]) ])
    (Printf.sprintf "wrong object entries/%s -" folder);
  check "a chunk that is a tree"
    (tree_of repo
       [
         ( "40000",
           "entries",
           tree_of repo
             [ ("40000", folder, tree_of repo [ ("100644", name, empty) ]) ] );
       ])
    (Printf.sprintf "wrong object %s -" path3);
  check "a tree that does not decode"
    (literally repo "tree" "100644 x")
    "bad tree - -";
  let root = ledger_tree repo name (lines_of three) in
  let first = commit_raw repo root in
  let second = commit_raw repo ~parents:[ first ] root in
  Alcotest.(check string)
    "a sound crafted history" "ok 3 entries 2 commits"
    (read_crafted repo Ledger.History second);
  let chunk_tree = tree_of repo [ ("100644", name, good) ] in
  let odd_root =
    tree_of repo
      [ ("40000", "entries", tree_of repo [ ("50000", folder, chunk_tree) ]) ]
  in
  let odd = commit_raw repo odd_root in
  let over_odd = commit_raw repo ~parents:[ odd ] root in
  Alcotest.(check string)
    "a parent whose listing differs from the child's in a mode alone"
    (Printf.sprintf "broken wrong path 50000 at %s entries/%s -" odd folder)
    (read_crafted repo Ledger.History over_odd);
  let folder_tree =
    String.trim
      (Repo.git repo
         [ "rev-parse"; Printf.sprintf "%s:entries/%s" root folder ])
  in
  List.iter
    (fun digit ->
      let near =
        String.mapi
          (fun i c -> if i = digit then if c = '0' then '1' else '0' else c)
          folder_tree
      in
      let near_root =
        tree_of repo
          [ ("40000", "entries", tree_of repo [ ("40000", folder, near) ]) ]
      in
      let near_parent = commit_raw repo near_root in
      let over_near = commit_raw repo ~parents:[ near_parent ] root in
      Alcotest.(check string)
        (Printf.sprintf
           "a parent whose folder differs from the child's in the digit %d of \
            its id"
           digit)
        (Printf.sprintf "missing object %s in %s" near near_parent)
        (read_crafted repo Ledger.History over_near))
    (List.init 40 Fun.id);
  let listing =
    Repo.git repo [ "cat-file"; "tree"; Printf.sprintf "%s:entries" root ]
  in
  let broken_listing =
    String.mapi (fun i c -> if i = 8 then 'x' else c) listing
  in
  let odd_listing = literally repo "tree" broken_listing in
  let odd_header =
    commit_raw repo (tree_of repo [ ("40000", "entries", odd_listing) ])
  in
  let over_odd_header = commit_raw repo ~parents:[ odd_header ] root in
  Alcotest.(check string)
    "a parent listing whose separator differs from the child's"
    (Printf.sprintf "broken bad tree at %s entries -" odd_header)
    (read_crafted repo Ledger.History over_odd_header);
  let merge = commit_raw repo ~parents:[ first; second ] root in
  Alcotest.(check string)
    "a merge commit"
    (Printf.sprintf "broken merge commit 2 at %s - -" merge)
    (read_crafted repo Ledger.History merge);
  Alcotest.(check string)
    "a merge commit at the tip check" "ok 3 entries 1 commits"
    (read_crafted repo Ledger.Tip merge);
  let on_blob = commit_raw repo ~parents:[ good ] root in
  Alcotest.(check string)
    "a parent that is a blob"
    (Printf.sprintf "broken parent not a commit at %s - -" on_blob)
    (read_crafted repo Ledger.History on_blob);
  let long = commit_raw repo ~parents:[ String.make 64 'a' ] root in
  Alcotest.(check string)
    "a parent of the length of SHA-256"
    (Printf.sprintf "broken bad commit at %s - -" long)
    (read_crafted repo Ledger.History long);
  let long_tree = commit_raw repo (String.make 64 'a') in
  Alcotest.(check string)
    "a tree of the length of SHA-256"
    (Printf.sprintf "broken bad commit at %s - -" long_tree)
    (read_crafted repo Ledger.Tip long_tree);
  let bad_parent = commit_raw repo (String.make 64 'b') in
  let over_bad = commit_raw repo ~parents:[ bad_parent ] root in
  Alcotest.(check string)
    "a parent whose tree has the length of SHA-256"
    (Printf.sprintf "broken bad commit at %s - -" bad_parent)
    (read_crafted repo Ledger.History over_bad);
  let garbage = literally repo "commit" "no tree here\n\n" in
  Alcotest.(check string)
    "a commit that does not decode"
    (Printf.sprintf "broken bad commit at %s - -" garbage)
    (read_crafted repo Ledger.Tip garbage);
  let missing = commit_raw repo ~parents:[ String.make 40 'e' ] root in
  Alcotest.(check string)
    "a missing parent"
    (Printf.sprintf "missing parent %s of %s" (String.make 40 'e') missing)
    (read_crafted repo Ledger.History missing);
  let lost =
    commit_raw repo
      (tree_of repo
         [
           ( "40000",
             "entries",
             tree_of repo
               [
                 ( "40000",
                   folder,
                   tree_of repo [ ("100644", name, String.make 40 'f') ] );
               ] );
         ])
  in
  Alcotest.(check string)
    "a missing chunk"
    (Printf.sprintf "missing object %s in %s" (String.make 40 'f') lost)
    (read_crafted repo Ledger.Tip lost)

let grafts_and_replacements_do_not_count () =
  let repo = build [ chunked three; chunked (three @ [ entry 3 ]) ] in
  let tip = commit_of repo 0 and parent = commit_of repo 1 in
  let fake =
    String.trim
      (Repo.git repo
         [
           "commit-tree";
           String.trim (Repo.git repo [ "rev-parse"; tip ^ "^{tree}" ]);
           "-m";
           "f";
         ])
  in
  let dropped =
    String.trim
      (Repo.git repo
         [
           "commit-tree";
           Repo.git repo [ "rev-parse"; parent ^ "^{tree}" ] |> String.trim;
           "-p";
           fake;
           "-m";
           "d";
         ])
  in
  let git_dir = Filename.concat (Repo.root repo) ".git" in
  (try Unix.mkdir (Filename.concat git_dir "info") 0o755
   with Unix.Unix_error (Unix.EEXIST, _, _) -> ());
  Out_channel.with_open_bin (Filename.concat git_dir "info/grafts")
    (fun channel ->
      Out_channel.output_string channel (tip ^ " " ^ dropped ^ "\n"));
  ignore (Repo.git repo [ "replace"; "-f"; parent; dropped ]);
  Alcotest.(check string)
    "the history of the raw objects" "ok 4 entries 2 commits"
    (describe (Ledger.read (opened repo) Ledger.History))

let unknown_parts_warn () =
  let lines =
    three
    @ [
        unknown_kind_at 4;
        line_of (approval_at 5 @ [ ("later", Json.Bool true) ]);
      ]
  in
  let repo = build [ chunked lines ] in
  match Ledger.read (opened repo) Ledger.Tip with
  | Ok (Some ledger) ->
      Alcotest.(check (pair int int))
        "the counts" (1, 1) (Ledger.unknown ledger);
      Alcotest.(check int)
        "the known entries" 4
        (List.length (Ledger.entries ledger));
      Alcotest.(check (option string))
        "the warning"
        (Some
           "the ledger holds 1 entry of an unknown kind and 1 unknown field; \
            sinter ignores them")
        (Ledger.warning ledger);
      Alcotest.(check string) "the tip" (commit_of repo 0) (Ledger.tip ledger)
  | other -> Alcotest.fail (describe other)

let warning_forms () =
  let warning lines =
    match
      Ledger.read (opened (build [ chunked (three @ lines) ])) Ledger.Tip
    with
    | Ok (Some ledger) -> Ledger.warning ledger
    | other -> Alcotest.fail (describe other)
  in
  Alcotest.(check (option string)) "none" None (warning []);
  Alcotest.(check (option string))
    "two fields" (Some "the ledger holds 2 unknown fields; sinter ignores them")
    (warning
       [ line_of (approval_at 4 @ [ ("a1", Json.Int 1); ("a2", Json.Int 2) ]) ]);
  Alcotest.(check (option string))
    "one field" (Some "the ledger holds 1 unknown field; sinter ignores it")
    (warning [ line_of (approval_at 4 @ [ ("a1", Json.Int 1) ]) ]);
  Alcotest.(check (option string))
    "two kinds"
    (Some "the ledger holds 2 entries of an unknown kind; sinter ignores them")
    (warning
       [
         unknown_kind_at 4;
         line_of
           (("kind", Json.String "x")
           :: List.remove_assoc "kind" (common ~seq:5 ()));
       ])

let entries_come_in_order () =
  let lines = List.rev (entries 0 150) in
  match Ledger.read (opened (build [ chunked lines ])) Ledger.Tip with
  | Ok (Some ledger) ->
      Alcotest.(check (list string))
        "the lines" (entries 0 150)
        (List.map (fun (e : Ledger.entry) -> e.line) (Ledger.entries ledger))
  | other -> Alcotest.fail (describe other)

let a_generated_ledger_verifies () =
  let repo = Repo.init () in
  Sinter_bench.Generated_ledger.write repo ~entries:250 ~per_commit:7;
  Alcotest.(check string)
    "the history" "ok 250 entries 37 commits"
    (describe (Ledger.read (opened repo) Ledger.History));
  Alcotest.(check string)
    "the tip" "ok 250 entries 1 commits"
    (describe (Ledger.read (opened repo) Ledger.Tip))

let a_sha256_ledger_verifies () =
  let repo = Repo.init ~object_format:"sha256" () in
  let lines =
    List.init 120 (fun n ->
        line_of
          (("head", Json.String (String.make 64 'c'))
          :: ("subject", Json.String (string_of_int n))
          :: List.remove_assoc "subject"
               (List.remove_assoc "head" (approval_at (n + 1)))))
  in
  let first count = List.filteri (fun i _ -> i < count) lines in
  ignore
    (build ~repo
       [
         [];
         chunked (first 3);
         chunked (first 110);
         chunked (first 115);
         chunked (first 118);
         chunked lines;
       ]);
  Alcotest.(check string)
    "the history" "ok 120 entries 6 commits"
    (describe (Ledger.read (opened repo) Ledger.History));
  Alcotest.(check string)
    "the work" "waits 19, listings 2, lines 120, matches 0"
    (work_of repo Ledger.History)

let clones_that_lack_objects () =
  let source = Repo.init () in
  Repo.write source "a.txt" "a\n";
  ignore (Repo.git source [ "add"; "a.txt" ]);
  ignore (Repo.git source [ "commit"; "-q"; "-m"; "a" ]);
  ignore
    (build ~repo:source
       [ chunked three; chunked (entries 0 4); chunked (entries 0 5) ]);
  Repo.append_config source "[uploadpack]\n\tallowFilter = true\n";
  let url = "file://" ^ Repo.root source in
  let shallow = Repo.init () in
  ignore
    (Repo.git shallow
       [
         "fetch";
         "-q";
         "--depth=1";
         url;
         Ledger.ref_name ^ ":" ^ Ledger.ref_name;
       ]);
  (match Ledger.read (opened shallow) Ledger.History with
  | Error (Ledger.Missing_parent _) -> ()
  | other -> Alcotest.fail ("a shallow clone: " ^ describe other));
  holds "a shallow clone reads its tip"
    (Result.is_ok (Ledger.read (opened shallow) Ledger.Tip));
  let partial = Repo.init () in
  ignore (Repo.git partial [ "remote"; "add"; "origin"; url ]);
  ignore
    (Repo.git partial
       [
         "fetch";
         "-q";
         "--filter=blob:none";
         "origin";
         Ledger.ref_name ^ ":" ^ Ledger.ref_name;
       ]);
  match Ledger.read (opened partial) Ledger.Tip with
  | Error (Ledger.Missing_object _) -> ()
  | other -> Alcotest.fail ("a partial clone: " ^ describe other)

let explain_texts () =
  let text error =
    (Ledger.explain error).fault ^ " / " ^ (Ledger.explain error).help
  in
  let commit = String.make 40 'a' and parent = String.make 40 'b' in
  let broken ?path ?line ?entry fault =
    text (Ledger.Broken { commit; path; line; entry; fault })
  in
  Alcotest.(check string)
    "a line"
    ("the ledger is broken: the line 3 of entries/ab/e-abababababab.jsonl in \
      the commit " ^ commit
   ^ " is not in the canonical form (the entry e-1) / repair the ledger with \
      sinter ledger repair")
    (broken ~path:"entries/ab/e-abababababab.jsonl" ~line:3 ~entry:"e-1"
       (Ledger.Bad_line Ledger.Not_canonical));
  Alcotest.(check string)
    "a path with a control character"
    ("the ledger is broken: a\xef\xbf\xbdb in the commit " ^ commit
   ^ " is an empty chunk / repair the ledger with sinter ledger repair")
    (broken ~path:"a\027b" Ledger.Empty_chunk);
  Alcotest.(check string)
    "a dropped entry"
    ("the ledger is broken: the commit " ^ commit
   ^ " drops the entry e-2 that the line 1 of p in the commit " ^ parent
   ^ " holds / repair the ledger with sinter ledger repair")
    (broken ~path:"p" ~line:1 ~entry:"e-2" (Ledger.Dropped { parent }));
  Alcotest.(check string)
    "a merge"
    ("the ledger is broken: the commit " ^ commit
   ^ " is a merge commit with 2 parents / repair the ledger with sinter ledger \
      repair")
    (broken (Ledger.Merge_commit 2));
  Alcotest.(check string)
    "a newer version"
    ("the line 4 of p in the commit " ^ commit
   ^ " holds an entry of version 2, and this sinter reads version 1 / upgrade \
      sinter to a version that reads the ledger")
    (text (Ledger.Newer { commit; path = "p"; line = 4; version = 2 }));
  Alcotest.(check string)
    "a missing parent"
    ("the clone does not hold the commit " ^ parent
   ^ " of the ledger, the parent of " ^ commit
   ^ " / fetch the whole history of the ledger with git fetch \
      --depth=2147483647 --no-filter origin refs/sinter/ledger")
    (text (Ledger.Missing_parent { commit; parent }));
  Alcotest.(check string)
    "a missing object"
    ("the clone does not hold the object " ^ parent
   ^ " of the ledger, in the commit " ^ commit
   ^ " / fetch every object of the ledger with git fetch --refetch --no-filter \
      origin refs/sinter/ledger")
    (text (Ledger.Missing_object { commit; id = parent }));
  List.iter
    (fun fault ->
      holds "every fault has a text"
        (String.length (broken ~path:"p" ~line:1 fault) > 0))
    Ledger.
      [
        Not_a_commit Git.Decode.Tag;
        Bad_commit "x";
        Parent_not_a_commit { parent; kind = Git.Decode.Blob };
        Bad_tree "x";
        Wrong_object Git.Decode.Tree;
        Wrong_path { mode = 0o100755 };
        Unordered_tree;
        Empty_folder;
        No_line_feed;
        Wrong_name "e-1";
        Repeated_id;
      ]

let random_chunks lines sizes =
  let rec take lines sizes =
    match lines with
    | [] -> []
    | _ ->
        let size, sizes =
          match sizes with size :: rest -> (max 1 size, rest) | [] -> (100, [])
        in
        let chunk = List.filteri (fun i _ -> i < size) lines in
        let rest = List.filteri (fun i _ -> i >= size) lines in
        chunked chunk |> fun files -> files @ take rest sizes
  in
  take lines sizes

let growth =
  Gen.(
    pair
      (list_size (int_range 1 5) (int_range 0 4))
      (list_size (int_range 1 6) (list_size (int_range 1 4) (int_range 1 5))))

let states_of (additions, layouts) =
  let _, states =
    List.fold_left
      (fun (count, states) (added, index) ->
        let count = count + added in
        let sizes = List.nth layouts (index mod List.length layouts) in
        (count, random_chunks (entries 0 count) sizes :: states))
      (0, [])
      (List.mapi (fun index added -> (added, index)) additions)
  in
  List.rev states

let print_growth (additions, layouts) =
  Printf.sprintf "additions [%s], layouts %d"
    (String.concat "; " (List.map string_of_int additions))
    (List.length layouts)

let additions_verify =
  property ~count:40
    ~name:"a history that only adds entries, in any chunks, verifies"
    ~print:print_growth growth (fun growth ->
      let states = states_of growth in
      let total = List.fold_left ( + ) 0 (fst growth) in
      describe (Ledger.read (opened (build states)) Ledger.History)
      = Printf.sprintf "ok %d entries %d commits" total (List.length states))

let a_lost_entry_fails =
  property ~count:40
    ~name:"a commit that drops or changes an entry of its parent fails"
    ~print:(fun (growth, (lost, changed)) ->
      Printf.sprintf "%s, lost %d, changed %b" (print_growth growth) lost
        changed)
    Gen.(pair growth (pair nat bool))
    (fun (growth, (lost, changed)) ->
      let states = states_of growth in
      let total = List.fold_left ( + ) 0 (fst growth) in
      if total = 0 then true
      else
        let lost = lost mod total in
        let lines =
          List.filteri (fun i _ -> i <> lost) (entries 0 total)
          @ if changed then [ entry ~seq:(lost + 1) (1000 + lost) ] else []
        in
        let states = states @ [ chunked lines ] in
        let repo = build states in
        match Ledger.read (opened repo) Ledger.History with
        | Error
            (Ledger.Broken
               { commit; fault = Ledger.Missing_seq { seq; count }; _ })
          when not changed ->
            lost + 1 < total
            && String.equal commit (commit_of repo 0)
            && seq = lost + 1
            && count = total - 1
        | Error (Ledger.Broken { commit; fault = Ledger.Dropped _; entry; _ })
          when changed || lost + 1 = total -> (
            String.equal commit (commit_of repo 0)
            && entry
               =
               match
                 Ledger.read_line Git.Sha1
                   (Sinter_bench.Generated_ledger.entry lost)
               with
               | Ok (Ledger.Known { entry; _ }) -> Some entry.id
               | _ -> None)
        | _ -> false)

let a_shuffle_keeps_the_order =
  property ~count:40
    ~name:"a tip whose chunks hold the entries in any order reads in seq order"
    ~print:(fun (count, (keys, sizes)) ->
      Printf.sprintf "count %d, keys [%s], sizes [%s]" count
        (String.concat "; " (List.map string_of_int keys))
        (String.concat "; " (List.map string_of_int sizes)))
    Gen.(
      pair (int_range 1 120)
        (pair
           (list_size (return 120) (int_bound 1_000_000))
           (list_size (int_range 1 6) (int_range 1 60))))
    (fun (count, (keys, sizes)) ->
      let lines = entries 0 count in
      let shuffled =
        List.map snd
          (List.sort compare
             (List.mapi
                (fun index line -> ((List.nth keys index, index), line))
                lines))
      in
      match
        Ledger.read (opened (build [ random_chunks shuffled sizes ])) Ledger.Tip
      with
      | Ok (Some ledger) ->
          List.map (fun (e : Ledger.entry) -> e.line) (Ledger.entries ledger)
          = lines
      | _ -> false)

let output_forms () =
  let repo = build [ chunked (entries 0 1) ] in
  (match Ledger.read (opened repo) Ledger.History with
  | Ok (Some ledger) ->
      Alcotest.(check string)
        "one entry in one commit"
        "the ledger passes verification: 1 entry in 1 commit"
        (Ledger.summary ledger)
  | other -> Alcotest.fail (describe other));
  let entry_of fields =
    match read (line_of fields) with
    | Ok (Ledger.Known { entry; _ }) -> entry
    | _ -> Alcotest.fail "the line does not read"
  in
  let set =
    entry_of
      (("by", Json.String "a\027b")
       :: List.remove_assoc "by" (set_fields ~csh:(hash 1) [] [])
      |> List.map (function "seq", _ -> ("seq", Json.Int 12) | field -> field))
  and void =
    entry_of
      (common ~kind:"void" ~seq:3 ()
      @ [
          ("dropped", Json.String ("e-" ^ String.make 12 'a'));
          ("reason", Json.String "r");
        ])
  in
  (match
     Ledger.read
       (opened (build [ chunked (entries 0 2 @ [ unknown_kind_at 3 ]) ]))
       Ledger.Tip
   with
  | Ok (Some ledger) ->
      Alcotest.(check string)
        "the summary counts every kind"
        "the ledger passes verification: 3 entries in 1 commit"
        (Ledger.summary ledger)
  | other -> Alcotest.fail (describe other));
  Alcotest.(check string)
    "a commitment set names its hash"
    ("12 2026-10-31T14:05:09Z " ^ set.id ^ " commitment-set " ^ hash 1
   ^ " a\xef\xbf\xbdb")
    (Ledger.log_line set);
  Alcotest.(check string)
    "a void names the entry that it dropped"
    ("3 2026-10-31T14:05:09Z " ^ void.id ^ " void e-aaaaaaaaaaaa a@example.com")
    (Ledger.log_line void);
  let commit = String.make 40 'a' in
  let finding =
    Ledger.finding
      {
        commit;
        path = None;
        line = None;
        entry = None;
        fault = Ledger.Merge_commit 3;
      }
  in
  Alcotest.(check string)
    "the id of the finding"
    ("finding:ledger-broken:ledger:" ^ commit)
    (Finding.id finding);
  Alcotest.(check (option string))
    "the detail"
    (Some ("the commit " ^ commit ^ " is a merge commit with 3 parents"))
    finding.detail;
  holds "no place" (Option.is_none finding.place);
  let missing count =
    (Ledger.finding
       {
         commit;
         path = None;
         line = None;
         entry = None;
         fault = Ledger.Missing_seq { seq = 1; count };
       })
      .detail
  in
  Alcotest.(check (list (option string)))
    "the detail of a missing seq"
    [
      Some
        ("the commit " ^ commit ^ " holds 1 entry and no entry with the seq 1");
      Some
        ("the commit " ^ commit ^ " holds 3 entries and no entry with the seq 1");
    ]
    [ missing 1; missing 3 ]

let generated count =
  let repo = Repo.init () in
  Sinter_bench.Generated_ledger.write repo ~entries:count ~per_commit:1;
  opened repo

let the_work_of_a_read_grows_with_the_entries depth () =
  Counted_work.check_growth ~margin:2. ~sizes:(100, 1000) ~input:generated
    (fun t ->
      match Ledger.read t depth with
      | Ok (Some _) -> ()
      | other -> Alcotest.fail (describe other))

let the_work_of_a_long_history () =
  let repo = Repo.init () in
  Sinter_bench.Generated_ledger.write repo ~entries:513 ~per_commit:1;
  Alcotest.(check (list string))
    "the tip and the history"
    [
      "waits 24, listings 1, lines 513, matches 0";
      "waits 583, listings 10, lines 513, matches 0";
    ]
    [ work_of repo Ledger.Tip; work_of repo Ledger.History ]

let the_work_of_a_history_one_commit_past_a_window () =
  let repo = Repo.init () in
  Sinter_bench.Generated_ledger.write repo ~entries:194 ~per_commit:1;
  Alcotest.(check string)
    "the history" "waits 222, listings 3, lines 194, matches 0"
    (work_of repo Ledger.History)

let the_work_of_a_change_of_layout () =
  let lines = entries 0 120 in
  let repo =
    build
      [
        chunked (entries 0 3);
        in_chunks_of_one (entries 0 7);
        chunked (entries 0 60);
        chunked lines;
        chunked (List.rev lines);
        chunked (List.rev lines @ [ entry ~seq:121 500 ]);
      ]
  in
  Alcotest.(check string)
    "the history" "waits 18, listings 5, lines 121, matches 129"
    (work_of repo Ledger.History)

let reader_tests =
  [ additions_verify; a_lost_entry_fails; a_shuffle_keeps_the_order ]
  @ tree_cases @ seq_tip_cases @ history_cases @ seq_history_cases
  @ [
      Alcotest.test_case "no ref is no ledger" `Quick no_ref_is_no_ledger;
      Alcotest.test_case "a ref to a tag, a tree, or a blob" `Quick
        tag_tree_and_blob;
      Alcotest.test_case "a ref to an object that the clone lacks" `Quick
        a_ref_to_a_missing_object;
      Alcotest.test_case "crafted trees and commits" `Quick crafted_trees;
      Alcotest.test_case "grafts and replacements do not count" `Quick
        grafts_and_replacements_do_not_count;
      Alcotest.test_case "unknown kinds and fields give a warning" `Quick
        unknown_parts_warn;
      Alcotest.test_case "the forms of the warning" `Quick warning_forms;
      Alcotest.test_case "the entries come in the order of ts and id" `Quick
        entries_come_in_order;
      Alcotest.test_case "a generated ledger verifies" `Quick
        a_generated_ledger_verifies;
      Alcotest.test_case "a SHA-256 ledger verifies" `Quick
        a_sha256_ledger_verifies;
      Alcotest.test_case "a shallow or partial clone lacks objects" `Quick
        clones_that_lack_objects;
      Alcotest.test_case "the texts of the errors" `Quick explain_texts;
      Alcotest.test_case "the summary, the log line, and the finding" `Quick
        output_forms;
      Alcotest.test_case "the work of a long history" `Quick
        the_work_of_a_long_history;
      Alcotest.test_case "the work of a history one commit past a window" `Quick
        the_work_of_a_history_one_commit_past_a_window;
      Alcotest.test_case "the work of a change of layout" `Quick
        the_work_of_a_change_of_layout;
      Alcotest.test_case "the work of a read of the tip grows with the entries"
        `Quick
        (the_work_of_a_read_grows_with_the_entries Ledger.Tip);
      Alcotest.test_case "the work of a verification grows with the commits"
        `Quick
        (the_work_of_a_read_grows_with_the_entries Ledger.History);
    ]

let tests = line_tests @ reader_tests
