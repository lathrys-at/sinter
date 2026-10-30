(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

open Sinter_core

let case name f = Alcotest.test_case name `Quick f

let elements =
  Style.[ Block; Warn; Headline; Frame; Help; Inserted; Removed; Note; Plain ]

let printed renderer element =
  let buffer = Buffer.create 32 in
  let ppf = Format.formatter_of_buffer buffer in
  Style.prepare ppf renderer;
  Style.string element ppf "x";
  Format.pp_print_flush ppf ();
  Buffer.contents buffer

let each_element_has_its_escape_codes () =
  Alcotest.(check (list string))
    "the text x in each style"
    [
      "\x1b[1m\x1b[91mx\x1b[0;1m\x1b[0m";
      "\x1b[1m\x1b[33mx\x1b[0;1m\x1b[0m";
      "\x1b[1mx\x1b[0m";
      "\x1b[1m\x1b[94mx\x1b[0;1m\x1b[0m";
      "\x1b[1m\x1b[36mx\x1b[0;1m\x1b[0m";
      "\x1b[32mx\x1b[0m";
      "\x1b[31mx\x1b[0m";
      "\x1b[1mx\x1b[0m";
      "x";
    ]
    (List.map (printed `Ansi_tty) elements)

let no_style_writes_an_escape_code_with_no_renderer () =
  Alcotest.(check (list string))
    "the text x in each style"
    (List.map (fun _ -> "x") elements)
    (List.map (printed `None) elements)

let a_tier_has_the_style_of_its_name () =
  Alcotest.(check bool)
    "block, warn, off, and no tier" true
    (List.map Style.of_tier
       [
         Some Finding_class.Block;
         Some Finding_class.Warn;
         Some Finding_class.Off;
         None;
       ]
    = Style.[ Block; Warn; Headline; Headline ])

let color_gives_the_ansi_renderer () =
  Alcotest.(check bool)
    "color and no color" true
    (List.map Style.renderer [ true; false ] = [ `Ansi_tty; `None ])

let variables =
  [ "NO_COLOR"; "CLICOLOR_FORCE"; "FORCE_COLOR"; "TERM"; "CLICOLOR" ]

let getenv bindings name = List.assoc_opt name bindings

let reference setting bindings ~terminal =
  let value name = List.assoc_opt name bindings in
  let set_and_not_empty name =
    match value name with Some text -> text <> "" | None -> false
  in
  if setting = Style.Always then true
  else if setting = Style.Never then false
  else if set_and_not_empty "NO_COLOR" then false
  else if
    (match value "CLICOLOR_FORCE" with
      | Some text -> text <> "0"
      | None -> false)
    || set_and_not_empty "FORCE_COLOR"
  then true
  else if value "TERM" = Some "dumb" || value "CLICOLOR" = Some "0" then false
  else terminal

let setting_name = function
  | Style.Auto -> "auto"
  | Style.Always -> "always"
  | Style.Never -> "never"

let values = [ None; Some ""; Some "0"; Some "1"; Some "dumb"; Some "xterm" ]

let rec combinations = function
  | [] -> [ [] ]
  | name :: rest ->
      List.concat_map
        (fun others ->
          List.map
            (function None -> others | Some value -> (name, value) :: others)
            values)
        (combinations rest)

let every_case =
  List.concat_map
    (fun setting ->
      List.concat_map
        (fun bindings ->
          List.map
            (fun terminal -> (setting, bindings, terminal))
            [ true; false ])
        (combinations variables))
    Style.[ Auto; Always; Never ]

let print_case (setting, bindings, terminal) =
  Printf.sprintf "--color=%s %s terminal=%b" (setting_name setting)
    (String.concat " "
       (List.map
          (fun (name, value) -> Printf.sprintf "%s=%S" name value)
          bindings))
    terminal

let the_choice_of_color_follows_the_order_of_the_settings () =
  Alcotest.(check int)
    "the number of cases"
    (3 * 7776 * 2)
    (List.length every_case);
  Alcotest.(check (list string))
    "the cases where the choice differs from the reference" []
    (List.filter_map
       (fun ((setting, bindings, terminal) as case) ->
         if
           Bool.equal
             (Style.color setting ~getenv:(getenv bindings) ~terminal)
             (reference setting bindings ~terminal)
         then None
         else Some (print_case case))
       every_case)

let decides setting bindings ~terminal =
  Style.color setting ~getenv:(getenv bindings) ~terminal

let rule_1_the_option_wins_over_every_variable () =
  Alcotest.(check (pair bool bool))
    "always with NO_COLOR, never with CLICOLOR_FORCE on a terminal" (true, false)
    ( decides Style.Always
        [ ("NO_COLOR", "1"); ("TERM", "dumb") ]
        ~terminal:false,
      decides Style.Never [ ("CLICOLOR_FORCE", "1") ] ~terminal:true )

let rule_2_no_color_wins_over_the_force_variables () =
  Alcotest.(check bool)
    "NO_COLOR with CLICOLOR_FORCE and FORCE_COLOR" false
    (decides Style.Auto
       [ ("NO_COLOR", "1"); ("CLICOLOR_FORCE", "1"); ("FORCE_COLOR", "1") ]
       ~terminal:true)

let rule_2_an_empty_no_color_counts_as_unset () =
  Alcotest.(check bool)
    "an empty NO_COLOR on a terminal" true
    (decides Style.Auto [ ("NO_COLOR", "") ] ~terminal:true)

let rule_3_a_force_variable_wins_over_term_and_the_stream () =
  Alcotest.(check (list bool))
    "CLICOLOR_FORCE=1, an empty CLICOLOR_FORCE, FORCE_COLOR=1, with TERM=dumb \
     off a terminal"
    [ true; true; true ]
    (List.map
       (fun force ->
         decides Style.Auto (force :: [ ("TERM", "dumb") ]) ~terminal:false)
       [ ("CLICOLOR_FORCE", "1"); ("CLICOLOR_FORCE", ""); ("FORCE_COLOR", "1") ])

let rule_3_a_force_of_0_or_empty_forces_nothing () =
  Alcotest.(check (list bool))
    "CLICOLOR_FORCE=0 and an empty FORCE_COLOR, off a terminal" [ false; false ]
    (List.map
       (fun force -> decides Style.Auto [ force ] ~terminal:false)
       [ ("CLICOLOR_FORCE", "0"); ("FORCE_COLOR", "") ])

let rule_4_a_dumb_term_or_clicolor_0_turns_color_off () =
  Alcotest.(check (list bool))
    "TERM=dumb and CLICOLOR=0 on a terminal" [ false; false ]
    (List.map
       (fun binding -> decides Style.Auto [ binding ] ~terminal:true)
       [ ("TERM", "dumb"); ("CLICOLOR", "0") ])

let rule_5_the_stream_decides_at_the_end () =
  Alcotest.(check (pair bool bool))
    "a terminal and a file, with TERM=xterm" (true, false)
    ( decides Style.Auto [ ("TERM", "xterm") ] ~terminal:true,
      decides Style.Auto [ ("TERM", "xterm") ] ~terminal:false )

let a_formatter_breaks_no_line () =
  Fixture.with_temporary_folder (fun folder ->
      let path = Filename.concat folder "out" in
      let long = String.make 300 'a' in
      Out_channel.with_open_bin path (fun channel ->
          let ppf = Style.formatter channel ~color:false in
          Fmt.pf ppf "@[%s@ %s@]@\n" long "b";
          Style.string Style.Block ppf "x";
          Format.pp_print_flush ppf ());
      Alcotest.(check string)
        "the lines" (long ^ " b\nx")
        (In_channel.with_open_bin path In_channel.input_all))

let tests =
  [
    case "each element has its escape codes" each_element_has_its_escape_codes;
    case "no style writes an escape code with no renderer"
      no_style_writes_an_escape_code_with_no_renderer;
    case "a tier has the style of its name" a_tier_has_the_style_of_its_name;
    case "color gives the ANSI renderer" color_gives_the_ansi_renderer;
    case "the choice of color follows the order of the settings in every case"
      the_choice_of_color_follows_the_order_of_the_settings;
    case "rule 1: the option wins over every variable"
      rule_1_the_option_wins_over_every_variable;
    case "rule 2: NO_COLOR wins over the force variables"
      rule_2_no_color_wins_over_the_force_variables;
    case "rule 2: an empty NO_COLOR counts as unset"
      rule_2_an_empty_no_color_counts_as_unset;
    case "rule 3: a force variable wins over TERM and the stream"
      rule_3_a_force_variable_wins_over_term_and_the_stream;
    case "rule 3: a force of 0 or empty forces nothing"
      rule_3_a_force_of_0_or_empty_forces_nothing;
    case "rule 4: a dumb TERM or CLICOLOR=0 turns color off"
      rule_4_a_dumb_term_or_clicolor_0_turns_color_off;
    case "rule 5: the stream decides at the end"
      rule_5_the_stream_decides_at_the_end;
    case "a formatter breaks no line" a_formatter_breaks_no_line;
  ]
