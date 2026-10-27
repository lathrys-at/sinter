(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

type tag = {
  column : int;
  word : string;
  target : string option;
  rev : int option;
  desc : string;
}

let of_markdown (tag : Markdown.tag) =
  {
    column = tag.span.start.column;
    word = tag.word;
    target = tag.target;
    rev = tag.rev;
    desc = tag.desc;
  }

let tags (document : Markdown.t) ~first ~count =
  let all = document.tags in
  let rec search low high =
    if low < high then
      let middle = (low + high) / 2 in
      if all.(middle).span.start.line < first then search (middle + 1) high
      else search low middle
    else low
  in
  let start = search 0 (Array.length all) in
  let rec collect index line found =
    if line >= first + count then Some (List.rev found)
    else if index < Array.length all && all.(index).span.start.line = line then
      collect (index + 1) (line + 1) (of_markdown all.(index) :: found)
    else None
  in
  collect start first []

type fixes = {
  revision : string -> int option;
  spelling : string -> string option;
  renamed : string -> (string * int) option;
  successors : string -> (string * int) list;
  word : string -> string option;
}

let fixes ?same ~base facts =
  let resolve = lazy (Facts.resolve facts)
  and declarations = lazy (Array.of_list (Facts.declarations facts))
  and renamed = Adjudicator.renamed_to ?same ~base facts in
  let declared target =
    match Lazy.force resolve target with
    | Facts.Declaration index -> Some index
    | Facts.External _ | Facts.Unresolved _ -> None
  in
  let written index =
    let declaration = (Lazy.force declarations).(index) in
    (declaration.Facts.slug, declaration.rev)
  in
  {
    revision =
      (fun target -> Option.map (fun i -> snd (written i)) (declared target));
    spelling = Findings.declared_spelling facts;
    renamed =
      (fun target ->
        Option.map
          (fun (declaration : Facts.declaration) ->
            (declaration.slug, declaration.rev))
          (renamed target));
    successors =
      (fun target ->
        match declared target with
        | Some index -> List.map written (Facts.successors facts index)
        | None -> []);
    word = Findings.nearest_word;
  }

let citation_words =
  [ "satisfies"; "verifies"; "refines"; "cites"; "supersedes" ]

let pinned_words = [ "satisfies"; "verifies"; "refines"; "supersedes" ]
let declaration_words = [ "req"; "design"; "decision" ]

let edit fixes (o : tag) (n : tag) =
  let same_word = String.equal o.word n.word in
  match (o.target, n.target) with
  | Some a, Some b when same_word && List.mem o.word citation_words ->
      if String.equal a b then
        match (o.rev, n.rev) with
        | Some old, Some rev -> old <> rev && fixes.revision a = Some rev
        | None, Some rev ->
            List.mem o.word pinned_words && fixes.revision a = Some rev
        | _, None -> false
      else
        let names (slug, rev) =
          String.equal b slug && n.rev = Option.map (fun _ -> rev) o.rev
        in
        (o.rev = n.rev && fixes.spelling a = Some b)
        || Option.fold ~none:false ~some:names (fixes.renamed a)
        || String.equal o.word "cites"
           && List.exists names (fixes.successors a)
  | Some a, Some b when same_word && List.mem o.word declaration_words ->
      String.equal a b
      && Option.value n.rev ~default:1 > Option.value o.rev ~default:1
  | _ ->
      (not same_word) && o.target = n.target && o.rev = n.rev
      && fixes.word o.word = Some n.word

let is_ack (tag : tag) = String.equal tag.word "ack"

let is_repair fixes ~removed ~added =
  let old = List.filter (fun tag -> not (is_ack tag)) removed
  and fresh = List.filter (fun tag -> not (is_ack tag)) added in
  (removed <> [] || added <> [])
  && List.compare_lengths old fresh = 0
  && List.for_all2
       (fun (o : tag) (n : tag) ->
         o.column = n.column && String.equal o.desc n.desc && edit fixes o n)
       old fresh

let hunk fixes ~base document (h : Git.hunk) =
  let lines document first count =
    match document with
    | Some document -> tags document ~first ~count
    | None -> if count = 0 then Some [] else None
  in
  match (lines base h.old_line h.removed, lines document h.line h.added) with
  | Some removed, Some added -> is_repair fixes ~removed ~added
  | None, _ | _, None -> false
