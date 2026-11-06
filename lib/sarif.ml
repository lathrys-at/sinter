(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

let schema =
  "https://raw.githubusercontent.com/oasis-tcs/sarif-spec/master/Schemata/sarif-schema-2.1.0.json"

let fingerprint = "sinterFindingId/v1"

let unreserved = function
  | 'A' .. 'Z' | 'a' .. 'z' | '0' .. '9' | '-' | '.' | '_' | '~' | '/' -> true
  | _ -> false

let uri path =
  let buffer =
    Buffer.create
      (String.length path
       [@mutaml.skip
         "Buffer.create takes any size and raises a size below 1 to 1; the \
          size is only the first room of a buffer that grows as it needs, and \
          no output reads it"])
  in
  String.iter
    (fun byte ->
      if unreserved byte then Buffer.add_char buffer byte
      else Buffer.add_string buffer (Printf.sprintf "%%%02X" (Char.code byte)))
    path;
  Buffer.contents buffer

let message_text text =
  let buffer =
    Buffer.create
      (String.length text
       [@mutaml.skip
         "Buffer.create takes any size and raises a size below 1 to 1; the \
          size is only the first room of a buffer that grows as it needs, and \
          no output reads it"])
  in
  String.iter
    (function
      | '{' -> Buffer.add_string buffer "{{"
      | '}' -> Buffer.add_string buffer "}}"
      | byte -> Buffer.add_char buffer byte)
    text;
  Buffer.contents buffer

let link_text text =
  let buffer =
    Buffer.create
      (String.length text
       [@mutaml.skip
         "Buffer.create takes any size and raises a size below 1 to 1; the \
          size is only the first room of a buffer that grows as it needs, and \
          no output reads it"])
  in
  String.iter
    (function
      | ('\\' | '[' | ']') as byte ->
          Buffer.add_char buffer '\\';
          Buffer.add_char buffer byte
      | byte -> Buffer.add_char buffer byte)
    text;
  message_text (Buffer.contents buffer)

let message text = Json.Object [ ("text", Json.String text) ]

let region ~line ~col ~eline ~ecol =
  Json.Object
    [
      ("startLine", Json.Int line);
      ("startColumn", Json.Int col);
      ("endLine", Json.Int eline);
      ("endColumn", Json.Int ecol);
    ]

let span_region (span : Markdown.span) =
  region ~line:span.start.line ~col:span.start.column ~eline:span.stop.line
    ~ecol:span.stop.column

let artifact path =
  Json.Object
    [ ("uri", Json.String (uri path)); ("uriBaseId", Json.String "%SRCROOT%") ]

let location (finding : Finding.t) =
  match finding.place with
  | None -> []
  | Some { path; span } ->
      let physical =
        match finding.mark with
        | None -> [ ("region", span_region span) ]
        | Some { start; stop; _ } ->
            ( "region",
              region ~line:span.start.line ~col:start ~eline:span.start.line
                ~ecol:stop )
            ::
            (if
               span.stop.line = span.start.line
               && start = span.start.column && stop = span.stop.column
             then []
             else [ ("contextRegion", span_region span) ])
      in
      [
        ( "locations",
          Json.Array
            [
              Json.Object
                (( "physicalLocation",
                   Json.Object (("artifactLocation", artifact path) :: physical)
                 )
                ::
                (match finding.mark with
                | None -> []
                | Some { label; _ } ->
                    [ ("message", message (message_text label)) ]));
            ] );
      ]

let related (finding : Finding.t) =
  match finding.related with
  | [] -> []
  | places ->
      [
        ( "relatedLocations",
          Json.Array
            (List.mapi
               (fun index ({ label; place } : Finding.related) ->
                 Json.Object
                   ([
                      ("id", Json.Int (index + 1));
                      ("message", message (message_text label));
                    ]
                   @
                   match place with
                   | None -> []
                   | Some { path; span } ->
                       [
                         ( "physicalLocation",
                           Json.Object
                             [
                               ("artifactLocation", artifact path);
                               ("region", span_region span);
                             ] );
                       ]))
               places) );
      ]

let result_message (finding : Finding.t) =
  let detail =
    message_text
      (Option.value finding.detail
         ~default:(Finding_class.name finding.finding_class))
  in
  let links =
    List.mapi
      (fun index ({ label; place } : Finding.related) ->
        match place with
        | Some _ -> Printf.sprintf "[%s](%d)" (link_text label) (index + 1)
        | None -> message_text label)
      finding.related
  in
  match links with
  | [] -> detail
  | links -> detail ^ " (" ^ String.concat "; " links ^ ")"

let fixes (finding : Finding.t) =
  match (finding.fix, finding.place) with
  | Some fix, Some { path; _ } ->
      let description = message (message_text (Fix.help fix)) in
      [
        ( "fixes",
          Json.Array
            (List.map
               (fun edits ->
                 Json.Object
                   [
                     ("description", description);
                     ( "artifactChanges",
                       Json.Array
                         [
                           Json.Object
                             [
                               ("artifactLocation", artifact path);
                               ( "replacements",
                                 Json.Array
                                   (List.map
                                      (fun ({ line; col; eline; ecol; text } :
                                             Fix.edit) ->
                                        Json.Object
                                          (( "deletedRegion",
                                             region ~line ~col ~eline ~ecol )
                                          ::
                                          (if String.equal text "" then []
                                           else
                                             [
                                               ( "insertedContent",
                                                 Json.Object
                                                   [
                                                     ("text", Json.String text);
                                                   ] );
                                             ])))
                                      edits) );
                             ];
                         ] );
                   ])
               (Fix.alternatives fix)) );
      ]
  | Some _, None | None, _ -> []

let level = function
  | Finding_class.Off -> "none"
  | Finding_class.Warn -> "warning"
  | Finding_class.Block -> "error"

let rule_indices =
  List.mapi
    (fun index finding_class -> (finding_class, index))
    Finding_class.all

let result ~gate ((finding : Finding.t), tier) =
  let name = Finding_class.name finding.finding_class in
  Json.Object
    ([
       ("ruleId", Json.String name);
       ("ruleIndex", Json.Int (List.assoc finding.finding_class rule_indices));
       ("level", Json.String (level tier));
       ("message", message (result_message finding));
       ( "partialFingerprints",
         Json.Object [ (fingerprint, Json.String (Finding.id finding)) ] );
       ( "properties",
         Json.Object
           [
             ("subject", Json.String (Finding.subject_id finding.subject));
             ("ack_subject", Json.String (Finding.ack_subject finding.subject));
             ("ackable", Json.Bool finding.ackable);
             ("tier", Json.String (Finding_class.tier_name tier));
             ("gate", Json.String (Finding_class.gate_name gate));
           ] );
     ]
    @ location finding @ related finding @ fixes finding)

let rule finding_class =
  let text = message (Finding_class.summary finding_class) in
  Json.Object
    [
      ("id", Json.String (Finding_class.name finding_class));
      ("shortDescription", text);
      ("fullDescription", text);
      ("help", text);
    ]

let to_string ~tool ~mode ~gate ~base entries =
  let log =
    Json.Object
      [
        ("$schema", Json.String schema);
        ("version", Json.String "2.1.0");
        ( "runs",
          Json.Array
            [
              Json.Object
                [
                  ( "tool",
                    Json.Object
                      [
                        ( "driver",
                          Json.Object
                            [
                              ("name", Json.String "sinter");
                              ("version", Json.String tool);
                              ( "rules",
                                Json.Array (List.map rule Finding_class.all) );
                            ] );
                      ] );
                  ("columnKind", Json.String "unicodeCodePoints");
                  ( "properties",
                    Json.Object
                      [
                        ("mode", Json.String (Mode.name mode));
                        ("gate", Json.String (Finding_class.gate_name gate));
                        ("base", Json.String base);
                      ] );
                  ("results", Json.Array (List.map (result ~gate) entries));
                ];
            ] );
      ]
  in
  match Json.to_string log with
  | Ok text -> text
  | Error _ ->
      invalid_arg
        "Sinter_core.Sarif: a string is not valid UTF-8, or a line or a column \
         is outside the range of JSON"
