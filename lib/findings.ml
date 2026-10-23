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

(* {1 The global rules} *)

let historical manifest (finding : Finding.t) =
  match finding.place with
  | Some { path; _ } -> Manifest.is_historical manifest path
  | None -> false

let tree manifest documents ~not_text =
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
          ]))
