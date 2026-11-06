(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

let ref_name = "refs/sinter/ledger"
let version = 1
let chunk_size = 50

type approved = Text of { rev : int; xh : string } | Commitment of string
type scope = { step : string option; glob : string }
type promise = { step : string; word : string; target : string }

type body =
  | Approval of { subject : string; approved : approved; note : string option }
  | Commitment_set of {
      csh : string;
      scopes : scope list;
      promises : promise list;
      csh_holds : bool;
    }
  | Decline of { subject : string; hash : string; reason : string }
  | Delivered of { subject : string; csh : string; merge : string }
  | Completed of {
      subject : string;
      approval : string option;
      merge : string;
      report : string;
    }
  | Abandoned of { subject : string; reason : string }
  | Void of { dropped : string; reason : string }

type entry = {
  id : string;
  v : int;
  seq : int;
  by : string;
  ts : string;
  head : string;
  branch : string option;
  tool : string;
  body : body;
  line : string;
}

let kind_name = function
  | Approval _ -> "approval"
  | Commitment_set _ -> "commitment-set"
  | Decline _ -> "decline"
  | Delivered _ -> "delivered"
  | Completed _ -> "completed"
  | Abandoned _ -> "abandoned"
  | Void _ -> "void"

let subject = function
  | Approval { subject; _ }
  | Decline { subject; _ }
  | Delivered { subject; _ }
  | Completed { subject; _ }
  | Abandoned { subject; _ } ->
      Some subject
  | Commitment_set _ | Void _ -> None

let compare a b = Int.compare a.seq b.seq

type line_fault =
  | Not_json
  | Not_an_object
  | Bad_value of string
  | Repeated_key of string
  | Not_utf_8
  | Not_canonical
  | Missing_field of string
  | Wrong_type of string
  | Wrong_id of string
  | Approval_hashes

type read =
  | Known of { entry : entry; unknown_fields : int }
  | Unknown of { id : string; kind : string; seq : int }

type line_error =
  | Too_new of int
  | Fault of { id : string option; fault : line_fault }

let is_lower_hex text =
  String.for_all (function '0' .. '9' | 'a' .. 'f' -> true | _ -> false) text

let is_entry_id text =
  String.length text = 14
  && String.starts_with ~prefix:"e-" text
  && is_lower_hex (String.sub text 2 12)

let is_hash text = String.length text = 64 && is_lower_hex text
let id_length = function Git.Sha1 -> 40 | Git.Sha256 -> 64

let is_commit format text =
  String.length text = id_length format && is_lower_hex text

let is_digit c = c >= '0' && c <= '9'

let number text start length =
  let rec go i value =
    if i = start + length then value
    else go (i + 1) ((value * 10) + Char.code text.[i] - Char.code '0')
  in
  go start 0

let days_in year month =
  match month with
  | 2 ->
      if year mod 4 = 0 && (year mod 100 <> 0 || year mod 400 = 0) then 29
      else 28
  | 4 | 6 | 9 | 11 -> 30
  | _ -> 31

let is_ts text =
  String.length text = 20
  && List.for_all Fun.id
       (List.init 20 (fun i ->
            match i with
            | 4 | 7 -> text.[i] = '-'
            | 10 -> text.[i] = 'T'
            | 13 | 16 -> text.[i] = ':'
            | 19 -> text.[i] = 'Z'
            | _ -> is_digit text.[i]))
  &&
  let year = number text 0 4
  and month = number text 5 2
  and day = number text 8 2 in
  month >= 1 && month <= 12 && day >= 1
  && day <= days_in year month
  && number text 11 2 < 24
  && number text 14 2 < 60
  && number text 17 2 < 60

exception Line_fault of line_fault

let scalar = function
  | `String s -> Some (Json.String s)
  | `Int i -> Some (Json.Int i)
  | `Bool b -> Some (Json.Bool b)
  | _ -> None

let same_type a b =
  match (a, b) with
  | Json.String _, Json.String _
  | Json.Int _, Json.Int _
  | Json.Bool _, Json.Bool _ ->
      true
  | _ -> false

let value key raw =
  let bad () = raise (Line_fault (Bad_value key)) in
  match (scalar raw, raw) with
  | Some value, _ -> value
  | None, `List [] -> Json.Array []
  | None, `List (`Assoc _ :: _ as items) ->
      Json.Array
        (List.map
           (function
             | `Assoc fields ->
                 Json.Object
                   (List.map
                      (fun (name, field) ->
                        match scalar field with
                        | Some value -> (name, value)
                        | None -> bad ())
                      fields)
             | _ -> bad ())
           items)
  | None, `List (first :: _ as items) -> (
      match scalar first with
      | None -> bad ()
      | Some first ->
          Json.Array
            (List.map
               (fun item ->
                 match scalar item with
                 | Some value when same_type first value -> value
                 | Some _ | None -> bad ())
               items))
  | None, _ -> bad ()

let printed value =
  match Json.to_string value with
  | Ok text -> text
  | Error (Json.Repeated_key { key; _ }) ->
      raise (Line_fault (Repeated_key key))
  | Error (Json.Out_of_range { path; _ }) ->
      raise
        (Line_fault
           (Bad_value (match path with Json.Key key :: _ -> key | _ -> "")))
  | Error (Json.Not_utf_8 _) -> raise (Line_fault Not_utf_8)

let hash_id text = "e-" ^ String.sub (Sha256.hex text) 0 12

let id_of = function
  | Json.Object members ->
      Result.map hash_id
        (Json.to_string
           (Json.Object
              (List.filter
                 (fun (key, _) -> not (String.equal key "id"))
                 members)))
  | _ -> invalid_arg "Sinter_core.Ledger.id_of: the value is not an object"

let common_fields =
  [ "id"; "kind"; "v"; "seq"; "by"; "ts"; "head"; "branch"; "tool" ]

let kind_fields = function
  | "approval" -> Some [ "subject"; "rev"; "xh"; "csh"; "note" ]
  | "commitment-set" -> Some [ "csh"; "scopes"; "promises" ]
  | "decline" -> Some [ "subject"; "hash"; "reason" ]
  | "delivered" -> Some [ "subject"; "csh"; "merge" ]
  | "completed" -> Some [ "subject"; "approval"; "merge"; "report" ]
  | "abandoned" -> Some [ "subject"; "reason" ]
  | "void" -> Some [ "dropped"; "reason" ]
  | _ -> None

let scope_keys = [ "step"; "glob" ]
let promise_keys = [ "step"; "word"; "target" ]
let text = function Json.String s -> Some s | _ -> None
let positive = function Json.Int i when i >= 1 -> Some i | _ -> None
let checked test = function Json.String s when test s -> Some s | _ -> None

let optional members name check =
  match List.assoc_opt name members with
  | None -> None
  | Some value -> (
      match check value with
      | Some found -> Some found
      | None -> raise (Line_fault (Wrong_type name)))

let required members name check =
  match List.assoc_opt name members with
  | None -> raise (Line_fault (Missing_field name))
  | Some value -> (
      match check value with
      | Some found -> found
      | None -> raise (Line_fault (Wrong_type name)))

let objects keys item = function
  | Json.Array values ->
      List.fold_right
        (fun value found ->
          match (value, found) with
          | Json.Object fields, Some (items, extra) ->
              Option.map
                (fun item ->
                  ( item :: items,
                    extra
                    + List.length
                        (List.filter
                           (fun (key, _) -> not (List.mem key keys))
                           fields) ))
                (item fields)
          | _ -> None)
        values
        (Some ([], 0))
  | _ -> None

module Names = Map.Make (String)

let set_limit = 1_048_576

let csh_holds csh scopes promises =
  let add key value map =
    Names.update key
      (fun found -> Some (value :: Option.value found ~default:[]))
      map
  in
  let plan_scope, own =
    List.fold_left
      (fun (plan_scope, own) (scope : scope) ->
        match scope.step with
        | None -> (scope.glob :: plan_scope, own)
        | Some step -> (plan_scope, add step scope.glob own))
      ([], Names.empty) scopes
  in
  let inherited, owned =
    List.fold_left
      (fun (inherited, owned) (promise : promise) ->
        let pair = (promise.word, promise.target) in
        if Names.mem promise.step own then
          (inherited, add promise.step pair owned)
        else (pair :: inherited, owned))
      ([], Names.empty) promises
  in
  let steps =
    { Commitment_set.scope = plan_scope; promises = inherited }
    :: Names.fold
         (fun step globs steps ->
           {
             Commitment_set.scope = globs;
             promises = Option.value (Names.find_opt step owned) ~default:[];
           }
           :: steps)
         own []
  in
  Commitment_set.size ~scope:plan_scope steps <= set_limit
  && String.equal csh (Commitment_set.hash ~scope:plan_scope steps)

let body format kind members =
  let req name check = required members name check
  and opt name check = optional members name check in
  let hash = checked is_hash and entry_id = checked is_entry_id in
  let commit = checked (is_commit format) in
  match kind with
  | "approval" ->
      let subject = req "subject" text in
      let rev = opt "rev" positive in
      let xh = opt "xh" hash in
      let csh = opt "csh" hash in
      let note = opt "note" text in
      let approved =
        match (rev, xh, csh) with
        | Some rev, Some xh, None -> Text { rev; xh }
        | None, None, Some csh -> Commitment csh
        | _ -> raise (Line_fault Approval_hashes)
      in
      (Approval { subject; approved; note }, 0)
  | "commitment-set" ->
      let csh = req "csh" hash in
      let scopes, scope_extra =
        req "scopes"
          (objects scope_keys (fun fields ->
               let glob = List.assoc_opt "glob" fields
               and step = List.assoc_opt "step" fields in
               match (glob, step) with
               | Some (Json.String glob), (None | Some (Json.String _)) ->
                   Some { step = Option.bind step text; glob }
               | _ -> None))
      in
      let promises, promise_extra =
        req "promises"
          (objects promise_keys (fun fields ->
               match
                 ( List.assoc_opt "step" fields,
                   List.assoc_opt "word" fields,
                   List.assoc_opt "target" fields )
               with
               | ( Some (Json.String step),
                   Some (Json.String word),
                   Some (Json.String target) ) ->
                   Some { step; word; target }
               | _ -> None))
      in
      ( Commitment_set
          { csh; scopes; promises; csh_holds = csh_holds csh scopes promises },
        scope_extra + promise_extra )
  | "decline" ->
      let subject = req "subject" text in
      let hash = req "hash" hash in
      let reason = req "reason" text in
      (Decline { subject; hash; reason }, 0)
  | "delivered" ->
      let subject = req "subject" text in
      let csh = req "csh" hash in
      let merge = req "merge" commit in
      (Delivered { subject; csh; merge }, 0)
  | "completed" ->
      let subject = req "subject" text in
      let approval = opt "approval" entry_id in
      let merge = req "merge" commit in
      let report = req "report" hash in
      (Completed { subject; approval; merge; report }, 0)
  | "abandoned" ->
      let subject = req "subject" text in
      let reason = req "reason" text in
      (Abandoned { subject; reason }, 0)
  | _ ->
      let dropped = req "dropped" entry_id in
      let reason = req "reason" text in
      (Void { dropped; reason }, 0)

let read_line format line =
  match Yojson.Safe.from_string line with
  | exception Yojson.Json_error _ ->
      Error (Fault { id = None; fault = Not_json })
  | `Assoc raw -> (
      let newer =
        match List.filter (fun (key, _) -> String.equal key "v") raw with
        | [ (_, `Int v) ] when v > version -> Some v
        | _ -> None
      in
      match newer with
      | Some v -> Error (Too_new v)
      | None -> (
          let id =
            List.find_map (function "id", `String s -> Some s | _ -> None) raw
          in
          try
            let members =
              List.map (fun (key, raw) -> (key, value key raw)) raw
            in
            if not (String.equal (printed (Json.Object members)) line) then
              raise (Line_fault Not_canonical);
            let id = required members "id" text in
            let kind = required members "kind" text in
            let v = required members "v" positive in
            let seq = required members "seq" positive in
            let without =
              printed
                (Json.Object
                   (List.filter
                      (fun (key, _) -> not (String.equal key "id"))
                      members))
            in
            let own = hash_id without in
            if not (String.equal own id) then raise (Line_fault (Wrong_id own));
            match kind_fields kind with
            | None -> Ok (Unknown { id; kind; seq })
            | Some fields ->
                let req name check = required members name check in
                let by = req "by" text in
                let ts = req "ts" (checked is_ts) in
                let head = req "head" (checked (is_commit format)) in
                let branch = optional members "branch" text in
                let tool = req "tool" text in
                let body, inner_unknown = body format kind members in
                let unknown_fields =
                  List.length
                    (List.filter
                       (fun (key, _) ->
                         not (List.mem key common_fields || List.mem key fields))
                       members)
                  + inner_unknown
                in
                Ok
                  (Known
                     {
                       entry =
                         { id; v; seq; by; ts; head; branch; tool; body; line };
                       unknown_fields;
                     })
          with Line_fault fault -> Error (Fault { id; fault })))
  | _ -> Error (Fault { id = None; fault = Not_an_object })

type fault =
  | Not_a_commit of Git.Decode.kind
  | Bad_commit of string
  | Merge_commit of int
  | Parent_not_a_commit of { parent : string; kind : Git.Decode.kind }
  | Bad_tree of string
  | Wrong_object of Git.Decode.kind
  | Wrong_path of { mode : int }
  | Unordered_tree
  | Empty_folder
  | Empty_chunk
  | No_line_feed
  | Wrong_name of string
  | Bad_line of line_fault
  | Repeated_id
  | Repeated_seq of int
  | Missing_seq of { seq : int; count : int }
  | Dropped of { parent : string }

type broken = {
  commit : string;
  path : string option;
  line : int option;
  entry : string option;
  fault : fault;
}

type error =
  | Repository of Git.error
  | Broken of broken
  | Newer of { commit : string; path : string; line : int; version : int }
  | Missing_parent of { commit : string; parent : string }
  | Missing_object of { commit : string; id : string }

let kind_word = function
  | Git.Decode.Blob -> "a blob"
  | Git.Decode.Tree -> "a tree"
  | Git.Decode.Commit -> "a commit"
  | Git.Decode.Tag -> "a tag"

let quoted text = "'" ^ Display.clean text ^ "'"

let line_text = function
  | Not_json -> "is not JSON"
  | Not_an_object -> "is not a JSON object"
  | Bad_value key ->
      Printf.sprintf "holds a value that a ledger does not allow in %s"
        (quoted key)
  | Repeated_key key -> Printf.sprintf "holds the key %s twice" (quoted key)
  | Not_utf_8 -> "holds a string that is not valid UTF-8"
  | Not_canonical -> "is not in the canonical form"
  | Missing_field key -> Printf.sprintf "has no field %s" (quoted key)
  | Wrong_type key ->
      Printf.sprintf "has a value of the wrong type in %s" (quoted key)
  | Wrong_id id -> Printf.sprintf "does not have its own id, %s" id
  | Approval_hashes ->
      "is an approval that holds neither rev and xh nor csh, or both"

let place ~commit ~path ~line =
  let path = Option.map Display.clean path in
  match (path, line) with
  | Some path, Some line ->
      Printf.sprintf "the line %d of %s in the commit %s" line path commit
  | Some path, None -> Printf.sprintf "%s in the commit %s" path commit
  | None, _ -> Printf.sprintf "the tree of the commit %s" commit

let broken_text { commit; path; line; entry; fault } =
  let here = place ~commit ~path ~line in
  let entry_note =
    match entry with
    | Some id -> Printf.sprintf " (the entry %s)" (Display.clean id)
    | None -> ""
  in
  match fault with
  | Not_a_commit kind ->
      Printf.sprintf "the ref %s names %s, %s, and not a commit" ref_name
        (kind_word kind) commit
  | Bad_commit detail ->
      Printf.sprintf "the commit %s does not decode: %s" commit
        (Display.clean detail)
  | Merge_commit count ->
      Printf.sprintf "the commit %s is a merge commit with %d parents" commit
        count
  | Parent_not_a_commit { parent; kind } ->
      Printf.sprintf "the parent %s of the commit %s is %s, and not a commit"
        parent commit (kind_word kind)
  | Bad_tree detail ->
      Printf.sprintf "%s does not decode: %s" here (Display.clean detail)
  | Wrong_object kind -> Printf.sprintf "%s is %s" here (kind_word kind)
  | Wrong_path { mode } ->
      Printf.sprintf "%s has the mode %o, and is no folder or chunk of a ledger"
        here mode
  | Unordered_tree ->
      Printf.sprintf "%s holds its names out of order, or a name twice" here
  | Empty_folder -> Printf.sprintf "%s is an empty folder" here
  | Empty_chunk -> Printf.sprintf "%s is an empty chunk" here
  | No_line_feed -> Printf.sprintf "%s does not end with a line feed" here
  | Wrong_name id ->
      Printf.sprintf "%s does not have the name of its first entry, %s" here id
  | Bad_line fault -> Printf.sprintf "%s %s%s" here (line_text fault) entry_note
  | Repeated_id -> Printf.sprintf "%s repeats an earlier id%s" here entry_note
  | Repeated_seq seq ->
      Printf.sprintf "%s repeats the seq %d of an earlier entry%s" here seq
        entry_note
  | Missing_seq { seq; count } ->
      Printf.sprintf "the commit %s holds %s and no entry with the seq %d"
        commit
        (if count = 1 then "1 entry" else Printf.sprintf "%d entries" count)
        seq
  | Dropped { parent } ->
      Printf.sprintf "the commit %s drops the entry%s that %s holds" commit
        (match entry with Some id -> " " ^ Display.clean id | None -> "")
        (place ~commit:parent ~path ~line)

let explain error =
  let make fault help = { Error_text.fault; help; place = None } in
  match error with
  | Repository error -> Error_text.of_git error
  | Broken broken ->
      make
        ("the ledger is broken: " ^ broken_text broken)
        "repair the ledger with sinter ledger repair"
  | Newer { commit; path; line; version = newer } ->
      make
        (Printf.sprintf
           "%s holds an entry of version %d, and this sinter reads version %d"
           (place ~commit ~path:(Some path) ~line:(Some line))
           newer version)
        "upgrade sinter to a version that reads the ledger"
  | Missing_parent { commit; parent } ->
      make
        (Printf.sprintf
           "the clone does not hold the commit %s of the ledger, the parent of \
            %s"
           parent commit)
        "fetch the whole history of the ledger with git fetch \
         --depth=2147483647 --no-filter origin refs/sinter/ledger"
  | Missing_object { commit; id } ->
      make
        (Printf.sprintf
           "the clone does not hold the object %s of the ledger, in the commit \
            %s"
           id commit)
        "fetch every object of the ledger with git fetch --refetch --no-filter \
         origin refs/sinter/ledger"

type work = { waits : int; listings : int; lines : int; matches : int }

type t = {
  tip_commit : string;
  known : entry list;
  checked : int;
  unknown_kinds : int;
  unknown_fields : int;
  done_work : work;
}

type depth = Tip | History

let tip t = t.tip_commit
let entries t = t.known
let commits t = t.checked
let work t = t.done_work
let unknown t = (t.unknown_kinds, t.unknown_fields)

let warning t =
  let count n one many =
    Printf.sprintf "%d %s" n (if n = 1 then one else many)
  in
  match
    List.filter_map Fun.id
      [
        (if t.unknown_kinds = 0 then None
         else
           Some
             (count t.unknown_kinds "entry of an unknown kind"
                "entries of an unknown kind"));
        (if t.unknown_fields = 0 then None
         else Some (count t.unknown_fields "unknown field" "unknown fields"));
      ]
  with
  | [] -> None
  | parts ->
      Some
        (Printf.sprintf "the ledger holds %s; sinter ignores %s"
           (String.concat " and " parts)
           (if t.unknown_kinds + t.unknown_fields = 1 then "it" else "them"))

exception Stop of error

let stop error = raise (Stop error)

let broken ?path ?line ?entry commit fault =
  stop (Broken { commit; path; line; entry; fault })

type folder = { tree : string; chunks : string Names.t }

type snapshot = {
  commit : string;
  root : string;
  listing : (string * string) option;
  folders : folder Names.t;
  count : int;
}

type chunk = { blob : string; lines : (string * int * string) array }

type place = {
  id : string;
  seq : int;
  folder : string;
  name : string;
  blob : string;
}

type state = {
  objects : Git.objects;
  format : Git.object_format;
  index : (string, place) Hashtbl.t;
  ids : (string, unit) Hashtbl.t;
  seqs : (int, unit) Hashtbl.t;
  paths : (string, chunk) Hashtbl.t;
  contents : (string, string) Hashtbl.t;
  cache : (string, Git.found) Hashtbl.t;
  mutable listings : int;
  mutable lines : int;
  mutable matches : int;
}

let table () =
  Hashtbl.create ~random:true 64
  [@mutaml.skip
    "the seed and the first size change only the time of a lookup on keys that \
     collide, and never its result; no test measures that time"]

let lookup state id =
  match Hashtbl.find_opt state.cache id with
  | Some found ->
      (Hashtbl.remove state.cache id;
       Ok found)
      [@mutaml.skip
        "an object of the cache is the object of its id, so an object that \
         stays gives the same answer to every later read; only the memory of \
         the cache changes"]
  | None -> Git.read_object state.objects id

let prefetch state ids =
  let wanted =
    List.sort_uniq String.compare (List.filter (is_commit state.format) ids)
  in
  match Git.read_objects state.objects wanted with
  | Ok found -> List.iter2 (Hashtbl.replace state.cache) wanted found
  | Error _ -> ()

let peek_records state id =
  match Hashtbl.find_opt state.cache id with
  | Some (Git.Found { kind = Git.Decode.Tree; content }) -> (
      match Git.Decode.tree_object state.format content with
      | Ok records -> Some records
      | Error _ -> None)
  | Some _ | None -> None

let peek_content state id =
  match Hashtbl.find_opt state.cache id with
  | Some (Git.Found { kind = Git.Decode.Tree; content }) -> Some content
  | Some _ | None -> None

let fetch state ~commit id =
  match lookup state id with
  | Error error -> stop (Repository error)
  | Ok Git.Absent -> stop (Missing_object { commit; id })
  | Ok (Git.Found { kind; content }) -> (kind, content)

let tree_content state ~commit ?path id =
  match fetch state ~commit id with
  | Git.Decode.Tree, content -> content
  | kind, _ -> broken ?path commit (Wrong_object kind)

let decode_tree state ~commit ?path ~valid content =
  match Git.Decode.tree_object state.format content with
  | Ok records ->
      List.iter
        (fun ({ mode; name; _ } : Git.Decode.tree_record) ->
          if not (valid ~mode name) then
            broken
              ~path:
                (match path with
                | Some path -> path ^ "/" ^ name
                | None -> name)
              commit
              (Wrong_path { mode }))
        records;
      let rec ordered = function
        | (a : Git.Decode.tree_record) :: (b :: _ as rest) ->
            String.compare a.name b.name < 0 && ordered rest
        | [ _ ] | [] -> true
      in
      if ordered records then records else broken ?path commit Unordered_tree
  | Error detail -> broken ?path commit (Bad_tree detail)

let fetch_tree state ~commit ?path ~valid id =
  decode_tree state ~commit ?path ~valid (tree_content state ~commit ?path id)

let tree_mode = 0o40000
let chunk_mode = 0o100644
let is_folder_name name = String.length name = 2 && is_lower_hex name

let is_chunk_name ~folder name =
  String.length name = 20
  && String.starts_with ~prefix:"e-" name
  && String.ends_with ~suffix:".jsonl" name
  && is_lower_hex (String.sub name 2 12)
  && String.equal (String.sub name 2 2) folder

let read_root state ~commit root =
  match
    fetch_tree state ~commit
      ~valid:(fun ~mode name -> mode = tree_mode && String.equal name "entries")
      root
  with
  | [ { id; _ } ] -> Some id
  | _ -> None

let listing_folders state ~commit content =
  state.listings <- state.listings + 1;
  match
    decode_tree state ~commit ~path:"entries"
      ~valid:(fun ~mode name -> mode = tree_mode && is_folder_name name)
      content
  with
  | [] -> broken ~path:"entries" commit Empty_folder
  | records ->
      List.fold_left
        (fun folders ({ name; id; _ } : Git.Decode.tree_record) ->
          Names.add name id folders)
        Names.empty records

let hex_digits = "0123456789abcdef"

let hex_of text start length =
  String.init (2 * length) (fun i ->
      let byte = Char.code text.[start + (i / 2)] in
      hex_digits.[if i land 1 = 0 then byte lsr 4 else byte land 15])

let id_bytes = function Git.Sha1 -> 20 | Git.Sha256 -> 32

let rec same_bytes a b at stop =
  let word = at + 8 in
  if
    (word <= stop)
    [@mutaml.skip
      "the word step and the byte step compare the same bytes, so a word that \
       ends at stop gives the same answer by either step"]
  then
    Int64.equal (String.get_int64_ne a at) (String.get_int64_ne b at)
    && same_bytes a b word stop
  else if at < stop then a.[at] = b.[at] && same_bytes a b (at + 1) stop
  else true

let listing_changes format previous current =
  let size = 9 + id_bytes format in
  let length = String.length current in
  let piece text at width = String.sub text at width in
  let rec slots at changes =
    if at >= length then Some (List.rev changes)
    else if same_bytes previous current at (at + size) then
      slots (at + size) changes
    else if not (String.equal (piece previous at 9) (piece current at 9)) then
      None
    else
      slots (at + size)
        ((String.sub current (at + 6) 2, hex_of current (at + 9) (size - 9))
        :: changes)
  in
  if length <> String.length previous || length mod size <> 0 then None
  else slots 0 []

let read_folder state ~commit name id =
  let path = "entries/" ^ name in
  match
    fetch_tree state ~commit ~path
      ~valid:(fun ~mode chunk ->
        mode = chunk_mode && is_chunk_name ~folder:name chunk)
      id
  with
  | [] -> broken ~path commit Empty_folder
  | records ->
      List.fold_left
        (fun chunks ({ name = chunk; id; _ } : Git.Decode.tree_record) ->
          Names.add chunk id chunks)
        Names.empty records

let read_chunk state ~commit ~path blob =
  match fetch state ~commit blob with
  | Git.Decode.Blob, "" -> broken ~path commit Empty_chunk
  | Git.Decode.Blob, content ->
      if content.[String.length content - 1] <> '\n' then
        broken ~path commit No_line_feed
      else content
  | kind, _ -> broken ~path commit (Wrong_object kind)

let lines content =
  match List.rev (String.split_on_char '\n' content) with
  | "" :: rest -> List.rev rest
  | all -> List.rev all

let check_line state ~commit ~path number line =
  state.lines <- state.lines + 1;
  match read_line state.format line with
  | Ok read -> read
  | Error (Too_new version) ->
      stop (Newer { commit; path; line = number; version })
  | Error (Fault { id; fault }) ->
      broken ~path ~line:number ?entry:id commit (Bad_line fault)

let id_of_read = function
  | Known { entry; _ } -> entry.id
  | Unknown { id; _ } -> id

let seq_of_read = function
  | Known { entry; _ } -> entry.seq
  | Unknown { seq; _ } -> seq

let rec least_missing seqs seq =
  if Hashtbl.mem seqs seq then least_missing seqs (seq + 1) else seq

let check_name ~commit ~path ~name id =
  if not (String.equal name (id ^ ".jsonl")) then
    broken ~path commit (Wrong_name id)

let chunk_path folder name = "entries/" ^ folder ^ "/" ^ name

type counts = {
  mutable known : entry list;
  mutable unknown_kinds : int;
  mutable unknown_fields : int;
}

let read_snapshot state counts ~commit ~root =
  let listing =
    Option.map
      (fun id -> (id, tree_content state ~commit ~path:"entries" id))
      (read_root state ~commit root)
  in
  let folders =
    match listing with
    | None -> Names.empty
    | Some (_, content) ->
        let listed = listing_folders state ~commit content in
        Names.mapi
          (fun name tree ->
            let chunks = read_folder state ~commit name tree in
            Names.iter
              (fun chunk blob ->
                let path = chunk_path name chunk in
                let content = read_chunk state ~commit ~path blob in
                let read_lines =
                  List.mapi
                    (fun index line ->
                      let number = index + 1 in
                      let read = check_line state ~commit ~path number line in
                      let id = id_of_read read in
                      if number = 1 then check_name ~commit ~path ~name:chunk id;
                      if Hashtbl.mem state.ids id then
                        broken ~path ~line:number ~entry:id commit Repeated_id;
                      Hashtbl.replace state.ids id ();
                      let seq = seq_of_read read in
                      if Hashtbl.mem state.seqs seq then
                        broken ~path ~line:number ~entry:id commit
                          (Repeated_seq seq);
                      Hashtbl.replace state.seqs seq ();
                      Hashtbl.replace state.index line
                        { id; seq; folder = name; name = chunk; blob };
                      (match read with
                      | Known { entry; unknown_fields } ->
                          counts.known <- entry :: counts.known;
                          counts.unknown_fields <-
                            counts.unknown_fields + unknown_fields
                      | Unknown _ ->
                          counts.unknown_kinds <- counts.unknown_kinds + 1);
                      (id, seq, line))
                    (lines content)
                in
                let lines = Array.of_list read_lines in
                Hashtbl.replace state.paths path { blob; lines };
                if Array.length lines < chunk_size then
                  Hashtbl.replace state.contents blob content)
              chunks;
            { tree; chunks })
          listed
  in
  let count = Hashtbl.length state.seqs in
  (match least_missing state.seqs 1 with
  | seq when seq <= count -> broken commit (Missing_seq { seq; count })
  | _ -> ());
  { commit; root; listing; folders; count }

let decode_commit state ~commit content =
  match Git.Decode.commit_object content with
  | Ok header ->
      if List.for_all (is_commit state.format) (header.tree :: header.parents)
      then header
      else
        broken commit
          (Bad_commit "an id does not have the length of the object format")
  | Error detail -> broken commit (Bad_commit detail)

let check_parents ~commit (header : Git.Decode.commit_object) =
  match header.parents with
  | [] | [ _ ] -> ()
  | parents -> broken commit (Merge_commit (List.length parents))

let content_of state ~commit blob =
  match Hashtbl.find_opt state.contents blob with
  | Some content -> content
  | None -> snd (fetch state ~commit blob)

let is_prefix prefix text =
  let length = String.length prefix in
  (length < String.length text)
  [@mutaml.skip
    "the one caller gives as text a chunk of the child, which passed its \
     checks, and as prefix another content at its path; a text that holds the \
     prefix holds at least one whole line more, of 3 bytes or more, so each \
     bound from length - 1 to length + 1 gives the same answer"]
  && String.equal prefix (String.sub text 0 length)

let rec count_lines text from count =
  match String.index_from_opt text from '\n' with
  | Some at -> count_lines text (at + 1) (count + 1)
  | None -> count

let parent_chunk state (child : snapshot) ~commit ~folder ~chunk ~fresh ~shared
    blob =
  let path = chunk_path folder chunk in
  let content = read_chunk state ~commit ~path blob in
  let note number id =
    if Hashtbl.mem fresh id then
      broken ~path ~line:number ~entry:id commit Repeated_id;
    Hashtbl.replace fresh id ()
  in
  let prefix =
    match Hashtbl.find_opt state.paths path with
    | Some held
      when is_prefix content (content_of state ~commit:child.commit held.blob)
      ->
        Some
          ( held,
            count_lines content
              (0
              [@mutaml.skip
                "the content is a prefix of a chunk that passed its checks, so \
                 its first byte is the { of a line and no line feed; a count \
                 from 0 and a count from 1 find the same line feeds"])
              0 )
    | Some _ | None -> None
  in
  let read_lines =
    match prefix with
    | Some (held, count) ->
        List.init count (fun index ->
            let ((id, _, _) as held_line) = held.lines.(index) in
            note (index + 1) id;
            held_line)
    | None ->
        List.mapi
          (fun index line ->
            let number = index + 1 in
            state.matches <- state.matches + 1;
            match Hashtbl.find_opt state.index line with
            | None ->
                let id =
                  id_of_read (check_line state ~commit ~path number line)
                in
                if number = 1 then check_name ~commit ~path ~name:chunk id;
                broken ~path ~line:number ~entry:id child.commit
                  (Dropped { parent = commit })
            | Some place ->
                let id = place.id in
                if number = 1 then check_name ~commit ~path ~name:chunk id;
                note number id;
                if shared place then
                  broken ~path ~line:number ~entry:id commit Repeated_id;
                (id, place.seq, line))
          (lines content)
  in
  (content, Array.of_list read_lines)

let folder_changes state (child : snapshot) ~commit listing =
  let held = Names.map (fun (folder : folder) -> folder.tree) child.folders in
  let versus listed =
    Names.merge
      (fun _ before after ->
        match (before, after) with
        | Some before, Some after when String.equal before after -> None
        | _, Some after -> Some (Some after)
        | Some _, None -> Some None
        | None, None -> None)
      held listed
  in
  match (listing, child.listing) with
  | None, _ -> versus Names.empty
  | Some (_, content), Some (_, before) -> (
      match listing_changes state.format before content with
      | Some changes ->
          List.fold_left
            (fun map (name, id) -> Names.add name (Some id) map)
            Names.empty changes
      | None -> versus (listing_folders state ~commit content))
  | Some (_, content), None -> versus (listing_folders state ~commit content)

let walk_parent state (child : snapshot) ~commit ~root listing =
  let listing =
    Option.map
      (fun id -> (id, tree_content state ~commit ~path:"entries" id))
      listing
  in
  let changes = folder_changes state child ~commit listing in
  let decoded = table () in
  let chunks_of name =
    match Names.find_opt name changes with
    | Some None -> None
    | None ->
        Option.map
          (fun (folder : folder) -> folder.chunks)
          (Names.find_opt name child.folders)
    | Some (Some tree) -> (
        match Hashtbl.find_opt decoded name with
        | Some chunks -> chunks
        | None ->
            let chunks =
              match read_folder state ~commit name tree with
              | chunks -> Some chunks
              | exception Stop (Broken _) -> None
            in
            Hashtbl.replace decoded name chunks;
            chunks)
  in
  let shared (place : place) =
    match Option.bind (chunks_of place.folder) (Names.find_opt place.name) with
    | Some blob -> String.equal blob place.blob
    | None -> false
  in
  let fresh = table () in
  let added = ref [] in
  let held name =
    match Names.find_opt name child.folders with
    | Some folder -> folder.chunks
    | None -> Names.empty
  in
  let folders =
    Names.fold
      (fun name change folders ->
        match change with
        | None -> Names.remove name folders
        | Some tree ->
            let chunks =
              match Hashtbl.find_opt decoded name with
              | Some (Some chunks) -> chunks
              | Some None | None -> read_folder state ~commit name tree
            in
            Hashtbl.replace decoded name (Some chunks);
            let before = held name in
            Names.iter
              (fun chunk blob ->
                match Names.find_opt chunk before with
                | Some same when String.equal same blob -> ()
                | Some _ | None ->
                    let content, lines =
                      parent_chunk state child ~commit ~folder:name ~chunk
                        ~fresh ~shared blob
                    in
                    added := (name, chunk, blob, content, lines) :: !added)
              chunks;
            Names.add name { tree; chunks } folders)
      changes child.folders
  in
  let unmatched = ref [] in
  Names.iter
    (fun name _ ->
      let kept =
        match Names.find_opt name folders with
        | Some folder -> folder.chunks
        | None -> Names.empty
      in
      Names.iter
        (fun chunk blob ->
          match Names.find_opt chunk kept with
          | Some same when String.equal same blob -> ()
          | Some _ | None -> (
              let path = chunk_path name chunk in
              match Hashtbl.find_opt state.paths path with
              | Some held ->
                  Array.iter
                    (fun (id, seq, line) ->
                      if not (Hashtbl.mem fresh id) then
                        unmatched := seq :: !unmatched;
                      Hashtbl.remove state.index line)
                    held.lines;
                  Hashtbl.remove state.paths path;
                  Hashtbl.remove state.contents held.blob
              | None -> ()))
        (held name))
    changes;
  let count = child.count - List.length !unmatched in
  (match List.sort Int.compare !unmatched with
  | seq :: _ when seq <= count -> broken commit (Missing_seq { seq; count })
  | _ -> ());
  List.iter
    (fun (folder, name, blob, content, lines) ->
      Array.iter
        (fun (id, seq, line) ->
          Hashtbl.replace state.index line { id; seq; folder; name; blob })
        lines;
      Hashtbl.replace state.paths (chunk_path folder name) { blob; lines };
      Hashtbl.replace state.contents blob content)
    !added;
  { commit; root; listing; folders; count }

let step state (child : snapshot) parent =
  let header =
    match lookup state parent with
    | Error error -> stop (Repository error)
    | Ok Git.Absent -> stop (Missing_parent { commit = child.commit; parent })
    | Ok (Git.Found { kind = Git.Decode.Commit; content }) ->
        decode_commit state ~commit:parent content
    | Ok (Git.Found { kind; _ }) ->
        broken child.commit (Parent_not_a_commit { parent; kind })
  in
  let commit = parent in
  let snapshot =
    if String.equal header.tree child.root then { child with commit }
    else
      let listing = read_root state ~commit header.tree in
      if Option.equal String.equal listing (Option.map fst child.listing) then
        { child with commit; root = header.tree }
      else walk_parent state child ~commit ~root:header.tree listing
  in
  (snapshot, header)

let window = 193

let prefetch_window state (child : snapshot) parent =
  let rec chain id count roots =
    if count >= window || Hashtbl.mem state.cache id then List.rev roots
    else
      match Git.read_object state.objects id with
      | Ok (Git.Found { kind = Git.Decode.Commit; content } as found) -> (
          Hashtbl.replace state.cache id found;
          match Git.Decode.commit_object content with
          | Ok { tree; parents = [ next ] } when is_commit state.format next ->
              chain next (count + 1) (tree :: roots)
          | Ok { tree; _ } -> List.rev (tree :: roots)
          | Error _ -> List.rev roots)
      | Ok _ | Error _ -> List.rev roots
  in
  let roots = chain parent 0 [] in
  let changed first items =
    List.rev
      (snd
         (List.fold_left
            (fun (previous, ids) item ->
              (item, if String.equal previous item then ids else item :: ids))
            (first, []) items))
  in
  prefetch state (changed child.root roots);
  let listings =
    List.rev
      (snd
         (List.fold_left
            (fun ((previous_root, previous), listings) root ->
              let listing =
                if String.equal previous_root root then previous
                else
                  match peek_records state root with
                  | Some [ { mode; name = "entries"; id } ]
                    when mode = tree_mode ->
                      Some id
                  | Some _ | None -> None
              in
              ((root, listing), listing :: listings))
            ((child.root, Option.map fst child.listing), [])
            roots))
  in
  prefetch state
    (List.filter_map Fun.id
       (snd
          (List.fold_left
             (fun (previous, ids) listing ->
               ( listing,
                 if Option.equal String.equal previous listing then ids
                 else listing :: ids ))
             (Option.map fst child.listing, [])
             listings)));
  let start =
    ( Option.map snd child.listing,
      Names.map (fun (folder : folder) -> folder.tree) child.folders )
  in
  let _, folder_ids =
    List.fold_left
      (fun ((previous_content, previous_folders), changes) listing ->
        match Option.bind listing (peek_content state) with
        | None -> ((previous_content, previous_folders), changes)
        | Some content ->
            let found =
              match
                Option.bind previous_content (fun before ->
                    listing_changes state.format before content)
              with
              | Some found -> found
              | None -> (
                  match Git.Decode.tree_object state.format content with
                  | Ok records ->
                      List.filter_map
                        (fun (record : Git.Decode.tree_record) ->
                          match Names.find_opt record.name previous_folders with
                          | Some same when String.equal same record.id -> None
                          | Some _ | None -> Some (record.name, record.id))
                        records
                  | Error _ -> [])
            in
            let folders =
              List.fold_left
                (fun map (name, id) -> Names.add name id map)
                previous_folders found
            in
            ( ( (Some content
                [@mutaml.skip
                  "the content only lets the read-ahead diff the next listing \
                   with this one; without it the read-ahead decodes the next \
                   listing in full and finds the same changed folders, so it \
                   reads the same objects"]),
                folders ),
              found :: changes ))
      (start, []) listings
  in
  let folder_ids = List.rev folder_ids in
  prefetch state (List.concat_map (List.map snd) folder_ids);
  let _, blobs =
    List.fold_left
      (fun (chunk_maps, blobs) found ->
        List.fold_left
          (fun (chunk_maps, blobs) (name, tree) ->
            let map =
              List.fold_left
                (fun map (record : Git.Decode.tree_record) ->
                  Names.add record.name record.id map)
                Names.empty
                (Option.value (peek_records state tree) ~default:[])
            in
            let before =
              Option.value (Names.find_opt name chunk_maps) ~default:Names.empty
            in
            ( Names.add name map chunk_maps,
              Names.fold
                (fun chunk blob blobs ->
                  match Names.find_opt chunk before with
                  | Some same when String.equal same blob -> blobs
                  | Some _ | None -> blob :: blobs)
                map blobs ))
          (chunk_maps, blobs) found)
      (Names.map (fun (folder : folder) -> folder.chunks) child.folders, [])
      folder_ids
  in
  prefetch state blobs

let read repo depth =
  match Git.ref_target repo ref_name with
  | Error error -> Error (Repository error)
  | Ok None -> Ok None
  | Ok (Some tip_commit) -> (
      let result =
        Git.with_objects repo (fun objects ->
            let state =
              {
                objects;
                format = Git.object_format repo;
                index = table ();
                ids = table ();
                seqs = table ();
                paths = table ();
                contents = table ();
                cache = table ();
                listings = 0;
                lines = 0;
                matches = 0;
              }
            in
            let counts =
              { known = []; unknown_kinds = 0; unknown_fields = 0 }
            in
            match
              let header =
                match fetch state ~commit:tip_commit tip_commit with
                | Git.Decode.Commit, content ->
                    decode_commit state ~commit:tip_commit content
                | kind, _ -> broken tip_commit (Not_a_commit kind)
              in
              let snapshot =
                read_snapshot state counts ~commit:tip_commit ~root:header.tree
              in
              let checked =
                match depth with
                | Tip -> 1
                | History ->
                    let rec walk snapshot (header : Git.Decode.commit_object)
                        count =
                      check_parents ~commit:snapshot.commit header;
                      match header.parents with
                      | [] -> count
                      | parent :: _ ->
                          if not (Hashtbl.mem state.cache parent) then
                            prefetch_window state snapshot parent;
                          let snapshot, header = step state snapshot parent in
                          walk snapshot header (count + 1)
                    in
                    walk snapshot header 1
              in
              {
                tip_commit;
                known = List.sort compare counts.known;
                checked;
                unknown_kinds = counts.unknown_kinds;
                unknown_fields = counts.unknown_fields;
                done_work =
                  {
                    waits = Git.waits objects;
                    listings = state.listings;
                    lines = state.lines;
                    matches = state.matches;
                  };
              }
            with
            | ledger -> Ok (Ok (Some ledger))
            | exception Stop error -> Ok (Error error))
      in
      match result with
      | Error error -> Error (Repository error)
      | Ok read -> read)

let finding (fault : broken) =
  Finding.make Finding_class.Ledger_broken (Finding.Ledger_commit fault.commit)
    ~detail:(broken_text fault) ()

let summary (t : t) =
  let count n one many =
    Printf.sprintf "%d %s" n (if n = 1 then one else many)
  in
  Printf.sprintf "the ledger passes verification: %s in %s"
    (count (List.length t.known + t.unknown_kinds) "entry" "entries")
    (count t.checked "commit" "commits")

let log_line (entry : entry) =
  let what =
    match entry.body with
    | Commitment_set { csh; _ } -> csh
    | Void { dropped; _ } -> dropped
    | Approval { subject; _ }
    | Decline { subject; _ }
    | Delivered { subject; _ }
    | Completed { subject; _ }
    | Abandoned { subject; _ } ->
        subject
  in
  String.concat " "
    (string_of_int entry.seq
    :: List.map Display.clean
         [ entry.ts; entry.id; kind_name entry.body; what; entry.by ])
