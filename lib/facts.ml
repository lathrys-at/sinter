(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

let declaration_words = [ "req"; "design"; "decision" ]

let citation_words =
  [ "satisfies"; "verifies"; "refines"; "cites"; "supersedes" ]

let promise_words = declaration_words @ citation_words

(* The kinds of declaration that a status word applies to. *)
let status_kinds = function
  | "deprecated" -> declaration_words
  | "rejected" | "deferred" -> [ "decision" ]
  | _ -> []

let manifest_kind = function
  | "req" -> Some Manifest.Req
  | "design" -> Some Manifest.Design
  | "decision" -> Some Manifest.Decision
  | _ -> None

let is_blank = function ' ' | '\t' -> true | _ -> false

let trim text =
  let length = String.length text in
  let rec first index =
    if index < length && is_blank text.[index] then first (index + 1) else index
  in
  let rec last index =
    if index > 0 && is_blank text.[index - 1] then last (index - 1) else index
  in
  let start = first 0 in
  let stop = last length in
  if stop <= start then "" else String.sub text start (stop - start)

(* The tokens of [text], each with its byte offset: the runs of
   characters that are neither a space nor a tab. *)
let tokens text =
  let length = String.length text in
  let rec skip index found =
    if index >= length then List.rev found
    else if is_blank text.[index] then skip (index + 1) found
    else take index index found
  and take start index found =
    if index < length && not (is_blank text.[index]) then
      take start (index + 1) found
    else skip index ((start, String.sub text start (index - start)) :: found)
  in
  skip 0 []

(* The globs of the text after a [@scope] word: the parts between
   commas, without the spaces and tabs at their ends, empty parts left
   out. *)
let globs rest =
  List.filter
    (fun glob -> not (String.equal glob ""))
    (List.map trim (String.split_on_char ',' rest))

(* The path set of the valid members of [globs]. *)
let path_set globs =
  let valid member =
    let glob =
      if String.starts_with ~prefix:"!" member then
        String.sub member 1 (String.length member - 1)
      else member
    in
    Result.is_ok (Glob.of_string glob)
  in
  match
    Path_set.of_strings
      (List.sort_uniq String.compare (List.filter valid globs))
  with
  | Ok set -> set
  | Error _ -> Path_set.empty

(* {1 The facts} *)

type declaration = {
  kind : string;
  slug : string;
  rev : int;
  path : string;
  span : Markdown.span;
  extent : Markdown.extent;
  title : string option;
  desc : string;
  status : string option;
}

let declaration_id (declaration : declaration) =
  declaration.kind ^ ":" ^ declaration.slug

(* What the tag target of an edge resolves to. *)
type target =
  | Declaration of int  (** the index in [declarations] *)
  | Ref of { ns : string; id : string }
  | Unresolved of { dangling : bool }

type edge = {
  word : string;
  path : string;
  span : Markdown.span;
  src : string;
  source : int option;  (** the index of the source in [declarations] *)
  target_text : string;
  rev : int option;
  desc : string;
}

let edge_id (edge : edge) = edge.word ^ ":" ^ edge.src ^ "->" ^ edge.target_text

type site = {
  id : string;
  path : string;
  span : Markdown.span;
  name : string option;
  extent : (int * int) option;
}

type ack = {
  path : string;
  span : Markdown.span;
  block : string;
  target : string;
  hash : string;
}

type promise = { word : string; target : string; span : Markdown.span }

type step = {
  slug : string;
  title : string;
  span : Markdown.span;
  own_scope : string list option;
  promises : promise list;
}

type plan = {
  slug : string;
  path : string;
  span : Markdown.span;
  title : string option;
  scope : string list;
  steps : step list;
}

type t = {
  manifest : Manifest.t;
  declarations : declaration array;
  edges : edge list;
  targets : target list;  (** the target of each edge, in the same order *)
  sites : site list;
  acks : ack list;
  plans : plan list;
}

(* {1 Files that are not plan files} *)

let site_id path (section : Markdown.section) =
  match section.heading with
  | None -> "site:" ^ path
  | Some heading -> "site:" ^ path ^ "#" ^ heading.name

let is_citation (tag : Markdown.tag) =
  List.mem tag.word citation_words && Option.is_some tag.target

(* The facts of one file that is not a plan file. A declaration of the
   kind [rule] is in the result too, so that the edges in its extent
   have a source, but it gives no record. [base] is the number of the
   declarations of the files before this one. *)
let ordinary_file ~base ~path (document : Markdown.t) =
  let tags = document.tags in
  let count = Array.length tags in
  let indices = List.init count Fun.id in
  (* [number.(index)] is the index in the declarations of the whole
     tree of the declaration at the tag [index]. *)
  let number = Array.make count (-1) in
  let declared =
    List.filter
      (fun index -> Option.is_some tags.(index).Markdown.extent)
      indices
  in
  List.iteri (fun n index -> number.(index) <- base + n) declared;
  let owner (tag : Markdown.tag) =
    match tag.owner with
    | Some index when number.(index) >= 0 -> Some index
    | Some _ | None -> None
  in
  let id_of index =
    let tag = tags.(index) in
    tag.word ^ ":" ^ Option.value tag.target ~default:""
  in
  let is_site = Array.make (Array.length document.sections) false in
  Array.iter
    (fun (tag : Markdown.tag) ->
      if is_citation tag && Option.is_none (owner tag) then
        is_site.(tag.section) <- true)
    tags;
  (* The status of each declaration: the first status tag of its block
     whose extent is its own and whose word applies to its kind. *)
  let status = Array.make count None in
  Array.iter
    (fun (tag : Markdown.tag) ->
      match owner tag with
      | Some index
        when tags.(index).block = tag.block
             && Option.is_none status.(index)
             && List.mem tags.(index).word (status_kinds tag.word) ->
          status.(index) <- Some tag.word
      | Some _ | None -> ())
    tags;
  (* The last declaration of each block takes its trailing prose. *)
  let last = Array.make (Array.length document.blocks) (-1) in
  List.iter (fun index -> last.(tags.(index).block) <- index) declared;
  let declarations =
    List.filter_map
      (fun index ->
        let tag = tags.(index) in
        match (tag.target, tag.extent) with
        | Some slug, Some extent ->
            let title =
              match tag.node with
              | Markdown.Item_paragraph -> None
              | Markdown.Section_paragraph ->
                  Option.map
                    (fun (heading : Markdown.heading) -> heading.text)
                    document.sections.(tag.section).heading
            in
            let prose =
              if last.(tag.block) = index then
                List.map trim document.blocks.(tag.block).prose
              else []
            in
            let inline = trim tag.desc in
            Some
              {
                kind = tag.word;
                slug;
                rev = Option.value tag.rev ~default:1;
                path;
                span = tag.span;
                extent;
                title;
                desc =
                  String.concat "\n"
                    ((if String.equal inline "" then [] else [ inline ]) @ prose);
                status = status.(index);
              }
        | _ -> None)
      declared
  in
  let edges =
    List.filter_map
      (fun (tag : Markdown.tag) ->
        match tag.target with
        | Some target_text when is_citation tag ->
            let src, source =
              match owner tag with
              | Some index -> (id_of index, Some number.(index))
              | None -> (site_id path document.sections.(tag.section), None)
            in
            Some
              {
                word = tag.word;
                path;
                span = tag.span;
                src;
                source;
                target_text;
                rev = tag.rev;
                desc = trim tag.desc;
              }
        | _ -> None)
      (Array.to_list tags)
  in
  let sites =
    List.filter_map
      (fun index ->
        if not is_site.(index) then None
        else
          let section = document.sections.(index) in
          let span =
            match
              (section.first_paragraph, section.extent, section.heading)
            with
            | Some span, _, _ | None, Some span, _ -> span
            | None, None, Some heading -> heading.span
            | None, None, None ->
                let start = { Markdown.line = 1; column = 1 } in
                { Markdown.start; stop = start }
          in
          Some
            {
              id = site_id path section;
              path;
              span;
              name =
                Option.map
                  (fun (heading : Markdown.heading) -> heading.name)
                  section.heading;
              extent =
                Option.map
                  (fun (span : Markdown.span) ->
                    (span.start.line, span.stop.line))
                  section.extent;
            })
      (List.init (Array.length document.sections) Fun.id)
  in
  let acks =
    List.filter_map
      (fun (tag : Markdown.tag) ->
        let block =
          match owner tag with
          | Some index -> Some (id_of index)
          | None ->
              if is_site.(tag.section) then
                Some (site_id path document.sections.(tag.section))
              else None
        in
        match (tag.word, block, List.rev (tokens tag.rest)) with
        | "ack", Some block, (_, hash) :: (offset, last) :: before ->
            let start =
              match List.rev before with
              | (start, _) :: _ -> start
              | [] -> offset
            in
            let stop = offset + String.length last in
            Some
              {
                path;
                span = tag.span;
                block;
                target = String.sub tag.rest start (stop - start);
                hash;
              }
        | _ -> None)
      (Array.to_list tags)
  in
  (declarations, edges, sites, acks)

(* {1 Plan files} *)

(* The index of the tag of the word [plan] in the first block of
   [document], when [path] is under [.plans/]. *)
let plan_tag ~path (document : Markdown.t) =
  if
    String.starts_with ~prefix:".plans/" path
    && Array.length document.blocks > 0
  then
    List.find_opt
      (fun index -> String.equal document.tags.(index).word "plan")
      document.blocks.(0).tags
  else None

(* The globs of the first [@scope] tag of [indices]. *)
let first_scope (document : Markdown.t) indices =
  List.find_map
    (fun index ->
      let tag = document.tags.(index) in
      if String.equal tag.word "scope" then Some (globs tag.rest) else None)
    indices

(* The index of the section of level 2 that holds the section [index],
   or that is that section. *)
let rec step_section (document : Markdown.t) index =
  let section = document.sections.(index) in
  if section.level = 2 then Some index
  else if section.level < 2 then None
  else Option.bind section.parent (step_section document)

(* The promises of the tags [indices], each word and target once. *)
let promises_of (document : Markdown.t) indices =
  List.rev
    (List.fold_left
       (fun found index ->
         let tag = document.tags.(index) in
         match tag.target with
         | Some target
           when List.mem tag.word promise_words
                && not
                     (List.exists
                        (fun (promise : promise) ->
                          String.equal promise.word tag.word
                          && String.equal promise.target target)
                        found) ->
             { word = tag.word; target; span = tag.span } :: found
         | Some _ | None -> found)
       [] indices)

let plan_file ~path (document : Markdown.t) plan_index =
  let plan_tag = document.tags.(plan_index) in
  match plan_tag.target with
  | Some slug when Slug.is_valid slug ->
      let first_block = document.blocks.(0).tags in
      let later =
        List.filter
          (fun index -> not (List.mem index first_block))
          (List.init (Array.length document.tags) Fun.id)
      in
      let step section_index =
        match document.sections.(section_index) with
        | { level = 2; heading = Some heading; _ } ->
            let held =
              List.filter
                (fun index ->
                  step_section document document.tags.(index).section
                  = Some section_index)
                later
            in
            let own_scope = first_scope document held in
            let promises = promises_of document held in
            if Option.is_none own_scope && promises = [] then None
            else
              Some
                {
                  slug = heading.slug;
                  title = heading.text;
                  span = heading.span;
                  own_scope;
                  promises;
                }
        | _ -> None
      in
      Some
        {
          slug;
          path;
          span = plan_tag.span;
          title =
            Option.map
              (fun (heading : Markdown.heading) -> heading.text)
              document.sections.(plan_tag.section).heading;
          scope = Option.value (first_scope document first_block) ~default:[];
          steps =
            List.filter_map step
              (List.init (Array.length document.sections) Fun.id);
        }
  | Some _ | None -> None

(* {1 Resolution} *)

(* The order of the records of declarations. *)
let compare_declarations (a : declaration) (b : declaration) =
  compare
    (a.kind, a.path, a.span.start.line, a.span.start.column)
    (b.kind, b.path, b.span.start.line, b.span.start.column)

let resolve manifest declarations edges =
  (* The first declaration of each citable slug, in the order of the
     records. *)
  let by_slug = Hashtbl.create 64 in
  Array.iteri
    (fun index (declaration : declaration) ->
      if List.mem declaration.kind declaration_words then
        match Hashtbl.find_opt by_slug declaration.slug with
        | Some other
          when compare_declarations declarations.(other) declaration <= 0 ->
            ()
        | Some _ | None -> Hashtbl.replace by_slug declaration.slug index)
    declarations;
  let namespaces = Manifest.ref_namespaces manifest in
  List.map
    (fun edge ->
      let text = edge.target_text in
      match String.index_opt text '/' with
      | Some slash -> (
          let ns = String.sub text 0 slash in
          let id =
            String.sub text (slash + 1) (String.length text - slash - 1)
          in
          match List.assoc_opt ns namespaces with
          | Some pattern when Id_pattern.matches pattern id -> Ref { ns; id }
          | Some _ | None -> Unresolved { dangling = false })
      | None -> (
          match Hashtbl.find_opt by_slug text with
          | Some index -> Declaration index
          | None -> Unresolved { dangling = Slug.is_valid text }))
    edges

let make manifest files =
  let ordinary, plans =
    List.partition_map
      (fun (path, document) ->
        match plan_tag ~path document with
        | Some index -> Right (plan_file ~path document index)
        | None -> Left (path, document))
      files
  in
  let declarations, edges, sites, acks, _ =
    List.fold_left
      (fun (declarations, edges, sites, acks, base) (path, document) ->
        let d, e, s, a = ordinary_file ~base ~path document in
        ( List.rev_append d declarations,
          List.rev_append e edges,
          List.rev_append s sites,
          List.rev_append a acks,
          base + List.length d ))
      ([], [], [], [], 0) ordinary
  in
  let declarations = Array.of_list (List.rev declarations) in
  let edges = List.rev edges in
  {
    manifest;
    declarations;
    edges;
    targets = resolve manifest declarations edges;
    sites = List.rev sites;
    acks = List.rev acks;
    plans = List.filter_map Fun.id plans;
  }

let needs_changes facts =
  List.exists
    (fun plan ->
      List.exists (fun (step : step) -> step.promises = []) plan.steps)
    facts.plans

(* {1 In force} *)

(* Whether each declaration is in force. A declaration is in force when
   it has no status and no live supersedes edge points at it. An edge is
   live when its source is a declaration that is in force and approved.
   A declaration on a cycle of supersedes edges counts as in force when
   it has no status. *)
let in_force ~approved declarations edges targets =
  let count = Array.length declarations in
  let successors = Array.make count [] in
  let predecessors = Array.make count [] in
  List.iter2
    (fun (edge : edge) target ->
      match (edge.word, edge.source, target) with
      | "supersedes", Some source, Declaration target ->
          successors.(source) <- target :: successors.(source);
          predecessors.(target) <- source :: predecessors.(target)
      | _ -> ())
    edges targets;
  (* Tarjan's algorithm: a declaration is on a cycle when its strongly
     connected component holds another declaration too, or when it has an
     edge to itself. *)
  let on_cycle = Array.make count false in
  let number = Array.make count (-1) in
  let low = Array.make count 0 in
  let stacked = Array.make count false in
  let stack = ref [] in
  let next = ref 0 in
  let rec visit node =
    number.(node) <- !next;
    low.(node) <- !next;
    incr next;
    stack := node :: !stack;
    stacked.(node) <- true;
    List.iter
      (fun successor ->
        if number.(successor) < 0 then (
          visit successor;
          low.(node) <- min low.(node) low.(successor))
        else if stacked.(successor) then
          low.(node) <- min low.(node) number.(successor))
      successors.(node);
    if low.(node) = number.(node) then
      let rec pop members =
        match !stack with
        | top :: rest ->
            stack := rest;
            stacked.(top) <- false;
            if top = node then top :: members else pop (top :: members)
        | [] -> members
      in
      match pop [] with
      | [ single ] -> on_cycle.(single) <- List.mem single successors.(single)
      | members -> List.iter (fun member -> on_cycle.(member) <- true) members
  in
  for node = 0 to count - 1 do
    if number.(node) < 0 then visit node
  done;
  (* Off the cycles, the edges form no cycle, so the recursion ends. *)
  let memo = Array.make count None in
  let rec force node =
    match memo.(node) with
    | Some value -> value
    | None ->
        let value =
          Option.is_none declarations.(node).status
          && (on_cycle.(node)
             || List.for_all
                  (fun source -> not (approved source && force source))
                  predecessors.(node))
        in
        memo.(node) <- Some value;
        value
  in
  Array.init count force

(* {1 Records} *)

(* A record and the key that orders it. *)
type key =
  | Located of { kind : string; path : string; line : int; col : int }
  | Unlocated

type fact = { key : key; id : string; record : Jsonl.record }

let compare_facts a b =
  match (a.key, b.key) with
  | Located x, Located y ->
      compare
        (x.kind, x.path, x.line, x.col, a.id)
        (y.kind, y.path, y.line, y.col, b.id)
  | Located _, Unlocated -> -1
  | Unlocated, Located _ -> 1
  | Unlocated, Unlocated -> String.compare a.id b.id

let located ~kind ~id ~path ~(span : Markdown.span) fields =
  {
    key =
      Located { kind; path; line = span.start.line; col = span.start.column };
    id;
    record =
      [
        ("v", Jsonl.int 1);
        ("kind", Jsonl.string kind);
        ("id", Jsonl.string id);
        ("pack", Jsonl.string "markdown");
        ("path", Jsonl.string path);
        ("line", Jsonl.int span.start.line);
        ("col", Jsonl.int span.start.column);
        ("eline", Jsonl.int span.stop.line);
        ("ecol", Jsonl.int span.stop.column);
      ]
      @ fields;
  }

let optional name = function None -> [] | Some value -> [ (name, value) ]

let text_unless_empty name text =
  if String.equal text "" then [] else [ (name, Jsonl.string text) ]

(* The canonical JSON text of an array of strings. *)
let json_strings strings =
  let wrapped = Jsonl.to_string [ ("a", Jsonl.strings strings) ] in
  (* [wrapped] is {"a":[...]}. *)
  String.sub wrapped 5 (String.length wrapped - 6)

let canonical globs = List.sort_uniq String.compare globs

let effective_scope plan (step : step) =
  Option.value step.own_scope ~default:plan.scope

let commitment_hash plan =
  let promises =
    List.concat_map
      (fun (step : step) ->
        let scope = canonical (effective_scope plan step) in
        List.map
          (fun (promise : promise) ->
            (promise.word, promise.target, json_strings scope, scope))
          step.promises)
      plan.steps
  in
  let objects =
    List.map
      (fun (word, target, _, scope) ->
        Jsonl.to_string
          [
            ("scope", Jsonl.strings scope);
            ("target", Jsonl.string target);
            ("word", Jsonl.string word);
          ])
      (List.sort
         (fun (w1, t1, s1, _) (w2, t2, s2, _) ->
           compare (w1, t1, s1) (w2, t2, s2))
         promises)
  in
  Sha256.hex
    ("{\"promises\":[" ^ String.concat "," objects ^ "],\"scope\":"
    ^ json_strings (canonical plan.scope)
    ^ "}")

let declaration_records facts ~inforce ~approved =
  let required = Manifest.approval_required facts.manifest in
  List.filter_map Fun.id
    (List.mapi
       (fun index (d : declaration) ->
         Option.map
           (fun kind ->
             located ~kind:d.kind ~id:(declaration_id d) ~path:d.path
               ~span:d.span
               ([
                  ("slug", Jsonl.string d.slug);
                  ("rev", Jsonl.int d.rev);
                  ("xh", Jsonl.string d.extent.hash);
                  ("xline", Jsonl.int d.extent.first);
                  ("xeline", Jsonl.int d.extent.last);
                  ("inforce", Jsonl.bool inforce.(index));
                  ("approved", Jsonl.bool (approved index));
                  ("approval_required", Jsonl.bool (List.mem kind required));
                  ("declined", Jsonl.bool false);
                ]
               @ optional "title" (Option.map Jsonl.string d.title)
               @ text_unless_empty "desc" d.desc
               @ optional "status" (Option.map Jsonl.string d.status)))
           (manifest_kind d.kind))
       (Array.to_list facts.declarations))

let edge_records facts ~inforce ~approved =
  List.map2
    (fun (edge : edge) target ->
      let dst, dangling =
        match target with
        | Declaration index ->
            (Some (declaration_id facts.declarations.(index)), false)
        | Ref { ns; id } -> (Some ("ref:" ^ ns ^ "/" ^ id), false)
        | Unresolved { dangling } -> (None, dangling)
      in
      let suspect =
        match (edge.rev, target) with
        | Some rev, Declaration index -> facts.declarations.(index).rev <> rev
        | _ -> false
      in
      let live =
        match edge.source with
        | Some index -> inforce.(index) && approved index
        | None -> false
      in
      located ~kind:edge.word ~id:(edge_id edge) ~path:edge.path ~span:edge.span
        ([
           ("src", Jsonl.string edge.src);
           ("target", Jsonl.string edge.target_text);
           ("suspect", Jsonl.bool suspect);
           ("dangling", Jsonl.bool dangling);
         ]
        @ optional "dst" (Option.map Jsonl.string dst)
        @ optional "rev" (Option.map Jsonl.int edge.rev)
        @ text_unless_empty "desc" edge.desc
        @ (if String.equal edge.word "verifies" then
             [ ("rung", Jsonl.string "orphan") ]
           else [])
        @
        if String.equal edge.word "supersedes" then
          [ ("live", Jsonl.bool live) ]
        else []))
    facts.edges facts.targets

let ref_records facts =
  List.map
    (fun (ns, ref_id) ->
      let id = "ref:" ^ ns ^ "/" ^ ref_id in
      {
        key = Unlocated;
        id;
        record =
          [
            ("v", Jsonl.int 1);
            ("kind", Jsonl.string "ref");
            ("id", Jsonl.string id);
            ("pack", Jsonl.string "markdown");
            ("ns", Jsonl.string ns);
            ("ref", Jsonl.string ref_id);
          ];
      })
    (List.sort_uniq compare
       (List.filter_map
          (function Ref { ns; id } -> Some (ns, id) | _ -> None)
          facts.targets))

let site_records facts =
  List.map
    (fun (site : site) ->
      located ~kind:"site" ~id:site.id ~path:site.path ~span:site.span
        (optional "name" (Option.map Jsonl.string site.name)
        @
        match site.extent with
        | Some (first, last) ->
            [ ("xline", Jsonl.int first); ("xeline", Jsonl.int last) ]
        | None -> []))
    facts.sites

let ack_records facts =
  List.map
    (fun (ack : ack) ->
      located ~kind:"ack"
        ~id:("ack:" ^ ack.block ^ ":" ^ ack.target)
        ~path:ack.path ~span:ack.span
        [
          ("block", Jsonl.string ack.block);
          ("target", Jsonl.string ack.target);
          ("hash", Jsonl.string ack.hash);
        ])
    facts.acks

(* The facts that would discharge [promise], each with its id and its
   path, in the order of their paths and places. A declaration counts
   when its kind is the word of the promise. An edge counts when its tag
   target resolves and it is not suspect. A [verifies] edge in markdown
   is at the rung orphan, which discharges no promise. *)
let residue facts (promise : promise) =
  let order (_, path_a, (span_a : Markdown.span))
      (_, path_b, (span_b : Markdown.span)) =
    compare
      (path_a, span_a.start.line, span_a.start.column)
      (path_b, span_b.start.line, span_b.start.column)
  in
  let found =
    if List.mem promise.word declaration_words then
      List.filter_map
        (fun (d : declaration) ->
          if
            String.equal d.kind promise.word
            && String.equal d.slug promise.target
          then Some (declaration_id d, d.path, d.span)
          else None)
        (Array.to_list facts.declarations)
    else if String.equal promise.word "verifies" then []
    else
      List.filter_map Fun.id
        (List.map2
           (fun (edge : edge) target ->
             let discharges =
               match (target, edge.rev) with
               | Declaration index, Some rev ->
                   facts.declarations.(index).rev = rev
               | Declaration _, None | Ref _, _ -> true
               | Unresolved _, _ -> false
             in
             if
               String.equal edge.word promise.word
               && String.equal edge.target_text promise.target
               && discharges
             then Some (edge_id edge, edge.path, edge.span)
             else None)
           facts.edges facts.targets)
  in
  List.sort order found

let plan_records facts ~changed plan =
  let required = Manifest.approval_required facts.manifest in
  let plan_record =
    located ~kind:"plan" ~id:("plan:" ^ plan.slug) ~path:plan.path
      ~span:plan.span
      ([
         ("slug", Jsonl.string plan.slug);
         ("scope", Jsonl.strings plan.scope);
         ("approved", Jsonl.bool (not (List.mem Manifest.Plan required)));
         ("active", Jsonl.bool false);
         ("open", Jsonl.bool true);
         ("csh", Jsonl.string (commitment_hash plan));
         ("declined", Jsonl.bool false);
       ]
      @ optional "title" (Option.map Jsonl.string plan.title))
  in
  let step_records (step : step) =
    let scope = effective_scope plan step in
    let in_scope = Path_set.mem (path_set scope) in
    let step_id = "step:" ^ plan.slug ^ "/" ^ step.slug in
    let promises =
      List.map
        (fun (promise : promise) ->
          let residue = residue facts promise in
          let location =
            Option.bind
              (manifest_kind promise.word)
              (Manifest.location facts.manifest)
          in
          let inside (_, path, _) =
            in_scope path
            || Option.fold ~none:false
                 ~some:(fun set -> Path_set.mem set path)
                 location
          in
          let by = List.find_opt inside residue in
          (promise, by, residue <> [] && Option.is_none by))
        step.promises
    in
    let met =
      List.length (List.filter (fun (_, by, _) -> Option.is_some by) promises)
    in
    let total = List.length promises in
    let verified =
      not
        (List.exists
           (fun (edge : edge) ->
             String.equal edge.word "verifies" && in_scope edge.path)
           facts.edges)
    in
    let done_ =
      verified
      && if total = 0 then List.exists in_scope changed else met = total
    in
    located ~kind:"step" ~id:step_id ~path:plan.path ~span:step.span
      [
        ("plan", Jsonl.string plan.slug);
        ("slug", Jsonl.string step.slug);
        ("title", Jsonl.string step.title);
        ("scope", Jsonl.strings scope);
        ("own_scope", Jsonl.bool (Option.is_some step.own_scope));
        ("refactor", Jsonl.bool (total = 0));
        ("met", Jsonl.int met);
        ("total", Jsonl.int total);
        ("done", Jsonl.bool done_);
        ("active", Jsonl.bool false);
      ]
    :: List.map
         (fun ((promise : promise), by, out_of_scope) ->
           located ~kind:"promise"
             ~id:
               (String.concat ":"
                  [ "promise"; step_id; promise.word; promise.target ])
             ~path:plan.path ~span:promise.span
             ([
                ("plan", Jsonl.string plan.slug);
                ("step", Jsonl.string step.slug);
                ("word", Jsonl.string promise.word);
                ("target", Jsonl.string promise.target);
                ("met", Jsonl.bool (Option.is_some by));
                ("out_of_scope", Jsonl.bool out_of_scope);
              ]
             @ optional "by" (Option.map (fun (id, _, _) -> Jsonl.string id) by)
             ))
         promises
  in
  plan_record :: List.concat_map step_records plan.steps

let records facts ~changed =
  let required = Manifest.approval_required facts.manifest in
  let approved index =
    match manifest_kind facts.declarations.(index).kind with
    | Some kind -> not (List.mem kind required)
    | None -> true
  in
  let inforce =
    in_force ~approved facts.declarations facts.edges facts.targets
  in
  List.map
    (fun fact -> fact.record)
    (List.stable_sort compare_facts
       (List.concat
          [
            declaration_records facts ~inforce ~approved;
            edge_records facts ~inforce ~approved;
            ref_records facts;
            site_records facts;
            ack_records facts;
            List.concat_map (plan_records facts ~changed) facts.plans;
          ]))

let index ~tree ~base ~target_branch ~manifest ~tool =
  [
    ("v", Jsonl.int 1);
    ("kind", Jsonl.string "index");
    ("tree", Jsonl.string tree);
    ("base", Jsonl.string base);
    ("target_branch", Jsonl.string target_branch);
    ("manifest", Jsonl.string manifest);
    ("evidence", Jsonl.bool false);
    ("packs", Jsonl.strings []);
    ("tool", Jsonl.string tool);
    ("mode", Jsonl.string "tree");
  ]
