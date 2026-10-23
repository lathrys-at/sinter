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
  (* [text.[start]] is not blank, so the search back stops there. *)
  let rec last index =
    if is_blank text.[index] then last (index - 1) else index
  in
  let start = first 0 in
  if start = length then ""
  else String.sub text start (last (length - 1) - start + 1)

(* The tag target and the hash of the text after an [@ack] word: the
   hash is its last token, and the tag target is everything before it,
   without the spaces and tabs at its ends. A token is a run of
   characters that are neither a space nor a tab. *)
let ack_parts rest =
  let text = trim rest in
  let blank =
    match (String.rindex_opt text ' ', String.rindex_opt text '\t') with
    | Some space, Some tab -> Some (max space tab)
    | (Some _ as one), None | None, (Some _ as one) -> one
    | None, None -> None
  in
  Option.map
    (fun blank ->
      ( trim (String.sub text 0 blank),
        String.sub text (blank + 1) (String.length text - blank - 1) ))
    blank

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
  (* Each declaration, by the index of its tag, with its index in the
     declarations of the whole tree. *)
  let numbers =
    List.mapi
      (fun n index -> (index, base + n))
      (List.filter
         (fun index -> Option.is_some tags.(index).Markdown.extent)
         indices)
  in
  let declared = List.map fst numbers in
  let owner (tag : Markdown.tag) = tag.owner in
  let id_of index =
    let tag = tags.(index) in
    tag.word ^ ":" ^ Option.value tag.target ~default:""
  in
  (* [site.(index)] is the span of the first citation of the section
     [index] outside every extent, when the section has one. *)
  let site = Array.make (Array.length document.sections) None in
  Array.iter
    (fun (tag : Markdown.tag) ->
      if
        is_citation tag
        && Option.is_none (owner tag)
        && Option.is_none site.(tag.section)
      then site.(tag.section) <- Some tag.span)
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
  (* The last declaration of the block [block], which takes its
     trailing prose. *)
  let last block =
    List.fold_left
      (fun found index -> if List.mem index declared then Some index else found)
      None document.blocks.(block).tags
  in
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
              if last tag.block = Some index then
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
              | Some index -> (id_of index, Some (List.assoc index numbers))
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
        Option.map
          (fun citation ->
            let section = document.sections.(index) in
            (* A section that holds a citation outside every extent
               keeps the line of the citation in its extent, so the
               extent is never [None] here. *)
            let span =
              match (section.first_paragraph, section.extent) with
              | Some span, _ | None, Some span -> span
              | None, None -> citation
            in
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
          site.(index))
      (List.init (Array.length document.sections) Fun.id)
  in
  let acks =
    List.filter_map
      (fun (tag : Markdown.tag) ->
        let block =
          match owner tag with
          | Some index -> Some (id_of index)
          | None ->
              if Option.is_some site.(tag.section) then
                Some (site_id path document.sections.(tag.section))
              else None
        in
        match (tag.word, block, ack_parts tag.rest) with
        | "ack", Some block, Some (target, hash) ->
            Some { path; span = tag.span; block; target; hash }
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
  match section.level with
  | 2 -> Some index
  | 0 | 1 -> None
  | _ -> Option.bind section.parent (step_section document)

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

module Slugs = Map.Make (String)

let resolve manifest (declarations : declaration array) edges =
  (* The first declaration of each citable slug, in the order of the
     records. *)
  let by_slug =
    List.fold_left
      (fun map index ->
        Slugs.update declarations.(index).slug
          (function None -> Some index | kept -> kept)
          map)
      Slugs.empty
      (List.stable_sort
         (fun a b -> compare_declarations declarations.(a) declarations.(b))
         (List.filter
            (fun index -> List.mem declarations.(index).kind declaration_words)
            (List.init (Array.length declarations) Fun.id)))
  in
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
          match Slugs.find_opt text by_slug with
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
  (* A declaration is on a cycle when it reaches itself along the
     edges. *)
  let on_cycle node =
    let rec search seen = function
      | [] -> false
      | next :: rest ->
          next = node
          ||
          if List.mem next seen then search seen rest
          else search (next :: seen) (successors.(next) @ rest)
    in
    search [] successors.(node)
  in
  (* Off the cycles, the edges form no cycle, so the recursion ends. *)
  let memo = Array.make count None in
  let rec force node =
    match memo.(node) with
    | Some value -> value
    | None ->
        let value =
          Option.is_none declarations.(node).status
          && (on_cycle node
             || List.for_all
                  (fun source -> not (approved source && force source))
                  predecessors.(node))
        in
        memo.(node) <- Some value;
        value
  in
  Array.init count force

(* {1 Records} *)

(* A located record and its key of order: the kind, the path, the line,
   the column, and the id. *)
type fact = {
  key : string * string * int * int * string;
  record : Jsonl.record;
}

let located ~kind ~id ~path ~(span : Markdown.span) fields =
  {
    key = (kind, path, span.start.line, span.start.column, id);
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
  (* A record of the one key [a] is written as {"a": and the array and
     the closing brace. *)
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

(* The records of the refs that the edges resolve to, sorted by id. *)
let ref_records facts =
  List.map
    (fun (id, (ns, ref_id)) ->
      [
        ("v", Jsonl.int 1);
        ("kind", Jsonl.string "ref");
        ("id", Jsonl.string id);
        ("pack", Jsonl.string "markdown");
        ("ns", Jsonl.string ns);
        ("ref", Jsonl.string ref_id);
      ])
    (List.sort_uniq
       (fun (a, _) (b, _) -> String.compare a b)
       (List.filter_map
          (function
            | Ref { ns; id } -> Some ("ref:" ^ ns ^ "/" ^ id, (ns, id))
            | _ -> None)
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
    (List.stable_sort
       (fun a b -> compare a.key b.key)
       (List.concat
          [
            declaration_records facts ~inforce ~approved;
            edge_records facts ~inforce ~approved;
            site_records facts;
            ack_records facts;
            List.concat_map (plan_records facts ~changed) facts.plans;
          ]))
  @ ref_records facts

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
