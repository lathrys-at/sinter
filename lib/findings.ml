(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

let declaration_words = [ "req"; "design"; "decision"; "rule" ]

let citation_words =
  [ "satisfies"; "verifies"; "refines"; "cites"; "supersedes" ]

let vocabulary =
  declaration_words @ citation_words
  @ [
      "plan"; "deprecated"; "rejected"; "deferred"; "delivered"; "ack"; "scope";
    ]

let start_of (span : Markdown.span) = span.start
let place path span = { Finding.path; span }
let related label path span = { Finding.label; place = Some (place path span) }

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
            ~fix:(Fix.word tag nearest)
            ?mark:(Finding.part tag Tag_line.Word "not a tag word")
            ())
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

let not_a_slug slug =
  Some (Printf.sprintf "%s is not a valid slug" slug, "not a valid slug")

let target_problem manifest ~word target =
  let slug () = if Slug.is_valid target then None else not_a_slug target in
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
            Some
              ( Printf.sprintf "the external id %s names no namespace" target,
                "names no namespace" )
        | None ->
            Some
              ( Printf.sprintf "the manifest declares no namespace %s" ns,
                "no such namespace" )
        | Some _ when String.equal id "" ->
            Some
              ( Printf.sprintf "the external id %s names no id" target,
                "names no id" )
        | Some pattern ->
            if Id_pattern.matches pattern id then None
            else
              Some
                ( Printf.sprintf
                    "%s does not match the id pattern of the namespace %s" id ns,
                  "does not match the id pattern" ))
  else if String.equal word "plan" then
    match Plan_target.parse target with
    | Ok _ -> None
    | Error (Plan_target.Invalid_slug "") ->
        Some
          ( Printf.sprintf "%s has no slug before the @" target,
            "no slug before the @" )
    | Error (Plan_target.Invalid_slug slug) -> not_a_slug slug
    | Error (Plan_target.Invalid_id _) ->
        Some
          ( Printf.sprintf
              "the plan id after the @ in %s is not six lowercase hex digits"
              target,
            "not a valid plan id" )
  else if List.mem word declaration_words then slug ()
  else if String.equal word "delivered" then
    if Option.is_some (Plan_target.id_of_string target) then None
    else
      Some
        ( Printf.sprintf
            "the hash %s of the mark is not six lowercase hex digits" target,
          "not six lowercase hex digits" )
  else None

let invalid_targets manifest documents =
  List.filter_map
    (fun (path, (tag : Markdown.tag)) ->
      match tag.target with
      | None when String.equal tag.word "delivered" ->
          Some
            (Finding.make Finding_class.Invalid_target
               (Finding.Tag { path; position = start_of tag.span })
               ~place:(place path tag.span) ~detail:"the mark names no hash"
               ?mark:(Finding.part tag Tag_line.Word "no hash")
               ())
      | _ ->
          Option.bind tag.target (fun target ->
              Option.map
                (fun (detail, label) ->
                  Finding.make Finding_class.Invalid_target
                    (Finding.Tag { path; position = start_of tag.span })
                    ~place:(place path tag.span) ~detail
                    ?mark:(Finding.part tag Tag_line.Target label)
                    ())
                (target_problem manifest ~word:tag.word target)))
    (tags documents)

module Places = Set.Make (struct
  type t = string * int

  let compare = compare
end)

let marked facts =
  List.fold_left
    (fun places (plan : Facts.plan) ->
      List.fold_left
        (fun places (step : Facts.step) ->
          List.fold_left
            (fun places (tag : Markdown.tag) ->
              Places.add (plan.path, tag.span.start.line) places)
            places step.marks)
        places plan.steps)
    Places.empty (Facts.plans facts)

let misplaced_plans facts documents =
  let marked = lazy (marked facts) in
  List.filter_map
    (fun (path, (tag : Markdown.tag)) ->
      let written =
        match tag.target with
        | Some target -> "@" ^ tag.word ^ " " ^ target
        | None -> "@" ^ tag.word
      in
      let detail =
        if String.equal tag.word "delivered" then
          if Places.mem (path, tag.span.start.line) (Lazy.force marked) then
            None
          else
            Some
              ( Printf.sprintf "%s is not in the tag block of a step" written,
                "not in the tag block of a step" )
        else if not (String.equal tag.word "plan") then None
        else if not (String.starts_with ~prefix:".plans/" path) then
          Some
            ( Printf.sprintf "%s is not in a file under .plans/" written,
              "not in a file under .plans/" )
        else if tag.block <> 0 then
          Some
            ( Printf.sprintf "%s is not in the first tag block of its file"
                written,
              "not in the first tag block" )
        else None
      in
      Option.map
        (fun (detail, label) ->
          Finding.make Finding_class.Misplaced_plan
            (Finding.Tag { path; position = start_of tag.span })
            ~place:(place path tag.span) ~detail
            ?mark:(Finding.part tag Tag_line.Word label)
            ())
        detail)
    (tags documents)

let declaration_subject (declaration : Facts.declaration) =
  Finding.Fact
    { id = Facts.declaration_id declaration; ack_name = declaration.slug }

let edge_subject (edge : Facts.edge) =
  Finding.Fact { id = Facts.edge_id edge; ack_name = edge.target_text }

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

let declared_again = "declared again here"
let first_declared = "first declared here"

let declared_earlier slug item =
  Printf.sprintf "the slug %s of %s is declared earlier" slug item

let is_open (_ : Facts.plan) = true

let plan_duplicates facts =
  let by_place (a : Facts.plan) (b : Facts.plan) =
    compare (a.path, a.span.start.line) (b.path, b.span.start.line)
  in
  let plans = Facts.plans facts in
  let full =
    later_of_groups ~key:Facts.full_form ~order:by_place plans
    |> List.map (fun ((plan : Facts.plan), (first : Facts.plan)) ->
        ( plan,
          ( first,
            Printf.sprintf "a plan with the full form %s is declared earlier"
              (Facts.full_form first) ) ))
  in
  let reported (plan : Facts.plan) =
    List.exists (fun (p, _) -> p == plan) full
  in
  let slug =
    later_of_groups
      ~key:(fun (plan : Facts.plan) -> String.lowercase_ascii plan.slug)
      ~order:by_place
      (List.filter is_open plans)
    |> List.filter_map (fun ((plan : Facts.plan), (first : Facts.plan)) ->
        if reported plan then None
        else
          Some
            ( plan,
              ( first,
                Printf.sprintf
                  "an open plan with the slug %s is declared earlier" first.slug
              ) ))
  in
  full @ slug

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
  let plans = plan_duplicates facts in
  let tag path (span : Markdown.span) =
    Finding.Tag { path; position = span.start }
  in
  List.map
    (fun ((d : Facts.declaration), (first : Facts.declaration)) ->
      Finding.make Finding_class.Duplicate (tag d.path d.span)
        ~place:(place d.path d.span)
        ~detail:(declared_earlier d.slug (Facts.declaration_id d))
        ?mark:(Finding.part d.tag Tag_line.Target declared_again)
        ~related:[ related first_declared first.path first.span ]
        ())
    declarations
  @ List.map
      (fun ((plan : Facts.plan), ((first : Facts.plan), detail)) ->
        Finding.make Finding_class.Duplicate (tag plan.path plan.span)
          ~place:(place plan.path plan.span)
          ~detail
          ?mark:(Finding.part plan.tag Tag_line.Target declared_again)
          ~related:[ related first_declared first.path first.span ]
          ())
      plans
  @ List.concat_map
      (fun (plan : Facts.plan) ->
        List.concat_map
          (fun (step : Facts.step) ->
            match step.marks with
            | first :: later ->
                List.map
                  (fun (again : Markdown.tag) ->
                    Finding.make Finding_class.Duplicate
                      (tag plan.path again.span)
                      ~place:(place plan.path again.span)
                      ~detail:
                        (Printf.sprintf "%s holds a mark earlier"
                           (Facts.step_id plan step))
                      ?mark:
                        (Finding.part again Tag_line.Word "marked again here")
                      ~related:
                        [ related "the mark of the step" plan.path first.span ]
                      ())
                  later
            | [] -> [])
          plan.steps)
      (Facts.plans facts)
  @ List.concat_map
      (fun (plan : Facts.plan) ->
        List.map
          (fun ((step : Facts.step), (first : Facts.step)) ->
            Finding.make Finding_class.Duplicate
              (Finding.Line { path = plan.path; line = step.span.start.line })
              ~place:(place plan.path step.span)
              ~detail:(declared_earlier step.slug (Facts.step_id plan step))
              ~related:[ related first_declared plan.path first.span ]
              ())
          (later_of_groups
             ~key:(fun (step : Facts.step) -> step.slug)
             ~order:(fun (a : Facts.step) (b : Facts.step) ->
               Int.compare a.span.start.line b.span.start.line)
             plan.steps))
      (Facts.plans facts)

let missing_plan_ids facts ~base =
  List.filter_map
    (fun (plan : Facts.plan) ->
      match plan.id with
      | Some _ -> None
      | None when not (is_open plan) -> None
      | None ->
          Some
            (Finding.make Finding_class.Missing_plan_id
               (Finding.Fact
                  { id = Facts.plan_fact_id plan; ack_name = plan.slug })
               ~place:(place plan.path plan.span)
               ~detail:(Printf.sprintf "the plan %s has no plan id" plan.slug)
               ~fix:
                 (Fix.plan_id plan.tag
                    (Plan_target.derive ~base ~path:plan.path))
               ?mark:(Finding.part plan.tag Tag_line.Target "no plan id")
               ()))
    (Facts.plans facts)

let pinned_words = [ "satisfies"; "verifies"; "refines"; "supersedes" ]

let unpinned facts =
  let declarations = Array.of_list (Facts.declarations facts) in
  List.filter_map
    (fun ((edge : Facts.edge), target) ->
      if List.mem edge.word pinned_words && Option.is_none edge.rev then
        let fix, named =
          match target with
          | Facts.Declaration index ->
              let declaration = declarations.(index) in
              ( Some (Fix.pin edge.tag declaration.rev),
                [
                  related
                    (Printf.sprintf "declared here at v%d" declaration.rev)
                    declaration.path declaration.span;
                ] )
          | Facts.External _ | Facts.Unresolved _ -> (None, [])
        in
        Some
          (Finding.make Finding_class.Unpinned (edge_subject edge)
             ~place:(place edge.path edge.span)
             ~detail:
               (Printf.sprintf "@%s %s names no revision" edge.word
                  edge.target_text)
             ?fix
             ?mark:(Finding.part edge.tag Tag_line.Target "no revision")
             ~related:named ())
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
            Option.map (Fix.spelling edge.tag) (spelling edge.target_text)
          in
          Some
            (Finding.make Finding_class.Dangling (edge_subject edge)
               ~place:(place edge.path edge.span)
               ~detail:
                 (Printf.sprintf "no declaration has the slug %s"
                    edge.target_text)
               ?fix
               ?mark:
                 (Finding.part edge.tag Tag_line.Target
                    "no declaration has this slug")
               ())
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
               ~fix:(Fix.pin edge.tag declaration.rev)
               ?mark:
                 (Finding.part edge.tag Tag_line.Revision
                    (Printf.sprintf "names v%d" rev))
               ~related:
                 [
                   related
                     (Printf.sprintf "now at v%d" declaration.rev)
                     declaration.path declaration.span;
                 ]
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
            Printf.sprintf "%s is in a cycle with %s"
              (Facts.declaration_id declaration)
              (match others with
              | [] -> "itself"
              | _ ->
                  String.concat ", "
                    (List.map
                       (fun other -> Facts.declaration_id declarations.(other))
                       others))
          in
          Some
            (Finding.make Finding_class.Cycle
               (declaration_subject declaration)
               ~place:(place declaration.path declaration.span)
               ~detail
               ~related:
                 (List.map
                    (fun other ->
                      let member = declarations.(other) in
                      related "part of the cycle" member.Facts.path member.span)
                    others)
               ()))
    (components successors)

let retired facts =
  let declarations = Array.of_list (Facts.declarations facts) in
  let documents =
    lazy
      (List.fold_left
         (fun documents (path, document) ->
           Keys.update path
             (function None -> Some document | kept -> kept)
             documents)
         Keys.empty (Facts.files facts))
  in
  List.filter_map
    (fun ((edge : Facts.edge), target) ->
      match target with
      | Facts.Declaration index
        when String.equal edge.word "cites"
             && not (Facts.is_in_force facts index) ->
          let declaration = declarations.(index) in
          let successors =
            List.map (Array.get declarations) (Facts.successors facts index)
          in
          let finding state =
            Finding.make Finding_class.Retired (edge_subject edge)
              ~place:(place edge.path edge.span)
              ?mark:
                (Finding.part edge.tag Tag_line.Target "cites a retired item")
              ~related:
                (related
                   ("the cited item is " ^ state)
                   declaration.path declaration.span
                :: List.map
                     (fun (successor : Facts.declaration) ->
                       related "a successor" successor.path successor.span)
                     successors)
          in
          Some
            ( edge,
              match (successors, declaration.status) with
              | [], Some status ->
                  finding status
                    ~detail:
                      (Printf.sprintf "%s is %s"
                         (Facts.declaration_id declaration)
                         status)
                    ~fix:
                      (Fix.ack
                         (Keys.find edge.path (Lazy.force documents))
                         ~block:edge.block_index ~target:edge.target_text)
                    ~ackable:true ()
              | successors, _ ->
                  let written (successor : Facts.declaration) =
                    (successor.slug, successor.rev)
                  in
                  finding "superseded"
                    ~detail:
                      (Printf.sprintf "%s is superseded by %s"
                         (Facts.declaration_id declaration)
                         (String.concat ", "
                            (List.map Facts.declaration_id successors)))
                    ?fix:
                      (match successors with
                      | first :: others ->
                          Some
                            (Fix.successors edge.tag (written first)
                               (List.map written others))
                      | [] -> None)
                    ~ackable:false () )
      | _ -> None)
    (Facts.edges facts)

let wrong_sources facts =
  List.filter_map
    (fun ((edge : Facts.edge), _) ->
      let detail =
        match (edge.word, edge.source) with
        | "verifies", _ ->
            Some
              ( Printf.sprintf "@verifies %s needs a test as its source"
                  edge.target_text,
                "needs a test as its source" )
        | ("refines" | "supersedes"), None ->
            Some
              ( Printf.sprintf "@%s %s needs a declaration that holds it"
                  edge.word edge.target_text,
                "needs a declaration that holds it" )
        | _ -> None
      in
      Option.map
        (fun (detail, label) ->
          Finding.make Finding_class.Wrong_source (edge_subject edge)
            ~place:(place edge.path edge.span)
            ~detail
            ?mark:(Finding.part edge.tag Tag_line.Word label)
            ())
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
         let item = Facts.declaration_id declaration in
         let found =
           match (satisfied.(index), verified.(index)) with
           | false, false ->
               Some
                 ( Printf.sprintf
                     "nothing satisfies %s, and nothing verifies it" item,
                   "nothing satisfies it, and nothing verifies it" )
           | false, true ->
               Some
                 ( Printf.sprintf "nothing satisfies %s" item,
                   "nothing satisfies it" )
           | true, false ->
               Some
                 ( Printf.sprintf "nothing verifies %s" item,
                   "nothing verifies it" )
           | true, true -> None
         in
         if
           List.mem declaration.kind [ "req"; "design" ]
           && Facts.is_in_force facts index
         then
           Option.map
             (fun (detail, label) ->
               Finding.make Finding_class.Untraced
                 (declaration_subject declaration)
                 ~place:(place declaration.path declaration.span)
                 ~detail
                 ?mark:(Finding.part declaration.tag Tag_line.Target label)
                 ())
             found
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
                         (Printf.sprintf
                            "%s has %s in its scope, outside the scope of the \
                             plan"
                            (Facts.step_id plan step)
                            (String.concat ", " outside))
                       ())))
        plan.steps)
    (Facts.plans facts)

let steps_without_promises facts =
  if Manifest.step (Facts.manifest facts) <> Manifest.Promises then []
  else
    List.concat_map
      (fun (plan : Facts.plan) ->
        if not (is_open plan) then []
        else
          List.filter_map
            (fun (step : Facts.step) ->
              if step.promises <> [] then None
              else
                Some
                  (Finding.make Finding_class.Step_without_promises
                     (Finding.Fact
                        { id = Facts.step_id plan step; ack_name = step.slug })
                     ~place:(place plan.path step.span)
                     ~detail:
                       (Printf.sprintf
                          "%s has no promise, and proof.step is \"promises\""
                          (Facts.step_id plan step))
                     ()))
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
                    (Printf.sprintf "%s shares promises and scope with %s"
                       (Facts.step_id plan step)
                       (String.concat ", "
                          (List.map (Facts.step_id plan) others)))
                  ~related:
                    (List.map
                       (fun (other : Facts.step) ->
                         related "shares promises and scope" plan.path
                           other.span)
                       others)
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
                     ?mark:
                       (Finding.part promise.tag Tag_line.Target
                          "no promised @verifies")
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
              | { by = None; meeting_facts = _ :: _ as meeting_facts } ->
                  Some
                    (Finding.make Finding_class.Promise_out_of_scope
                       (promise_subject plan step promise)
                       ~place:(place plan.path promise.span)
                       ~detail:
                         (Printf.sprintf
                            "the promise %s:%s is met only outside the scope \
                             of %s"
                            promise.word promise.target
                            (Facts.step_id plan step))
                       ?mark:
                         (Finding.part promise.tag Tag_line.Target
                            "met only outside the scope of the step")
                       ~related:
                         (List.map
                            (fun (fact : Facts.meeting_fact) ->
                              related "meets the promise outside the scope"
                                fact.path fact.span)
                            meeting_facts)
                       ())
              | { by = Some _; _ } | { meeting_facts = []; _ } -> None)
            step.promises)
        plan.steps)
    (Facts.plans facts)

let step_subject plan (step : Facts.step) =
  Finding.Fact { id = Facts.step_id plan step; ack_name = step.slug }

let stale_marks facts =
  List.concat_map
    (fun (plan : Facts.plan) ->
      if not (is_open plan) then []
      else
        List.filter_map
          (fun (step : Facts.step) ->
            match Facts.mark step with
            | Some ({ target = Some target; _ } as tag)
              when Option.is_some (Plan_target.id_of_string target)
                   && not (Facts.delivered step) ->
                let hash = Facts.mark_hash step in
                Some
                  (Finding.make Finding_class.Stale_mark
                     (step_subject plan step) ~place:(place plan.path tag.span)
                     ~detail:
                       (Printf.sprintf
                          "the mark of %s names %s, and the step hash starts \
                           with %s"
                          (Facts.step_id plan step) target hash)
                     ~fix:(Fix.mark_hash tag hash)
                     ?mark:
                       (Finding.part tag Tag_line.Target "not the step hash")
                     ())
            | Some _ | None -> None)
          plan.steps)
    (Facts.plans facts)

let merged_incomplete facts =
  List.concat_map
    (fun (plan : Facts.plan) ->
      if not (is_open plan) then []
      else
        List.filter_map
          (fun (step : Facts.step) ->
            let standing = Facts.standing facts plan step in
            let met, unmet =
              List.partition
                (fun promise -> Option.is_some (standing promise).Facts.by)
                step.promises
            in
            match (met, unmet) with
            | _ :: _, _ :: _ ->
                Some
                  (Finding.make Finding_class.Merged_incomplete
                     (Finding.Fact
                        { id = Facts.step_id plan step; ack_name = step.slug })
                     ~place:(place plan.path step.span)
                     ~detail:
                       (Printf.sprintf "%s has %d of its %d promises met"
                          (Facts.step_id plan step) (List.length met)
                          (List.length step.promises))
                     ~related:
                       (List.map
                          (fun (promise : Facts.promise) ->
                            related "not met" plan.path promise.span)
                          unmet)
                     ())
            | [], _ | _, [] -> None)
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

let of_facts facts ~base ~not_text =
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
            misplaced_plans facts documents;
            duplicates facts;
            missing_plan_ids facts ~base;
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
            steps_without_promises facts;
            scope_overlaps facts;
            unverified_promises facts;
            promises_out_of_scope facts;
            stale_marks facts;
            merged_incomplete facts;
          ]))

let tree ?phases manifest documents ~base ~not_text =
  let facts =
    Allocation.measure phases "facts" (fun () -> Facts.make manifest documents)
  in
  Allocation.measure phases "findings" (fun () ->
      of_facts facts ~base ~not_text)
