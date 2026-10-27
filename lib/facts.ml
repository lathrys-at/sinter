(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

let declaration_words = [ "req"; "design"; "decision" ]

let citation_words =
  [ "satisfies"; "verifies"; "refines"; "cites"; "supersedes" ]

let promise_words = declaration_words @ citation_words

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
    if is_blank text.[index] then last (index - 1) else index
  in
  let start = first 0 in
  if start = length then ""
  else String.sub text start (last (length - 1) - start + 1)

let ack_parts rest =
  let text = trim rest in
  let blank =
    match (String.rindex_opt text ' ', String.rindex_opt text '\t') with
    | Some space, Some tab -> Some (max space tab)
    | (Some _ as one), None | None, (Some _ as one) -> one
    | None, None -> None
  in
  let rec target_end index =
    if is_blank text.[index - 1] then target_end (index - 1) else index
  in
  Option.map
    (fun blank ->
      ( String.sub text 0 (target_end blank),
        String.sub text (blank + 1) (String.length text - blank - 1) ))
    blank

let globs rest =
  List.filter
    (fun glob -> not (String.equal glob ""))
    (List.map trim (String.split_on_char ',' rest))

let path_set globs =
  let members = List.sort_uniq String.compare globs in
  match Path_set.of_strings members with
  | Ok set -> set
  | Error errors -> (
      let bad =
        List.filter_map
          (function
            | Path_set.Bad_glob { index; _ } -> Some index
            | Path_set.Repeated _ | Path_set.No_plain_glob -> None)
          errors
      in
      match
        Path_set.of_strings
          (List.filteri (fun index _ -> not (List.mem index bad)) members)
      with
      | Ok set -> set
      | Error _ -> Path_set.empty)

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

type target =
  | Declaration of int
  | Ref of { ns : string; id : string }
  | Unresolved of { dangling : bool }

type edge = {
  word : string;
  path : string;
  span : Markdown.span;
  src : string;
  source : int option;
  target_text : string;
  rev : int option;
  desc : string;
  block_index : int;
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
  block_index : int;
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

type meeting_fact = { id : string; path : string; span : Markdown.span }

module Pairs = Map.Make (struct
  type t = string * string

  let compare (a, b) (c, d) =
    match String.compare a c with 0 -> String.compare b d | order -> order
end)

type lookups = {
  declared : int list Pairs.t;
  cited : edge list Pairs.t;
  verifies : string list;
}

module Paths = Map.Make (String)

module Blocks = Map.Make (struct
  type t = string * int

  let compare (a, b) (c, d) =
    match String.compare a c with 0 -> Int.compare b d | order -> order
end)

type t = {
  manifest : Manifest.t;
  declarations : declaration array;
  inforce : bool array;
  retirers : int list array;
  edges : edge list;
  targets : target list;
  sites : site list;
  acks : ack list;
  plans : plan list;
  lookups : lookups Lazy.t;
  block_hashes : string array Paths.t Lazy.t;
  block_acks : ack list Blocks.t Lazy.t;
}

let site_id path (section : Markdown.section) =
  match section.heading with
  | None -> "site:" ^ path
  | Some heading -> "site:" ^ path ^ "#" ^ heading.name

let is_citation (tag : Markdown.tag) =
  List.mem tag.word citation_words && Option.is_some tag.target

let ordinary_file ~base ~path (document : Markdown.t) =
  let tags = document.tags in
  let count = Array.length tags in
  let indices = List.init count Fun.id in
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
  let site = Array.make (Array.length document.sections) None in
  Array.iter
    (fun (tag : Markdown.tag) ->
      if
        is_citation tag
        && Option.is_none (owner tag)
        && Option.is_none site.(tag.section)
      then site.(tag.section) <- Some tag.span)
    tags;
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
                block_index = tag.block;
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
            Some
              {
                path;
                span = tag.span;
                block;
                target;
                hash;
                block_index = tag.block;
              }
        | _ -> None)
      (Array.to_list tags)
  in
  (declarations, edges, sites, acks)

let plan_tag ~path (document : Markdown.t) =
  if
    String.starts_with ~prefix:".plans/" path
    && Array.length document.blocks > 0
  then
    List.find_opt
      (fun index -> String.equal document.tags.(index).word "plan")
      document.blocks.(0).tags
  else None

let first_scope (document : Markdown.t) indices =
  List.find_map
    (fun index ->
      let tag = document.tags.(index) in
      if String.equal tag.word "scope" then Some (globs tag.rest) else None)
    indices

let rec step_section (document : Markdown.t) index =
  let section = document.sections.(index) in
  match section.level with
  | 2 -> Some index
  | _ -> Option.bind section.parent (step_section document)

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

let compare_declarations (a : declaration) (b : declaration) =
  compare
    (a.kind, a.path, a.span.start.line, a.span.start.column)
    (b.kind, b.path, b.span.start.line, b.span.start.column)

module Slugs = Map.Make (String)

let resolve manifest (declarations : declaration array) edges =
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

let approved manifest (declarations : declaration array) index =
  match manifest_kind declarations.(index).kind with
  | Some kind -> not (List.mem kind (Manifest.approval_required manifest))
  | None -> true

let live_source manifest (declarations : declaration array) index =
  Option.is_none declarations.(index).status
  && approved manifest declarations index

let retirers manifest (declarations : declaration array) edges targets =
  let found = Array.make (Array.length declarations) [] in
  List.iter2
    (fun (edge : edge) target ->
      match (edge.word, edge.source, target) with
      | "supersedes", Some source, Declaration target
        when live_source manifest declarations source ->
          found.(target) <- source :: found.(target)
      | _ -> ())
    edges targets;
  found

let in_force ~retirers (declarations : declaration array) edges targets =
  let count = Array.length declarations in
  let superseded = Array.make count [] in
  List.iter2
    (fun (edge : edge) target ->
      match (edge.word, edge.source, target) with
      | "supersedes", Some source, Declaration target ->
          superseded.(source) <- target :: superseded.(source)
      | _ -> ())
    edges targets;
  let on_cycle node =
    let rec search seen = function
      | [] -> false
      | next :: rest ->
          next = node
          ||
          if List.mem next seen then search seen rest
          else search (next :: seen) (superseded.(next) @ rest)
    in
    search [] superseded.(node)
  in
  Array.init count (fun node ->
      Option.is_none declarations.(node).status
      && (retirers.(node) = [] || on_cycle node))

let in_place_order (a : meeting_fact) (b : meeting_fact) =
  compare
    (a.path, a.span.start.line, a.span.start.column)
    (b.path, b.span.start.line, b.span.start.column)

let promised plans =
  List.fold_left
    (fun keys (plan : plan) ->
      List.fold_left
        (fun keys (step : step) ->
          List.fold_left
            (fun keys (promise : promise) ->
              Pairs.add (promise.word, promise.target) [] keys)
            keys step.promises)
        keys plan.steps)
    Pairs.empty plans

let group keys add items =
  List.fold_left
    (fun groups item ->
      match add item with
      | Some (key, member) ->
          Pairs.update key (Option.map (List.cons member)) groups
      | None -> groups)
    keys (List.rev items)

let lookups (declarations : declaration array) edges targets plans =
  let keys = promised plans in
  {
    declared =
      group keys
        (fun index ->
          let d = declarations.(index) in
          Some ((d.kind, d.slug), index))
        (List.init (Array.length declarations) Fun.id);
    cited =
      group keys
        (fun ((edge : edge), target) ->
          let meets =
            match (target, edge.rev) with
            | Declaration index, Some rev -> declarations.(index).rev = rev
            | Declaration _, None | Ref _, _ -> true
            | Unresolved _, _ -> false
          in
          if meets then Some ((edge.word, edge.target_text), edge) else None)
        (List.combine edges targets);
    verifies =
      List.sort_uniq String.compare
        (List.filter_map
           (fun (edge : edge) ->
             if String.equal edge.word "verifies" then Some edge.path else None)
           edges);
  }

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
  let targets = resolve manifest declarations edges in
  let retirers = retirers manifest declarations edges targets in
  let plans = List.filter_map Fun.id plans in
  let acks = List.rev acks in
  {
    manifest;
    declarations;
    inforce = in_force ~retirers declarations edges targets;
    retirers;
    edges;
    targets;
    sites = List.rev sites;
    acks;
    plans;
    lookups = lazy (lookups declarations edges targets plans);
    block_hashes =
      lazy
        (List.fold_left
           (fun hashes (path, (document : Markdown.t)) ->
             Paths.update path
               (function
                 | None ->
                     Some
                       (Array.map
                          (fun (block : Markdown.block) -> block.hash)
                          document.blocks)
                 | kept -> kept)
               hashes)
           Paths.empty files);
    block_acks =
      lazy
        (List.fold_left
           (fun groups (ack : ack) ->
             Blocks.update
               (ack.path, ack.block_index)
               (fun found -> Some (ack :: Option.value found ~default:[]))
               groups)
           Blocks.empty (List.rev acks));
  }

let needs_changes facts =
  List.exists
    (fun plan ->
      List.exists (fun (step : step) -> step.promises = []) plan.steps)
    facts.plans

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

let json_strings strings =
  let wrapped = Jsonl.to_string [ ("a", Jsonl.strings strings) ] in
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

let edge_records facts =
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
        | Some index -> live_source facts.manifest facts.declarations index
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

let meeting_facts facts (promise : promise) =
  let lookups = Lazy.force facts.lookups in
  let find groups =
    Option.value
      (Pairs.find_opt (promise.word, promise.target) groups)
      ~default:[]
  in
  let found =
    if List.mem promise.word declaration_words then
      List.map
        (fun index ->
          let d = facts.declarations.(index) in
          { id = declaration_id d; path = d.path; span = d.span })
        (find lookups.declared)
    else if String.equal promise.word "verifies" then []
    else
      List.map
        (fun (edge : edge) ->
          { id = edge_id edge; path = edge.path; span = edge.span })
        (find lookups.cited)
  in
  List.sort in_place_order found

type standing = { by : meeting_fact option; meeting_facts : meeting_fact list }

let standing_within facts ~in_scope (promise : promise) =
  let meeting_facts = meeting_facts facts promise in
  let location =
    Option.bind (manifest_kind promise.word) (Manifest.location facts.manifest)
  in
  let inside (fact : meeting_fact) =
    in_scope fact.path
    || Option.fold ~none:false
         ~some:(fun set -> Path_set.mem set fact.path)
         location
  in
  { by = List.find_opt inside meeting_facts; meeting_facts }

let standing facts plan step =
  if not (List.memq plan facts.plans && List.memq step plan.steps) then
    invalid_arg "Facts.standing: the step is not one of these facts";
  let in_scope = Path_set.mem (path_set (effective_scope plan step)) in
  fun (promise : promise) ->
    if not (List.memq promise step.promises) then
      invalid_arg "Facts.standing: the promise is not one of this step";
    standing_within facts ~in_scope promise

let step_id (plan : plan) (step : step) = "step:" ^ plan.slug ^ "/" ^ step.slug

let promise_id plan step (promise : promise) =
  String.concat ":"
    [ "promise"; step_id plan step; promise.word; promise.target ]

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
    let step_id = step_id plan step in
    let promises =
      List.map
        (fun (promise : promise) ->
          let { by; meeting_facts } = standing_within facts ~in_scope promise in
          (promise, by, meeting_facts <> [] && Option.is_none by))
        step.promises
    in
    let met =
      List.length (List.filter (fun (_, by, _) -> Option.is_some by) promises)
    in
    let total = List.length promises in
    let verified =
      not (List.exists in_scope (Lazy.force facts.lookups).verifies)
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
             ~id:(promise_id plan step promise)
             ~path:plan.path ~span:promise.span
             ([
                ("plan", Jsonl.string plan.slug);
                ("step", Jsonl.string step.slug);
                ("word", Jsonl.string promise.word);
                ("target", Jsonl.string promise.target);
                ("met", Jsonl.bool (Option.is_some by));
                ("out_of_scope", Jsonl.bool out_of_scope);
              ]
             @ optional "by"
                 (Option.map (fun (by : meeting_fact) -> Jsonl.string by.id) by)
             ))
         promises
  in
  plan_record :: List.concat_map step_records plan.steps

let records facts ~changed =
  let approved = approved facts.manifest facts.declarations in
  let inforce = facts.inforce in
  List.map
    (fun fact -> fact.record)
    (List.stable_sort
       (fun a b -> compare a.key b.key)
       (List.concat
          [
            declaration_records facts ~inforce ~approved;
            edge_records facts;
            site_records facts;
            ack_records facts;
            List.concat_map (plan_records facts ~changed) facts.plans;
          ]))
  @ ref_records facts

let declarations facts = Array.to_list facts.declarations
let is_in_force facts index = facts.inforce.(index)

module Indices = Set.Make (Int)

let successors facts index =
  let declarations = facts.declarations in
  let rec walk reached = function
    | [] -> reached
    | node :: rest ->
        if Indices.mem node reached then walk reached rest
        else
          walk (Indices.add node reached)
            (if facts.inforce.(node) then rest else facts.retirers.(node) @ rest)
  in
  let reached =
    if facts.inforce.(index) then Indices.empty
    else walk Indices.empty facts.retirers.(index)
  in
  let order a b =
    compare
      ( declaration_id declarations.(a),
        declarations.(a).path,
        declarations.(a).span.start.line )
      ( declaration_id declarations.(b),
        declarations.(b).path,
        declarations.(b).span.start.line )
  in
  List.rev
    (List.fold_left
       (fun found node ->
         match found with
         | kept :: _
           when String.equal
                  (declaration_id declarations.(kept))
                  (declaration_id declarations.(node)) ->
             found
         | _ -> node :: found)
       []
       (List.sort order
          (Indices.elements
             (Indices.filter (fun node -> facts.inforce.(node)) reached))))

let block_hash facts path index =
  (Paths.find path (Lazy.force facts.block_hashes)).(index)

let block_acks facts path index =
  Option.value
    (Blocks.find_opt (path, index) (Lazy.force facts.block_acks))
    ~default:[]

let edges facts = List.combine facts.edges facts.targets
let acks facts = facts.acks
let plans facts = facts.plans

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
