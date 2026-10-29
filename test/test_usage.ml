(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

open Sinter_core

let case name f = Alcotest.test_case name `Quick f
let text { Error_text.fault; help; place } = (fault, help, Option.is_none place)
let error_text = Alcotest.(triple string string bool)

let a_usage_and_a_message_give_the_fault_and_the_help () =
  Alcotest.check error_text "the message and the usage"
    ( "unknown option '--foo'",
      "usage: sinter check [--help] [OPTION]\xe2\x80\xa6",
      true )
    (text
       (Usage.error
          "Usage: sinter check [--help] [OPTION]\xe2\x80\xa6\n\
           sinter: unknown option '--foo'\n"))

let a_bold_part_of_the_message_gets_quotes () =
  Alcotest.check error_text "the styles of cmdliner undone"
    ( "option '-o': invalid value 'x', expected one of 'full', 'brief' or 'json'",
      "usage: sinter check [--help] [OPTION]\xe2\x80\xa6",
      true )
    (text
       (Usage.error
          "Usage: \027[01msinter check\027[m [\027[01m--help\027[m] \
           [\027[04mOPTION\027[m]\xe2\x80\xa6\n\
           sinter: option \027[01m-o\027[m: \027[31minvalid\027[m value \
           \027[01mx\027[m, expected one of \027[01mfull\027[m, \
           \027[01mbrief\027[m or \027[01mjson\027[m\n"))

let every_other_escape_code_is_left_out () =
  Alcotest.check error_text
    "underline, red, a reset with no bold, a code of two bytes, and a code cut \
     at the end"
    ("required argument FILE is missing x", "usage: a", true)
    (text
       (Usage.error
          "Usage: a\n\
           sinter: required argument \027[04mFILE\027[m is \
           \027[31mmissing\027[m\027[m \027cx\027["))

let a_text_of_another_shape_is_one_line_with_no_help () =
  List.iter
    (fun (name, input, expected) ->
      Alcotest.check error_text name expected (text (Usage.error input)))
    [
      ( "a message with no usage line",
        "sinter: give either --query or --tree\n",
        ("sinter: give either --query or --tree", "", true) );
      ( "three lines, with escape codes and indents",
        "sinter: internal error, uncaught exception:\n\
        \        \027[01mNot_found\027[m\n\n\
         Raised at x\n",
        ( "sinter: internal error, uncaught exception: Not_found Raised at x",
          "",
          true ) );
      ( "a usage line and a line with no name",
        "Usage: a\nno name here\n",
        ("Usage: a no name here", "", true) );
      ( "a name with a space",
        "Usage: a\nsome tool: message\n",
        ("Usage: a some tool: message", "", true) );
      ( "an empty name",
        "Usage: a\n: message\n",
        ("Usage: a : message", "", true) );
      ( "a usage line that does not start the text",
        "sinter: message\nUsage: a\n",
        ("sinter: message Usage: a", "", true) );
      ("no text", "", ("", "", true));
    ]

let the_message_of_a_two_line_text_stays_as_it_is =
  QCheck_alcotest.to_alcotest ~speed_level:`Quick
    (QCheck2.Test.make ~count:500
       ~name:"the message of a usage error with no escape code stays as it is"
       ~print:QCheck2.Print.(pair string string)
       QCheck2.Gen.(
         pair
           (string_size ~gen:printable (int_bound 20))
           (string_size ~gen:printable (int_bound 40)))
       (fun (usage, message) ->
         let usage = String.map (fun c -> if c = '\n' then ' ' else c) usage
         and message =
           String.map (fun c -> if c = '\n' then ' ' else c) message
         in
         let error =
           Usage.error ("Usage: " ^ usage ^ "\nsinter: " ^ message ^ "\n")
         in
         error.fault = message && error.help = "usage: " ^ usage))

let no_escape_code_is_left_in_the_error =
  QCheck_alcotest.to_alcotest ~speed_level:`Quick
    (QCheck2.Test.make ~count:1000
       ~name:"no escape code is left in the error of any text"
       ~print:QCheck2.Print.string
       QCheck2.Gen.(
         map (String.concat "")
           (list_size (int_bound 30)
              (oneof
                 [
                   oneof_list
                     [
                       "\027[01m";
                       "\027[m";
                       "\027[04m";
                       "\027[31m";
                       "\027";
                       "\027[";
                       "\027c";
                       "Usage: ";
                       "sinter: ";
                       "\n";
                       " ";
                       ":";
                     ];
                   Generators.terminal_text;
                 ])))
       (fun input ->
         let { Error_text.fault; help; place } = Usage.error input in
         place = None
         && (not (String.contains fault '\027'))
         && not (String.contains help '\027')))

let tests =
  [
    case "a usage and a message give the fault and the help"
      a_usage_and_a_message_give_the_fault_and_the_help;
    case "a bold part of the message gets quotes"
      a_bold_part_of_the_message_gets_quotes;
    case "every other escape code is left out"
      every_other_escape_code_is_left_out;
    case "a text of another shape is one line with no help"
      a_text_of_another_shape_is_one_line_with_no_help;
    the_message_of_a_two_line_text_stays_as_it_is;
    no_escape_code_is_left_in_the_error;
  ]
