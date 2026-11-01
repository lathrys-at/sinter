(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(* @cites sarif-output *)

(** The findings of a check at a gate as one SARIF 2.1.0 log, for GitHub code
    scanning and other readers of SARIF. *)

val to_string :
  tool:string ->
  mode:Mode.t ->
  gate:Finding_class.gate ->
  base:string ->
  (Finding.t * Finding_class.tier) list ->
  string
(** [to_string ~tool ~mode ~gate ~base findings] is the SARIF log of [findings]
    of a check of [mode] at [gate], each with its tier at [gate], on one line in
    the canonical form of {!Json.to_string}, with no line feed after it.

    The log holds [$schema], the URI of the SARIF 2.1.0 schema; [version],
    ["2.1.0"]; and [runs], one run. The run holds:

    - [tool.driver]: [name] ["sinter"], [version] [tool], and [rules]: one rule
      for each class of {!Finding_class.all}, in that order. A rule holds [id],
      the {!Finding_class.name} of the class, and [shortDescription],
      [fullDescription], and [help], each an object whose [text] is
      {!Finding_class.summary} of the class.
    - [columnKind] ["unicodeCodePoints"]: the columns are those of
      {!Markdown.position}, which count code points from 1.
    - [properties]: [mode], the {!Mode.name} of [mode]; [gate], the
      {!Finding_class.gate_name} of [gate]; and [base], [base].
    - [results]: one result for each finding of [findings], in that order.

    A result holds:

    - [ruleId], the name of the class of the finding, and [ruleIndex], the
      position of the class in {!Finding_class.all}, from 0;
    - [level]: [warning] for the tier [Warn], [error] for [Block], and [none]
      for [Off];
    - [message.text]: the detail of the finding, or the name of its class when
      it has no detail. When the finding has related places, a space and the
      related places in parentheses follow, separated by ["; "]. A related place
      in a file is a link [[label](n)], where [n] is its id, and in the label of
      a link a backslash, [\[], and [\]] get a backslash before them. A place in
      no file is its label alone, as plain text;
    - [partialFingerprints]: the key ["sinterFindingId/v1"], with {!Finding.id}
      of the finding;
    - [properties]: [subject], the {!Finding.subject_id}; [ack_subject], the
      {!Finding.ack_subject}; [ackable]; [tier], the {!Finding_class.tier_name}
      of the tier; and [gate];
    - [locations], when the finding has a place: one location. Its
      [physicalLocation] holds the [artifactLocation] of the path of the place
      and a [region]. With a mark, the region is the mark, on the first line of
      the place; the [contextRegion] is the place, except when the mark covers
      the whole place, and the location holds a [message] whose [text] is the
      label of the mark. Without a mark, the region is the place. So the region
      can differ from [line], [col], [eline], and [ecol] of the finding record
      of {!Check.record}. A finding with no place gives a result with no
      [locations]; GitHub code scanning does not show such a result;
    - [relatedLocations], when the finding has related places: one location for
      each, in the order of {!Finding.t.related}, with [id] from 1 and a
      [message] whose [text] is the label. A place in a file also holds a
      [physicalLocation] with its [artifactLocation] and its [region];
    - [fixes], when the finding has a fix: one fix for each alternative of
      {!Fix.alternatives}, in their order. A fix holds a [description] whose
      [text] is {!Fix.help}, and one [artifactChanges] item: the
      [artifactLocation] of the path of the place, and one [replacements] item
      for each edit, in order. A replacement holds a [deletedRegion], the span
      of the edit, and an [insertedContent] whose [text] is the text of the
      edit, which it lacks for an empty text. An insert is a region whose start
      equals its end.

    An [artifactLocation] holds [uri], the path with each byte other than an
    ASCII letter, a digit, [-], [.], [_], [~], and [/] written as [%] and two
    uppercase hexadecimal digits, and [uriBaseId] ["%SRCROOT%"]. A region holds
    [startLine], [startColumn], [endLine], and [endColumn], with the end column
    one past the last character. In the text of every message, each [{] and each
    [}] is written twice.

    @raise Invalid_argument
      if a string of the log is not valid UTF-8, or a line or a column is
      outside the range from [-(2^53-1)] to [2^53-1]. *)
