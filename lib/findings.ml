(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

let declaration_words = [ "req"; "design"; "decision"; "rule" ]

let citation_words =
  [ "satisfies"; "verifies"; "refines"; "cites"; "supersedes" ]

let vocabulary =
  declaration_words @ citation_words
  @ [ "plan"; "deprecated"; "rejected"; "deferred"; "ack"; "scope" ]

let start_of (span : Markdown.span) = span.start
let place path span = { Finding.path; span }

(* Each tag line of each document, with the path of its file. *)
let tags documents =
  List.concat_map
    (fun (path, (document : Markdown.t)) ->
      List.map (fun tag -> (path, tag)) (Array.to_list document.tags))
    documents

(* {1 The classes of the reader} *)

let parse_errors documents ~not_text =
  List.map
    (fun (path, offset) ->
      let origin = { Markdown.line = 1; column = 1 } in
      Finding.make Finding_class.Parse_error (Finding.File path)
        ~place:(place path { Markdown.start = origin; stop = origin })
        ~detail:(Printf.sprintf "the file is not UTF-8 text at byte %d" offset)
        ())
    not_text
  @ List.concat_map
      (fun (path, (document : Markdown.t)) ->
        List.map
          (fun span ->
            Finding.make Finding_class.Parse_error
              (Finding.Error_node { path; position = start_of span })
              ~place:(place path span)
              ~detail:"the markdown parser cannot read the text here" ())
          document.errors)
      documents

let typo_tags documents =
  List.filter_map
    (fun (path, (tag : Markdown.tag)) ->
      if List.mem tag.word vocabulary then None
      else
        Option.map
          (fun nearest ->
            Finding.make Finding_class.Typo_tag
              (Finding.Line { path; line = tag.span.start.line })
              ~place:(place path tag.span)
              ~detail:
                (Printf.sprintf "@%s is not a tag word of sinter" tag.word)
              ~fix:("@" ^ nearest) ())
          (Edit_distance.nearest tag.word vocabulary))
    (tags documents)

let unread_tags documents =
  List.concat_map
    (fun (path, (document : Markdown.t)) ->
      List.map
        (fun (span : Markdown.span) ->
          Finding.make Finding_class.Unread_tag
            (Finding.Line { path; line = span.start.line })
            ~place:(place path span)
            ~detail:
              "sinter reads tags only in the first paragraph of a section or a \
               list item"
            ())
        document.unread)
    documents

(* Why the tag target [target] of a tag of the word [word] fails its
   pattern, or [None] when it does not. *)
let target_problem manifest ~word target =
  let slug () =
    if Slug.is_valid target then None
    else Some (Printf.sprintf "%s is not a valid slug" target)
  in
  if List.mem word citation_words then
    match String.index_opt target '/' with
    | None -> slug ()
    | Some slash -> (
        let ns = String.sub target 0 slash in
        let id =
          String.sub target (slash + 1) (String.length target - slash - 1)
        in
        match List.assoc_opt ns (Manifest.ref_namespaces manifest) with
        | None ->
            Some (Printf.sprintf "the manifest declares no ref namespace %s" ns)
        | Some pattern ->
            if Id_pattern.matches pattern id then None
            else
              Some
                (Printf.sprintf
                   "%s does not match the id pattern of the ref namespace %s" id
                   ns))
  else if List.mem word ("plan" :: declaration_words) then slug ()
  else None

let bad_targets manifest documents =
  List.filter_map
    (fun (path, (tag : Markdown.tag)) ->
      Option.bind tag.target (fun target ->
          Option.map
            (fun detail ->
              Finding.make Finding_class.Bad_target
                (Finding.Tag { path; position = start_of tag.span })
                ~place:(place path tag.span) ~detail ())
            (target_problem manifest ~word:tag.word target)))
    (tags documents)

let misplaced_plans documents =
  List.filter_map
    (fun (path, (tag : Markdown.tag)) ->
      let detail =
        if not (String.equal tag.word "plan") then None
        else if not (String.starts_with ~prefix:".plans/" path) then
          Some "a @plan tag stands only in a file under .plans/"
        else if tag.block <> 0 then
          Some "a @plan tag stands only in the first tag block of its file"
        else None
      in
      Option.map
        (fun detail ->
          Finding.make Finding_class.Misplaced_plan
            (Finding.Tag { path; position = start_of tag.span })
            ~place:(place path tag.span) ~detail ())
        detail)
    (tags documents)

(* {1 The classes of the facts} *)

let declaration_subject (declaration : Facts.declaration) =
  Finding.Fact
    { id = Facts.declaration_id declaration; ack_name = declaration.slug }

let edge_subject (edge : Facts.edge) =
  Finding.Fact { id = Facts.edge_id edge; ack_name = edge.target_text }

(* The text of a citation of the word [word] and the tag target
   [target], with the revision [rev] when it has one. *)
let citation ~word ~target rev =
  Printf.sprintf "@%s %s%s" word target
    (Option.fold ~none:"" ~some:(Printf.sprintf " v%d") rev)

(* The members of [items] that share their key, after the first, by
   the order of [order]: each with the first member of its group. *)
let later_of_groups ~key ~order items =
  let sorted = List.stable_sort order items in
  List.rev
    (snd
       (List.fold_left
          (fun (firsts, found) item ->
            match List.assoc_opt (key item) firsts with
            | Some first -> (firsts, (item, first) :: found)
            | None -> ((key item, item) :: firsts, found))
          ([], []) sorted))

let comes_first slug path line =
  Printf.sprintf "the slug %s comes first at %s:%d" slug path line

let duplicates facts =
  let by_place (path_a, (span_a : Markdown.span))
      (path_b, (span_b : Markdown.span)) =
    compare (path_a, span_a.start.line) (path_b, span_b.start.line)
  in
  let declarations =
    later_of_groups
      ~key:(fun (d : Facts.declaration) -> String.lowercase_ascii d.slug)
      ~order:(fun (a : Facts.declaration) (b : Facts.declaration) ->
        by_place (a.path, a.span) (b.path, b.span))
      (List.filter
         (fun (d : Facts.declaration) -> not (String.equal d.kind "rule"))
         (Facts.declarations facts))
  in
  let plans =
    later_of_groups
      ~key:(fun (plan : Facts.plan) -> String.lowercase_ascii plan.slug)
      ~order:(fun (a : Facts.plan) (b : Facts.plan) ->
        by_place (a.path, a.span) (b.path, b.span))
      (Facts.plans facts)
  in
  let tag path (span : Markdown.span) =
    Finding.Tag { path; position = span.start }
  in
  List.map
    (fun ((d : Facts.declaration), (first : Facts.declaration)) ->
      Finding.make Finding_class.Duplicate (tag d.path d.span)
        ~place:(place d.path d.span)
        ~detail:(comes_first first.slug first.path first.span.start.line)
        ())
    declarations
  @ List.map
      (fun ((plan : Facts.plan), (first : Facts.plan)) ->
        Finding.make Finding_class.Duplicate (tag plan.path plan.span)
          ~place:(place plan.path plan.span)
          ~detail:(comes_first first.slug first.path first.span.start.line)
          ())
      plans
  @ List.concat_map
      (fun (plan : Facts.plan) ->
        List.map
          (fun ((step : Facts.step), (first : Facts.step)) ->
            Finding.make Finding_class.Duplicate
              (Finding.Line { path = plan.path; line = step.span.start.line })
              ~place:(place plan.path step.span)
              ~detail:(comes_first first.slug plan.path first.span.start.line)
              ())
          (later_of_groups
             ~key:(fun (step : Facts.step) -> step.slug)
             ~order:(fun (a : Facts.step) (b : Facts.step) ->
               Int.compare a.span.start.line b.span.start.line)
             plan.steps))
      (Facts.plans facts)

let pinned_words = [ "satisfies"; "verifies"; "refines"; "supersedes" ]

let unpinned facts =
  let declarations = Array.of_list (Facts.declarations facts) in
  List.filter_map
    (fun ((edge : Facts.edge), target) ->
      if List.mem edge.word pinned_words && Option.is_none edge.rev then
        let fix =
          match target with
          | Facts.Declaration index ->
              Some
                (citation ~word:edge.word ~target:edge.target_text
                   (Some declarations.(index).Facts.rev))
          | Facts.Ref _ | Facts.Unresolved _ -> None
        in
        Some
          (Finding.make Finding_class.Unpinned (edge_subject edge)
             ~place:(place edge.path edge.span)
             ~detail:(Printf.sprintf "the @%s names no revision" edge.word)
             ?fix ())
      else None)
    (Facts.edges facts)

let dangling facts =
  let slugs =
    List.sort_uniq String.compare
      (List.filter_map
         (fun (d : Facts.declaration) ->
           if String.equal d.kind "rule" then None else Some d.slug)
         (Facts.declarations facts))
  in
  List.filter_map
    (fun ((edge : Facts.edge), target) ->
      match target with
      | Facts.Unresolved { dangling = true } ->
          let lower = String.lowercase_ascii edge.target_text in
          let fix =
            Option.map
              (fun slug -> citation ~word:edge.word ~target:slug edge.rev)
              (List.find_opt
                 (fun slug -> String.equal (String.lowercase_ascii slug) lower)
                 slugs)
          in
          Some
            (Finding.make Finding_class.Dangling (edge_subject edge)
               ~place:(place edge.path edge.span)
               ~detail:
                 (Printf.sprintf "no declaration has the slug %s"
                    edge.target_text)
               ?fix ())
      | Facts.Unresolved { dangling = false }
      | Facts.Declaration _ | Facts.Ref _ ->
          None)
    (Facts.edges facts)

let suspect facts =
  let declarations = Array.of_list (Facts.declarations facts) in
  List.filter_map
    (fun ((edge : Facts.edge), target) ->
      match (target, edge.rev) with
      | Facts.Declaration index, Some rev
        when declarations.(index).Facts.rev <> rev ->
          let declaration = declarations.(index) in
          Some
            (Finding.make Finding_class.Suspect (edge_subject edge)
               ~place:(place edge.path edge.span)
               ~detail:
                 (Printf.sprintf "the @%s names v%d, and %s is at v%d" edge.word
                    rev
                    (Facts.declaration_id declaration)
                    declaration.rev)
               ~fix:
                 (citation ~word:edge.word ~target:edge.target_text
                    (Some declaration.rev))
               ())
      | _ -> None)
    (Facts.edges facts)

let cycles facts =
  let declarations = Array.of_list (Facts.declarations facts) in
  let count = Array.length declarations in
  let successors = Array.make count [] in
  List.iter
    (fun ((edge : Facts.edge), target) ->
      match (edge.word, edge.source, target) with
      | ("refines" | "supersedes"), Some source, Facts.Declaration target ->
          successors.(source) <- target :: successors.(source)
      | _ -> ())
    (Facts.edges facts);
  (* [reach.(node)] is the set of the nodes that one edge or more lead
     to from [node]. *)
  let reach =
    Array.init count (fun node ->
        let seen = Array.make count false in
        let rec visit = function
          | [] -> ()
          | next :: rest ->
              if seen.(next) then visit rest
              else (
                seen.(next) <- true;
                visit (successors.(next) @ rest))
        in
        visit successors.(node);
        seen)
  in
  let order a b =
    compare
      ( Facts.declaration_id declarations.(a),
        declarations.(a).Facts.path,
        declarations.(a).span.start.line )
      ( Facts.declaration_id declarations.(b),
        declarations.(b).path,
        declarations.(b).span.start.line )
  in
  let members node =
    List.sort order
      (List.filter
         (fun other -> reach.(node).(other) && reach.(other).(node))
         (List.init count Fun.id))
  in
  List.filter_map
    (fun node ->
      match if reach.(node).(node) then members node else [] with
      | first :: others when first = node ->
          let declaration = declarations.(node) in
          let detail =
            match others with
            | [] -> None
            | _ ->
                Some
                  ("with "
                  ^ String.concat ", "
                      (List.map
                         (fun other ->
                           Facts.declaration_id declarations.(other))
                         others))
          in
          Some
            (Finding.make Finding_class.Cycle
               (declaration_subject declaration)
               ~place:(place declaration.path declaration.span)
               ?detail ())
      | _ -> None)
    (List.init count Fun.id)

(* The block hash of the block [index] of the document at [path]. *)
let block_hash documents path index =
  let document : Markdown.t = List.assoc path documents in
  document.blocks.(index).hash

let disendorsed facts documents =
  let declarations = Array.of_list (Facts.declarations facts) in
  List.filter_map
    (fun ((edge : Facts.edge), target) ->
      match target with
      | Facts.Declaration index
        when String.equal edge.word "cites"
             && not (Facts.is_in_force facts index) ->
          let declaration = declarations.(index) in
          let hash = block_hash documents edge.path edge.block_index in
          Some
            ( edge,
              Finding.make Finding_class.Disendorsed (edge_subject edge)
                ~place:(place edge.path edge.span)
                ~detail:
                  (Printf.sprintf "%s is %s"
                     (Facts.declaration_id declaration)
                     (Option.value declaration.status ~default:"superseded"))
                ~fix:
                  (Printf.sprintf "@ack disendorsed %s %s" edge.target_text
                     (String.sub hash 0 8))
                () )
      | _ -> None)
    (Facts.edges facts)

let orphans facts =
  List.filter_map
    (fun ((edge : Facts.edge), _) ->
      let detail =
        match (edge.word, edge.source) with
        | "verifies", _ -> Some "a @verifies needs a test as its source"
        | ("refines" | "supersedes"), None ->
            Some
              (Printf.sprintf "a @%s needs a declaration that holds it"
                 edge.word)
        | _ -> None
      in
      Option.map
        (fun detail ->
          Finding.make Finding_class.Orphan (edge_subject edge)
            ~place:(place edge.path edge.span)
            ~detail ())
        detail)
    (Facts.edges facts)

let uncovered facts =
  let edges = Facts.edges facts in
  let points_at word index =
    List.exists
      (fun ((edge : Facts.edge), target) ->
        String.equal edge.word word
        &&
        match target with
        | Facts.Declaration other -> other = index
        | Facts.Ref _ | Facts.Unresolved _ -> false)
      edges
  in
  List.filter_map Fun.id
    (List.mapi
       (fun index (declaration : Facts.declaration) ->
         let detail =
           match (points_at "satisfies" index, points_at "verifies" index) with
           | false, false ->
               Some "nothing satisfies it, and nothing verifies it"
           | false, true -> Some "nothing satisfies it"
           | true, false -> Some "nothing verifies it"
           | true, true -> None
         in
         if
           List.mem declaration.kind [ "req"; "design" ]
           && Facts.is_in_force facts index
         then
           Option.map
             (fun detail ->
               Finding.make Finding_class.Uncovered
                 (declaration_subject declaration)
                 ~place:(place declaration.path declaration.span)
                 ~detail ())
             detail
         else None)
       (Facts.declarations facts))

(* {1 The classes of plans} *)

(* The plain globs of a scope: the members that do not start with a
   [!]. *)
let plain scope =
  List.filter (fun glob -> not (String.starts_with ~prefix:"!" glob)) scope

(* [glob] with [**] after a [/] at its end, which means the same. *)
let full glob = if String.ends_with ~suffix:"/" glob then glob ^ "**" else glob

(* Whether the glob [inner] is contained in the glob [outer] by the
   rule of glob containment, where a glob that ends with [/] reads as
   the same glob with [**] added, and [**] holds every valid glob.
   [inner] is contained when it equals [outer]; when it is a literal
   path that [outer] matches; when it is a literal path prefix [<p>/]
   and [outer] is [<g>/**] and matches [<p>/x], so that [<g>] matches
   [<p>] or a leading part of it; or when [outer] is [<g>/**] and
   [inner] is [<g>/] and more segments. A glob that is not valid is
   contained only in itself. *)
let contained inner outer =
  let inner_full = full inner and outer_full = full outer in
  let folder =
    if String.ends_with ~suffix:"/**" outer_full then
      Some (String.sub outer_full 0 (String.length outer_full - 3))
    else None
  in
  String.equal inner_full outer_full
  ||
  match (Glob.of_string inner_full, Glob.of_string outer_full) with
  | Ok _, Ok outer_glob ->
      String.equal outer_full "**"
      ||
      if String.contains inner '*' then
        Option.fold ~none:false
          ~some:(fun prefix -> String.starts_with ~prefix:(prefix ^ "/") inner)
          folder
      else if String.ends_with ~suffix:"/" inner then
        Option.is_some folder && Glob.matches outer_glob (inner ^ "x")
      else Glob.matches outer_glob inner
  | Error _, _ | _, Error _ -> false

let bad_scopes facts =
  List.concat_map
    (fun (plan : Facts.plan) ->
      let outer = plain plan.scope in
      List.filter_map
        (fun (step : Facts.step) ->
          match step.own_scope with
          | None -> None
          | Some scope -> (
              match
                List.filter
                  (fun glob -> not (List.exists (contained glob) outer))
                  (plain scope)
              with
              | [] -> None
              | outside ->
                  Some
                    (Finding.make Finding_class.Bad_scope
                       (Finding.Fact
                          { id = Facts.step_id plan step; ack_name = step.slug })
                       ~place:(place plan.path step.span)
                       ~detail:
                         ("the scope of the plan does not hold "
                        ^ String.concat ", " outside)
                       ())))
        plan.steps)
    (Facts.plans facts)

(* Whether two scopes intersect: a plain glob of one contains a plain
   glob of the other, or is contained in it. *)
let intersect a b =
  List.exists
    (fun glob_a ->
      List.exists
        (fun glob_b -> contained glob_a glob_b || contained glob_b glob_a)
        (plain b))
    (plain a)

let scope_overlaps facts =
  List.concat_map
    (fun (plan : Facts.plan) ->
      let shares (a : Facts.step) (b : Facts.step) =
        intersect (Facts.effective_scope plan a) (Facts.effective_scope plan b)
        && List.exists
             (fun (promise : Facts.promise) ->
               List.exists
                 (fun (other : Facts.promise) ->
                   String.equal promise.word other.word
                   && String.equal promise.target other.target)
                 b.promises)
             a.promises
      in
      let rec walk earlier = function
        | [] -> []
        | (step : Facts.step) :: rest -> (
            match
              List.filter (fun other -> shares other step) (List.rev earlier)
            with
            | [] -> walk (step :: earlier) rest
            | others ->
                Finding.make Finding_class.Scope_overlap
                  (Finding.Fact
                     { id = Facts.step_id plan step; ack_name = step.slug })
                  ~place:(place plan.path step.span)
                  ~detail:
                    ("this step shares promises and scope with "
                    ^ String.concat ", " (List.map (Facts.step_id plan) others)
                    )
                  ()
                :: walk (step :: earlier) rest)
      in
      walk [] plan.steps)
    (Facts.plans facts)

let promise_subject plan step promise =
  let id = Facts.promise_id plan step promise in
  Finding.Fact { id; ack_name = id }

let unverified_promises facts =
  List.concat_map
    (fun (plan : Facts.plan) ->
      let verified =
        List.concat_map
          (fun (step : Facts.step) ->
            List.filter_map
              (fun (promise : Facts.promise) ->
                if String.equal promise.word "verifies" then Some promise.target
                else None)
              step.promises)
          plan.steps
      in
      List.concat_map
        (fun (step : Facts.step) ->
          List.filter_map
            (fun (promise : Facts.promise) ->
              if
                List.mem promise.word [ "req"; "design" ]
                && not (List.mem promise.target verified)
              then
                Some
                  (Finding.make Finding_class.Unverified_promise
                     (promise_subject plan step promise)
                     ~place:(place plan.path promise.span)
                     ~detail:
                       (Printf.sprintf "the plan promises no @verifies %s"
                          promise.target)
                     ())
              else None)
            step.promises)
        plan.steps)
    (Facts.plans facts)

let promises_out_of_scope facts =
  List.concat_map
    (fun (plan : Facts.plan) ->
      List.concat_map
        (fun (step : Facts.step) ->
          List.filter_map
            (fun (promise : Facts.promise) ->
              match Facts.discharge facts plan step promise with
              | { by = None; residue = first :: _ } ->
                  Some
                    (Finding.make Finding_class.Promise_out_of_scope
                       (promise_subject plan step promise)
                       ~place:(place plan.path promise.span)
                       ~detail:
                         (Printf.sprintf
                            "%s at %s:%d is outside the scope of the step"
                            first.id first.path first.span.start.line)
                       ())
              | { by = Some _; _ } | { residue = []; _ } -> None)
            step.promises)
        plan.steps)
    (Facts.plans facts)

(* {1 The global rules} *)

(* The class and the subject that the tag target of an ack names: the
   first token, and the rest without the spaces and tabs at its
   ends. *)
let ack_target target =
  let blank = function ' ' | '\t' -> true | _ -> false in
  let length = String.length target in
  let rec token_end index =
    if index < length && not (blank target.[index]) then token_end (index + 1)
    else index
  in
  let stop = token_end 0 in
  let rec rest_start index =
    if index < length && blank target.[index] then rest_start (index + 1)
    else index
  in
  let start = rest_start stop in
  ( String.sub target 0 stop,
    if start = length then None
    else Some (String.sub target start (length - start)) )

(* Whether a live ack of the block of [edge] discharges its disendorsed
   finding: the hash of the ack is eight or more of the first digits of
   the block hash, and its tag target is the class and, when it gives
   one, the tag target of the edge. *)
let acked facts documents (edge : Facts.edge) =
  let hash = block_hash documents edge.path edge.block_index in
  List.exists
    (fun (ack : Facts.ack) ->
      let finding_class, subject = ack_target ack.target in
      String.equal ack.path edge.path
      && ack.block_index = edge.block_index
      && String.length ack.hash >= 8
      && String.starts_with ~prefix:ack.hash hash
      && String.equal finding_class "disendorsed"
      && Option.fold ~none:true ~some:(String.equal edge.target_text) subject)
    (Facts.acks facts)

let historical manifest (finding : Finding.t) =
  List.exists
    (fun (place : Finding.place) -> Manifest.is_historical manifest place.path)
    (Option.to_list finding.place)

let tree manifest documents ~not_text =
  let facts = Facts.make manifest documents in
  List.sort Finding.compare
    (List.filter
       (fun finding -> not (historical manifest finding))
       (List.concat
          [
            parse_errors documents ~not_text;
            typo_tags documents;
            unread_tags documents;
            bad_targets manifest documents;
            misplaced_plans documents;
            duplicates facts;
            unpinned facts;
            dangling facts;
            suspect facts;
            cycles facts;
            List.filter_map
              (fun (edge, finding) ->
                if acked facts documents edge then None else Some finding)
              (disendorsed facts documents);
            orphans facts;
            uncovered facts;
            bad_scopes facts;
            scope_overlaps facts;
            unverified_promises facts;
            promises_out_of_scope facts;
          ]))
