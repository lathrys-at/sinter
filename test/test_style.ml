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

let each_stream_has_no_renderer () =
  Alcotest.(check bool)
    "standard output and standard error" true
    (List.map Style.renderer Style.[ Output; Errors ] = [ `None; `None ])

let a_formatter_breaks_no_line () =
  Fixture.with_temporary_folder (fun folder ->
      let path = Filename.concat folder "out" in
      let long = String.make 300 'a' in
      Out_channel.with_open_bin path (fun channel ->
          let ppf = Style.formatter channel Style.Output in
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
    case "each stream has no renderer" each_stream_has_no_renderer;
    case "a formatter breaks no line" a_formatter_breaks_no_line;
  ]
