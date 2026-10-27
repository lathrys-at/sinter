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

let tags documents =
  List.concat_map
    (fun (path, (document : Markdown.t)) ->
      List.map (fun tag -> (path, tag)) (Array.to_list document.tags))
    documents

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

let nearest_word word =
  if List.mem word vocabulary then None
  else Edit_distance.nearest word vocabulary

let typo_tags documents =
  List.filter_map
    (fun (path, (tag : Markdown.tag)) ->
      Option.map
        (fun nearest ->
          Finding.make Finding_class.Typo_tag
            (Finding.Line { path; line = tag.span.start.line })
            ~place:(place path tag.span)
            ~detail:(Printf.sprintf "@%s is not a tag word of sinter" tag.word)
            ~fix:("@" ^ nearest) ())
        (nearest_word tag.word))
    (tags documents)

let ignored_tags documents =
  List.concat_map
    (fun (path, (document : Markdown.t)) ->
      List.map
        (fun (span : Markdown.span) ->
          Finding.make Finding_class.Ignored_tag
            (Finding.Line { path; line = span.start.line })
            ~place:(place path span)
            ~detail:
              "sinter reads tags only in the first paragraph of a section or a \
               list item"
            ())
        document.unread)
    documents

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
        match List.assoc_opt ns (Manifest.namespaces manifest) with
        | None when String.equal ns "" ->
            Some (Printf.sprintf "the external id %s names no namespace" target)
        | None ->
            Some (Printf.sprintf "the manifest declares no namespace %s" ns)
        | Some _ when String.equal id "" ->
            Some (Printf.sprintf "the external id %s names no id" target)
        | Some pattern ->
            if Id_pattern.matches pattern id then None
            else
              Some
                (Printf.sprintf
                   "%s does not match the id pattern of the namespace %s" id ns)
        )
  else if List.mem word ("plan" :: declaration_words) then slug ()
  else None

let invalid_targets manifest documents =
  List.filter_map
    (fun (path, (tag : Markdown.tag)) ->
      Option.bind tag.target (fun target ->
          Option.map
            (fun detail ->
              Finding.make Finding_class.Invalid_target
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

let declaration_subject (declaration : Facts.declaration) =
  Finding.Fact
    { id = Facts.declaration_id declaration; ack_name = declaration.slug }

let edge_subject (edge : Facts.edge) =
  Finding.Fact { id = Facts.edge_id edge; ack_name = edge.target_text }

let citation ~word ~target rev =
  Printf.sprintf "@%s %s%s" word target
    (Option.fold ~none:"" ~some:(Printf.sprintf " v%d") rev)

module Keys = Map.Make (String)

let later_of_groups ~key ~order items =
  let sorted = List.stable_sort order items in
  List.rev
    (snd
       (List.fold_left
          (fun (firsts, found) item ->
            match Keys.find_opt (key item) firsts with
            | Some first -> (firsts, (item, first) :: found)
            | None -> (Keys.add (key item) item firsts, found))
          (Keys.empty, []) sorted))

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
          | Facts.External _ | Facts.Unresolved _ -> None
        in
        Some
          (Finding.make Finding_class.Unpinned (edge_subject edge)
             ~place:(place edge.path edge.span)
             ~detail:(Printf.sprintf "the @%s names no revision" edge.word)
             ?fix ())
      else None)
    (Facts.edges facts)

let spellings facts =
  let spellings =
    List.fold_left
      (fun spellings slug ->
        Keys.update
          (String.lowercase_ascii slug)
          (function None -> Some slug | kept -> kept)
          spellings)
      Keys.empty
      (List.sort_uniq String.compare
         (List.filter_map
            (fun (d : Facts.declaration) ->
              if String.equal d.kind "rule" then None else Some d.slug)
            (Facts.declarations facts)))
  in
  fun target -> Keys.find_opt (String.lowercase_ascii target) spellings

let declared_spelling facts =
  let resolve = lazy (Facts.resolve facts)
  and spelling = lazy (spellings facts) in
  fun target ->
    match Lazy.force resolve target with
    | Facts.Unresolved { dangling = true } -> Lazy.force spelling target
    | Facts.Unresolved { dangling = false }
    | Facts.Declaration _ | Facts.External _ ->
        None

let dangling facts =
  let spelling = spellings facts in
  List.filter_map
    (fun ((edge : Facts.edge), target) ->
      match target with
      | Facts.Unresolved { dangling = true } ->
          let fix =
            Option.map
              (fun slug -> citation ~word:edge.word ~target:slug edge.rev)
              (spelling edge.target_text)
          in
          Some
            (Finding.make Finding_class.Dangling (edge_subject edge)
               ~place:(place edge.path edge.span)
               ~detail:
                 (Printf.sprintf "no declaration has the slug %s"
                    edge.target_text)
               ?fix ())
      | Facts.Unresolved { dangling = false }
      | Facts.Declaration _ | Facts.External _ ->
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

type visit = { number : int; mutable low : int; mutable on_stack : bool }
type call = Start of int list | Visit of int * visit * int list

let components successors =
  let visits = Array.make (Array.length successors) None in
  let next =
    ref
      (0
      [@mutaml.skip
        "the numbers of arrival only order the nodes, so every first number \
         gives the same components"])
  in
  let stack = ref [] in
  let found = ref [] in
  let enter node =
    let visit = { number = !next; low = !next; on_stack = true } in
    visits.(node) <- Some visit;
    incr next;
    stack := (node, visit) :: !stack;
    visit
  in
  let rec pop root members =
    match !stack with
    | [] -> members
    | (node, visit) :: rest ->
        stack := rest;
        visit.on_stack <- false;
        if node = root then node :: members else pop root (node :: members)
  in
  let rec run = function
    | [] -> ()
    | Start [] :: calls -> run calls
    | Start (node :: rest) :: calls -> (
        match visits.(node) with
        | Some _ -> run (Start rest :: calls)
        | None ->
            let visit = enter node in
            run (Visit (node, visit, successors.(node)) :: Start rest :: calls))
    | Visit (node, visit, successor :: rest) :: calls -> (
        match visits.(successor) with
        | Some reached ->
            if reached.on_stack then visit.low <- min visit.low reached.number;
            run (Visit (node, visit, rest) :: calls)
        | None ->
            let reached = enter successor in
            run
              (Visit (successor, reached, successors.(successor))
              :: Visit (node, visit, rest)
              :: calls))
    | Visit (node, visit, []) :: calls ->
        (match calls with
        | Visit (_, caller, _) :: _ -> caller.low <- min caller.low visit.low
        | Start _ :: _ | [] -> ());
        if visit.low = visit.number then found := pop node [] :: !found;
        run calls
  in
  run [ Start (List.init (Array.length successors) Fun.id) ];
  !found

let cycles facts =
  let declarations = Array.of_list (Facts.declarations facts) in
  let successors = Array.make (Array.length declarations) [] in
  List.iter
    (fun ((edge : Facts.edge), target) ->
      match (edge.word, edge.source, target) with
      | ("refines" | "supersedes"), Some source, Facts.Declaration target ->
          successors.(source) <- target :: successors.(source)
      | _ -> ())
    (Facts.edges facts);
  let order a b =
    compare
      ( Facts.declaration_id declarations.(a),
        declarations.(a).Facts.path,
        declarations.(a).span.start.line )
      ( Facts.declaration_id declarations.(b),
        declarations.(b).path,
        declarations.(b).span.start.line )
  in
  List.filter_map
    (fun component ->
      match List.sort order component with
      | [] -> None
      | [ node ] when not (List.mem node successors.(node)) -> None
      | first :: others ->
          let declaration = declarations.(first) in
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
               ?detail ()))
    (components successors)

let retired facts =
  let declarations = Array.of_list (Facts.declarations facts) in
  List.filter_map
    (fun ((edge : Facts.edge), target) ->
      match target with
      | Facts.Declaration index
        when String.equal edge.word "cites"
             && not (Facts.is_in_force facts index) ->
          let declaration = declarations.(index) in
          let finding =
            Finding.make Finding_class.Retired (edge_subject edge)
              ~place:(place edge.path edge.span)
          in
          Some
            ( edge,
              match
                ( List.map (Array.get declarations)
                    (Facts.successors facts index),
                  declaration.status )
              with
              | [], Some status ->
                  let hash =
                    Facts.block_hash facts edge.path edge.block_index
                  in
                  finding
                    ~detail:
                      (Printf.sprintf "%s is %s"
                         (Facts.declaration_id declaration)
                         status)
                    ~fix:
                      (Printf.sprintf "@ack retired %s %s" edge.target_text
                         (String.sub hash 0 8))
                    ~ackable:true ()
              | successors, _ ->
                  finding
                    ~detail:
                      (Printf.sprintf "%s is superseded by %s"
                         (Facts.declaration_id declaration)
                         (String.concat ", "
                            (List.map Facts.declaration_id successors)))
                    ~fix:
                      (String.concat " or "
                         (List.map
                            (fun (successor : Facts.declaration) ->
                              citation ~word:edge.word ~target:successor.slug
                                (Option.map (fun _ -> successor.rev) edge.rev))
                            successors))
                    ~ackable:false () )
      | _ -> None)
    (Facts.edges facts)

let wrong_sources facts =
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
          Finding.make Finding_class.Wrong_source (edge_subject edge)
            ~place:(place edge.path edge.span)
            ~detail ())
        detail)
    (Facts.edges facts)

let untraced facts =
  let count = List.length (Facts.declarations facts) in
  let satisfied = Array.make count false
  and verified = Array.make count false in
  List.iter
    (fun ((edge : Facts.edge), target) ->
      match (edge.word, target) with
      | "satisfies", Facts.Declaration index -> satisfied.(index) <- true
      | "verifies", Facts.Declaration index -> verified.(index) <- true
      | _ -> ())
    (Facts.edges facts);
  List.filter_map Fun.id
    (List.mapi
       (fun index (declaration : Facts.declaration) ->
         let detail =
           match (satisfied.(index), verified.(index)) with
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
               Finding.make Finding_class.Untraced
                 (declaration_subject declaration)
                 ~place:(place declaration.path declaration.span)
                 ~detail ())
             detail
         else None)
       (Facts.declarations facts))

let plain scope =
  List.filter (fun glob -> not (String.starts_with ~prefix:"!" glob)) scope

let full glob = if String.ends_with ~suffix:"/" glob then glob ^ "**" else glob

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

let scopes_outside_plans facts =
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
                    (Finding.make Finding_class.Scope_outside_plan
                       (Finding.Fact
                          { id = Facts.step_id plan step; ack_name = step.slug })
                       ~place:(place plan.path step.span)
                       ~detail:
                         ("the scope of the plan does not hold "
                        ^ String.concat ", " outside)
                       ())))
        plan.steps)
    (Facts.plans facts)

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
          let standing = Facts.standing facts plan step in
          List.filter_map
            (fun (promise : Facts.promise) ->
              match standing promise with
              | { by = None; meeting_facts = first :: _ } ->
                  Some
                    (Finding.make Finding_class.Promise_out_of_scope
                       (promise_subject plan step promise)
                       ~place:(place plan.path promise.span)
                       ~detail:
                         (Printf.sprintf
                            "%s at %s:%d is outside the scope of the step"
                            first.id first.path first.span.start.line)
                       ())
              | { by = Some _; _ } | { meeting_facts = []; _ } -> None)
            step.promises)
        plan.steps)
    (Facts.plans facts)

let ack_target target =
  let blank = function ' ' | '\t' -> true | _ -> false in
  let length = String.length target in
  let rec token_end index =
    if index < length && not (blank target.[index]) then token_end (index + 1)
    else index
  in
  let stop =
    token_end
      (0
      [@mutaml.skip
        "the tag target of an ack never starts with a space or a tab, so the \
         first token ends at the same place when the scan starts at 1"])
  in
  let rec rest_start index =
    if index < length && blank target.[index] then rest_start (index + 1)
    else index
  in
  let start = rest_start stop in
  ( String.sub target 0 stop,
    if start = length then None
    else Some (String.sub target start (length - start)) )

let acked facts (edge : Facts.edge) =
  let hash = Facts.block_hash facts edge.path edge.block_index in
  List.exists
    (fun (ack : Facts.ack) ->
      let finding_class, subject = ack_target ack.target in
      String.length ack.hash >= 8
      && String.starts_with ~prefix:ack.hash hash
      && String.equal finding_class "retired"
      && Option.fold ~none:true ~some:(String.equal edge.target_text) subject)
    (Facts.block_acks facts edge.path edge.block_index)

let historical manifest (finding : Finding.t) =
  List.exists
    (fun (place : Finding.place) -> Manifest.is_historical manifest place.path)
    (Option.to_list finding.place)

let of_facts facts ~not_text =
  let manifest = Facts.manifest facts and documents = Facts.files facts in
  List.sort Finding.compare
    (List.filter
       (fun finding -> not (historical manifest finding))
       (List.concat
          [
            parse_errors documents ~not_text;
            typo_tags documents;
            ignored_tags documents;
            invalid_targets manifest documents;
            misplaced_plans documents;
            duplicates facts;
            unpinned facts;
            dangling facts;
            suspect facts;
            cycles facts;
            List.filter_map
              (fun (edge, (finding : Finding.t)) ->
                if finding.ackable && acked facts edge then None
                else Some finding)
              (retired facts);
            wrong_sources facts;
            untraced facts;
            scopes_outside_plans facts;
            scope_overlaps facts;
            unverified_promises facts;
            promises_out_of_scope facts;
          ]))

let tree ?phases manifest documents ~not_text =
  let facts =
    Allocation.measure phases "facts" (fun () -> Facts.make manifest documents)
  in
  Allocation.measure phases "findings" (fun () -> of_facts facts ~not_text)
