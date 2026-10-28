(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

open Sinter_bench

let result_of_int = Alcotest.(result int string)
let case name f = Alcotest.test_case name `Quick f

let gnu_time_reads_the_last_line () =
  Alcotest.check result_of_int "plain" (Ok 81234)
    (Measurement.gnu_time "81234\n");
  Alcotest.check result_of_int "after an exit status" (Ok 512)
    (Measurement.gnu_time "Command exited with non-zero status 1\n512\n\n")

let gnu_time_refuses_text_that_is_not_a_number () =
  List.iter
    (fun text ->
      match Measurement.gnu_time text with
      | Ok value -> Alcotest.failf "%S gave %d" text value
      | Error _ -> ())
    [ ""; "\n\n"; "12a\n"; "Command terminated by signal 9\n"; "-4\n" ]

let bsd_output =
  "        0.42 real         0.30 user         0.05 sys\n\
  \            26476544  maximum resident set size\n\
  \                   0  average shared memory size\n\
  \          2977772827  instructions retired\n\
  \          1063926080  cycles elapsed\n\
  \            20340736  peak memory footprint\n"

let sample =
  Alcotest.testable
    (fun format (sample : Measurement.sample) ->
      Format.fprintf format "{ peak %d; instructions %s; footprint %s }"
        sample.peak_kib
        (Option.fold ~none:"-" ~some:string_of_int sample.instructions)
        (Option.fold ~none:"-" ~some:string_of_int sample.footprint_kib))
    ( = )

let bsd_time_reads_bytes_as_kib () =
  Alcotest.(check (result sample string))
    "the sample"
    (Ok
       {
         Measurement.peak_kib = 25856;
         instructions = Some 2977772827;
         footprint_kib = Some 19864;
       })
    (Measurement.bsd_time bsd_output)

let bsd_time_without_counts_gives_none () =
  Alcotest.(check (result sample string))
    "the sample"
    (Ok { Measurement.peak_kib = 1; instructions = None; footprint_kib = None })
    (Measurement.bsd_time "  2047  maximum resident set size\n")

let bsd_time_needs_the_resident_set_size () =
  match Measurement.bsd_time "  2977772827  instructions retired\n" with
  | Ok _ -> Alcotest.fail "no error"
  | Error _ -> ()

let perf_output =
  "# started on Mon Oct 26 21:00:00 2026\n\n\
   2977772827,,instructions:u,1000000,100.00,,\n"

let count = Alcotest.(result (option int) string)

let perf_stat_reads_the_count () =
  Alcotest.check count "the count" (Ok (Some 2977772827))
    (Measurement.perf_stat perf_output)

let perf_stat_adds_the_counts_of_two_kinds_of_core () =
  Alcotest.check count "the sum" (Ok (Some 30))
    (Measurement.perf_stat
       "10,,cpu_atom/instructions:u/,1,100.00,,\n\
        20,,cpu_core/instructions:u/,1,100.00,,\n\
        <not counted>,,cpu_other/instructions:u/,0,0.00,,\n")

let perf_stat_without_a_count_gives_none () =
  List.iter
    (fun marker ->
      Alcotest.check count marker (Ok None)
        (Measurement.perf_stat (marker ^ ",,instructions:u,0,100.00,,\n")))
    [ "<not counted>"; "<not supported>" ]

let perf_stat_refuses_text_without_instructions () =
  List.iter
    (fun text ->
      match Measurement.perf_stat text with
      | Ok _ -> Alcotest.failf "%S gave a count" text
      | Error _ -> ())
    [
      "";
      "# started on Mon\n";
      "12,,cycles:u,1,100.00,,\n";
      "twelve,,instructions:u,1,100.00,,\n";
      "# 12,,instructions:u,1,100.00,,\n";
    ]

let decoders_never_raise =
  QCheck_alcotest.to_alcotest ~speed_level:`Quick
    (QCheck2.Test.make ~count:500
       ~name:
         "the decoders of time and perf give a value or an error for any text"
       ~print:QCheck2.Print.string
       QCheck2.Gen.(
         oneof
           [
             string_printable;
             map (String.concat "\n")
               (list_size (int_bound 6)
                  (oneof_list
                     [
                       "";
                       "12";
                       "  2047  maximum resident set size";
                       "9 instructions retired";
                       "4096 peak memory footprint";
                       "7,,instructions:u,1,,";
                       "<not counted>,,instructions:u";
                       ",,instructions";
                       "# x";
                       "99999999999999999999999";
                     ]));
           ])
       (fun text ->
         ignore (Measurement.gnu_time text);
         ignore (Measurement.bsd_time text);
         ignore (Measurement.perf_stat text);
         true))

let summary_of_values () =
  let summary = Measurement.summary [ 4.; 1.; 3.; 2. ] in
  Alcotest.(check (float 1e-9)) "median" 2.5 summary.median;
  Alcotest.(check (float 1e-9)) "min" 1. summary.min;
  Alcotest.(check (float 1e-9)) "max" 4. summary.max;
  Alcotest.(check (float 1e-9)) "spread" 120. summary.spread;
  let odd = Measurement.summary [ 5.; 9.; 7. ] in
  Alcotest.(check (float 1e-9)) "median of an odd count" 7. odd.median;
  Alcotest.(check (float 1e-9))
    "spread of a zero median" 0. (Measurement.summary [ 0.; 0.; 0. ]).spread

let summary_refuses_no_value () =
  match Measurement.summary [] with
  | _ -> Alcotest.fail "no exception"
  | exception Invalid_argument _ -> ()

let summary_orders_its_values =
  QCheck_alcotest.to_alcotest ~speed_level:`Quick
    (QCheck2.Test.make ~count:500
       ~name:"min, median, and max of a summary are in order and are bounds"
       ~print:QCheck2.Print.(list float)
       QCheck2.Gen.(list_size (int_range 1 9) (float_bound_inclusive 1e12))
       (fun values ->
         let summary = Measurement.summary values in
         summary.min <= summary.median
         && summary.median <= summary.max
         && List.for_all
              (fun value -> summary.min <= value && value <= summary.max)
              values
         && List.mem summary.min values
         && List.mem summary.max values
         && summary.spread >= 0.))

let budgets_text =
  "[scan]\nallocation-growth = 10.5\n\n[check]\nallocation-growth = 11\n"

let budgets text =
  match Budgets.of_string text with
  | Ok budgets -> budgets
  | Error message -> Alcotest.failf "the budgets do not read: %s" message

let budgets_give_each_limit () =
  let budgets = budgets budgets_text in
  let limit = Alcotest.(option (float 0.)) in
  Alcotest.check limit "scan" (Some 10.5) (Budgets.growth budgets "scan");
  Alcotest.check limit "check" (Some 11.) (Budgets.growth budgets "check");
  Alcotest.check limit "no table check-diff" None
    (Budgets.growth budgets "check-diff");
  Alcotest.check limit "another command" None (Budgets.growth budgets "serve")

let budgets_of_check_diff_are_optional () =
  Alcotest.(check (option (float 0.)))
    "the limit" (Some 12.)
    (Budgets.growth
       (budgets (budgets_text ^ "\n[check-diff]\nallocation-growth = 12\n"))
       "check-diff")

let budgets_refuse_a_memory_budget () =
  List.iter
    (fun (text, expected) ->
      Alcotest.(check (result reject string))
        text (Error expected)
        (Result.map (fun _ -> ()) (Budgets.of_string text)))
    [
      ( "[scan]\nallocation-growth = 1\npeak-memory-kib = 90000\n",
        "[scan]: unknown key peak-memory-kib" );
      ( "[scan]\nallocation-growth = 1\n[check]\npeak-memory-kib = 80000\n",
        "[check]: unknown key peak-memory-kib" );
      ( budgets_text ^ "[check-diff]\npeak-memory-kib = 1\n",
        "[check-diff]: unknown key peak-memory-kib" );
    ]

let budgets_refuse_a_bad_file () =
  List.iter
    (fun (text, expected) ->
      Alcotest.(check (result reject string))
        text (Error expected)
        (Result.map (fun _ -> ()) (Budgets.of_string text)))
    [
      ( "[scan\n",
        "line 1, column 6: the table header is not valid; expected ']'" );
      ("[check]\nallocation-growth = 1\n", "the table [scan] is missing");
      ("[scan]\nallocation-growth = 1\n", "the table [check] is missing");
      ("scan = 1\n", "[scan] is an integer, not a table");
      (budgets_text ^ "[serve]\n", "the budgets: unknown key serve");
      ("[scan]\nallocation-growth = 1\nwall = 1\n", "[scan]: unknown key wall");
      ("[scan]\n", "scan.allocation-growth is missing");
      ( "[scan]\nallocation-growth = -2.0\n",
        "scan.allocation-growth is not a positive number" );
      ( "[scan]\nallocation-growth = 0\n",
        "scan.allocation-growth is not a positive number" );
      ( "[scan]\nallocation-growth = 0.0\n",
        "scan.allocation-growth is not a positive number" );
      ( "[scan]\nallocation-growth = inf\n",
        "scan.allocation-growth is not a positive number" );
      ( "[scan]\nallocation-growth = nan\n",
        "scan.allocation-growth is not a positive number" );
      ( "[scan]\nallocation-growth = \"2\"\n",
        "scan.allocation-growth is not a positive number" );
      ( budgets_text ^ "[check-diff]\n",
        "check-diff.allocation-growth is missing" );
      ( "check-diff = 1\n" ^ budgets_text,
        "[check-diff] is an integer, not a table" );
    ]

let verdict (verdict : Budgets.verdict) =
  match verdict with
  | Pass value -> Printf.sprintf "pass %g" value
  | Fail value -> Printf.sprintf "fail %g" value
  | Skipped reason -> "skipped: " ^ reason

let words_of words ~tree ~command =
  Option.value (List.assoc_opt (tree, command) words) ~default:[]

let outcomes budgets ~words =
  List.map
    (fun (outcome : Budgets.outcome) ->
      Printf.sprintf "%s%s %g %s" outcome.command
        (Option.fold ~none:"" ~some:(fun phase -> " " ^ phase) outcome.phase)
        outcome.limit (verdict outcome.verdict))
    (Budgets.check budgets ~words:(words_of words))

let check_judges_each_phase () =
  Alcotest.(check (list string))
    "outcomes"
    [
      "scan read 10.5 pass 10";
      "scan records 10.5 pass 10.5";
      "check findings 11 fail 11.5";
      "check parse 11 pass 11";
    ]
    (outcomes (budgets budgets_text)
       ~words:
         [
           (("n1000", "scan"), [ ("records", 2.); ("read", 3.) ]);
           (("n10000", "scan"), [ ("read", 30.); ("records", 21.) ]);
           (("n1000", "check"), [ ("findings", 2.); ("parse", 1.) ]);
           (("n10000", "check"), [ ("findings", 23.); ("parse", 11.) ]);
         ])

let check_judges_the_budgets_of_check_diff () =
  Alcotest.(check (list string))
    "outcomes of check-diff"
    [ "check-diff facts 12 pass 11"; "check-diff base-facts 12 fail 13" ]
    (List.filter
       (fun line -> String.starts_with ~prefix:"check-diff" line)
       (outcomes
          (budgets (budgets_text ^ "[check-diff]\nallocation-growth = 12\n"))
          ~words:
            [
              (("n1000", "check-diff"), [ ("facts", 1.); ("base-facts", 1.) ]);
              (("n10000", "check-diff"), [ ("facts", 11.); ("base-facts", 13.) ]);
            ]))

let check_skips_what_the_run_did_not_measure () =
  Alcotest.(check (list string))
    "outcomes"
    [
      "scan read 10.5 skipped: the tree n1000 counts no word in the phase";
      "scan parse 10.5 skipped: the tree n1000 counts no word in the phase";
      "scan facts 10.5 pass 2";
      "check 11 skipped: the run counted no phase on the tree n1000 or on the \
       tree n10000";
    ]
    (outcomes (budgets budgets_text)
       ~words:
         [
           (("n1000", "scan"), [ ("read", 0.); ("facts", 4.) ]);
           (("n10000", "scan"), [ ("read", 5.); ("parse", 6.); ("facts", 8.) ]);
           (("n1000", "check"), [ ("read", 1.) ]);
         ])

module Gen = QCheck2.Gen

let check_passes_a_phase_at_or_under_its_limit =
  let phases =
    Gen.map
      (List.sort_uniq (fun (a, _, _) (b, _, _) -> String.compare a b))
      (Gen.list_size (Gen.int_bound 6)
         (Gen.triple
            (Gen.oneof_list [ "read"; "parse"; "facts"; "records"; "output" ])
            (Gen.oneof_weighted
               [
                 (1, Gen.return None);
                 (1, Gen.return (Some 0.));
                 (4, Gen.map Option.some (Gen.float_bound_inclusive 1e6));
               ])
            (Gen.float_bound_inclusive 1e8)))
  in
  QCheck_alcotest.to_alcotest ~speed_level:`Quick
    (QCheck2.Test.make ~count:500
       ~name:
         "check gives each phase of n10000 one outcome, which passes when the \
          growth is at or under the limit"
       (Gen.pair (Gen.float_range 0.5 50.) phases)
       (fun (limit, phases) ->
         let budgets =
           budgets
             (Printf.sprintf
                "[scan]\n\
                 allocation-growth = %.17g\n\
                 [check]\n\
                 allocation-growth = 1\n"
                limit)
         in
         let limit = Option.value (Budgets.growth budgets "scan") ~default:0. in
         let words =
           [
             ( ("n1000", "scan"),
               List.filter_map
                 (fun (phase, small, _) ->
                   Option.map (fun small -> (phase, small)) small)
                 phases );
             ( ("n10000", "scan"),
               List.map (fun (phase, _, large) -> (phase, large)) phases );
           ]
         in
         let scan =
           List.filter
             (fun (outcome : Budgets.outcome) ->
               String.equal outcome.command "scan")
             (Budgets.check budgets ~words:(words_of words))
         in
         match phases with
         | [] -> (
             match scan with
             | [ { phase = None; verdict = Skipped _; _ } ] -> true
             | _ -> false)
         | _ ->
             List.length scan = List.length phases
             && List.for_all2
                  (fun (phase, small, large) (outcome : Budgets.outcome) ->
                    outcome.phase = Some phase && outcome.limit = limit
                    &&
                    match (small, outcome.verdict) with
                    | Some small, Pass growth ->
                        small > 0. && growth = large /. small && growth <= limit
                    | Some small, Fail growth ->
                        small > 0. && growth = large /. small && growth > limit
                    | Some small, Skipped _ -> small = 0.
                    | None, Skipped _ -> true
                    | None, (Pass _ | Fail _) -> false)
                  phases scan))

let phase_words_reads_a_line_per_phase () =
  Alcotest.(check (result (list (pair string int)) string))
    "the phases"
    (Ok [ ("repository", 455939); ("read", 53509) ])
    (Measurement.phase_words "repository 455939\nread 53509\n");
  Alcotest.(check (result (list (pair string int)) string))
    "no phase" (Ok [])
    (Measurement.phase_words "")

let phase_words_refuses_a_bad_file () =
  List.iter
    (fun (text, expected) ->
      Alcotest.(check (result reject string))
        text (Error expected)
        (Result.map (fun _ -> ()) (Measurement.phase_words text)))
    [
      ("read 1", "the counts of the phases do not end with a line feed");
      ("read 1\nread 2\n", "the phase read occurs twice");
      ("read\n", "not a count of a phase: read");
      (" 1\n", "not a count of a phase:  1");
      ("read 1 2\n", "not a count of a phase: read 1 2");
      ("read -1\n", "not a count of a phase: read -1");
      ("read 1\n\n", "not a count of a phase: ");
    ]

let summary_gen =
  Gen.map
    (fun (median, min, max, spread) -> { Measurement.median; min; max; spread })
    (Gen.quad
       (Gen.float_bound_inclusive 1e12)
       (Gen.float_bound_inclusive 1e12)
       (Gen.float_bound_inclusive 1e12)
       (Gen.float_bound_inclusive 100.))

let row_gen =
  Gen.map
    (fun ( (tree, declarations, command, exit_code),
           (peak, instructions, footprint, phase_words) ) ->
      {
        Report.tree;
        declarations;
        command;
        exit_code;
        peak_kib = peak;
        instructions;
        footprint_kib = footprint;
        phase_words;
      })
    (Gen.pair
       (Gen.quad
          (Gen.oneof_list [ "self"; "n1000"; "n10000"; "n\"é" ])
          (Gen.option (Gen.int_bound 100000))
          (Gen.oneof_list [ "scan"; "check" ])
          (Gen.int_bound 3))
       (Gen.quad summary_gen (Gen.option summary_gen) (Gen.option summary_gen)
          (Gen.list_size (Gen.int_bound 4)
             (Gen.pair
                (Gen.oneof_list [ "read"; "parse"; "facts"; "p\"é" ])
                (Gen.float_bound_inclusive 1e12)))))

let report_gen =
  Gen.map
    (fun ((platform, counter, reason), (runs, seed, rows)) ->
      {
        Report.platform;
        instruction_counter = counter;
        no_count_reason = reason;
        runs;
        seed;
        rows;
      })
    (Gen.pair
       (Gen.triple
          (Gen.oneof_list [ "linux"; "macos" ])
          (Gen.option (Gen.oneof_list [ "perf"; "time" ]))
          (Gen.option Gen.string_printable))
       (Gen.triple (Gen.int_bound 9) Gen.int
          (Gen.list_size (Gen.int_bound 6) row_gen)))

let report_round_trips =
  QCheck_alcotest.to_alcotest ~speed_level:`Quick
    (QCheck2.Test.make ~count:300
       ~name:"a report reads back from the JSON that it writes" report_gen
       (fun report ->
         Report.of_string (Yojson.Basic.to_string (Report.to_json report []))
         = Ok report))

let report_reader_never_raises =
  QCheck_alcotest.to_alcotest ~speed_level:`Quick
    (QCheck2.Test.make ~count:300
       ~name:"the reader of a report gives a report or an error for any text"
       ~print:QCheck2.Print.string
       (Gen.oneof
          [
            Gen.string_printable;
            Gen.map2
              (fun report cut ->
                let text = Yojson.Basic.to_string (Report.to_json report []) in
                String.sub text 0 (cut mod (String.length text + 1)))
              report_gen Gen.nat;
            Gen.map2
              (fun report (at, byte) ->
                let text =
                  Bytes.of_string
                    (Yojson.Basic.to_string (Report.to_json report []))
                in
                Bytes.set text (at mod Bytes.length text) byte;
                Bytes.to_string text)
              report_gen
              (Gen.pair Gen.nat Gen.char);
          ])
       (fun text -> match Report.of_string text with Ok _ | Error _ -> true))

let a_report_names_the_key_it_lacks () =
  List.iter
    (fun (text, expected) ->
      Alcotest.(check (result reject string))
        text (Error expected)
        (Result.map (fun _ -> ()) (Report.of_string text)))
    [
      ("[]", "the key platform is not in an object");
      ("{}", "the key platform is missing");
      ( {|{"platform":1,"instruction_counter":null,"no_count_reason":null,"runs":1,"seed":1,"results":[]}|},
        "platform is not a string" );
      ( {|{"platform":"linux","instruction_counter":null,"no_count_reason":null,"runs":1.5,"seed":1,"results":[]}|},
        "runs is not an integer" );
      ( {|{"platform":"linux","instruction_counter":null,"no_count_reason":null,"runs":1,"seed":1,"results":{}}|},
        "results is not an array" );
      ( {|{"platform":"linux","instruction_counter":null,"no_count_reason":null,"runs":1,"seed":1,"results":[{"tree":"self","declarations":null,"command":"scan","exit":0,"peak_kib":3,"instructions":null,"footprint_kib":null}]}|},
        "peak_kib is not an object" );
      ( {|{"platform":"linux","instruction_counter":null,"no_count_reason":null,"runs":1,"seed":1,"results":[{"tree":"self","declarations":null,"command":"scan","exit":0,"peak_kib":{"median":"a","min":1,"max":1,"spread_percent":0},"instructions":null,"footprint_kib":null}]}|},
        "median is not a number" );
      ( {|{"platform":"linux","instruction_counter":null,"no_count_reason":null,"runs":1,"seed":1,"results":[{"tree":"self","declarations":null,"command":"scan","exit":0,"peak_kib":{"median":1,"min":1,"max":1,"spread_percent":0},"instructions":null,"footprint_kib":null}]}|},
        "the key phase_words is missing" );
      ( {|{"platform":"linux","instruction_counter":null,"no_count_reason":null,"runs":1,"seed":1,"results":[{"tree":"self","declarations":null,"command":"scan","exit":0,"peak_kib":{"median":1,"min":1,"max":1,"spread_percent":0},"instructions":null,"footprint_kib":null,"phase_words":[{"phase":"read","words":"x"}]}]}|},
        "words is not a number" );
    ]

let a_report_reads_the_first_row_of_a_tree_and_command () =
  let summary median =
    { Measurement.median; min = 0.; max = 0.; spread = 0. }
  in
  let row tree command peak instructions phase_words =
    {
      Report.tree;
      declarations = None;
      command;
      exit_code = 0;
      peak_kib = summary peak;
      instructions = Option.map summary instructions;
      footprint_kib = None;
      phase_words;
    }
  in
  let report =
    {
      Report.platform = "linux";
      instruction_counter = None;
      no_count_reason = None;
      runs = 1;
      seed = 1;
      rows =
        [
          row "n1000" "scan" 1. (Some 2.) [ ("read", 7.) ];
          row "n1000" "check" 3. None [];
          row "n1000" "scan" 5. (Some 6.) [ ("read", 8.) ];
        ];
    }
  in
  let number = Alcotest.(option (float 0.)) in
  Alcotest.check number "peak" (Some 1.)
    (Report.peak report ~tree:"n1000" ~command:"scan");
  Alcotest.check number "no row" None
    (Report.peak report ~tree:"n10000" ~command:"scan");
  Alcotest.check number "instructions" (Some 2.)
    (Report.instructions report ~tree:"n1000" ~command:"scan");
  Alcotest.check number "no count" None
    (Report.instructions report ~tree:"n1000" ~command:"check");
  Alcotest.check number "no row" None
    (Report.instructions report ~tree:"self" ~command:"check");
  let words = Alcotest.(list (pair string (float 0.))) in
  Alcotest.check words "words"
    [ ("read", 7.) ]
    (Report.words report ~tree:"n1000" ~command:"scan");
  Alcotest.check words "no row" []
    (Report.words report ~tree:"n10000" ~command:"scan")

let read path = In_channel.with_open_bin path In_channel.input_all

let write path text =
  Out_channel.with_open_bin path (fun channel ->
      Out_channel.output_string channel text)

let run arguments =
  let output = Filename.temp_file "sinter-run" ".out" in
  let errors = Filename.temp_file "sinter-run" ".err" in
  let code =
    Sys.command
      (Printf.sprintf "../bench/run.exe %s >%s 2>%s"
         (String.concat " " (List.map Filename.quote arguments))
         (Filename.quote output) (Filename.quote errors))
  in
  Fun.protect
    ~finally:(fun () -> List.iter Sys.remove [ output; errors ])
    (fun () -> (code, read output, read errors))

let sinter = Unix.realpath "../bin/main.exe"
let generator = Unix.realpath "../bench/generate.exe"

let small_trees =
  lazy
    (let dir = Git_fixture.temp_dir () in
     List.iter
       (fun name ->
         let tree = Filename.concat dir (name ^ "-seed1") in
         Unix.mkdir tree 0o755;
         ignore
           (Generated_tree.write
              (Generated_tree.make ~seed:1 ~declarations:20)
              tree))
       [ "n1000"; "n10000" ];
     dir)

let budgets_file text =
  let path = Filename.temp_file "sinter-budgets" ".toml" in
  write path text;
  path

let measure ?(extra = []) budgets =
  run
    ([
       "--sinter";
       sinter;
       "--generator";
       generator;
       "--trees";
       Lazy.force small_trees;
       "--runs";
       "1";
       "--budgets";
       budgets_file budgets;
     ]
    @ extra)

let json_of output =
  match Yojson.Basic.from_string output with
  | json -> json
  | exception Yojson.Json_error message -> Alcotest.failf "no JSON: %s" message

let member name json = Yojson.Basic.Util.member name json

let run_skips_every_budget_that_it_cannot_check () =
  let code, output, errors =
    measure ~extra:[ "--sizes"; "1000" ]
      "[scan]\nallocation-growth = 0.5\n\n[check]\nallocation-growth = 0.5\n"
  in
  Alcotest.(check int) ("exit, with: " ^ errors) 0 code;
  let json = json_of output in
  let counted = member "instruction_counter" json <> `Null in
  List.iter
    (fun result ->
      Alcotest.(check int)
        "exit of sinter" 0
        Yojson.Basic.Util.(to_int (member "exit" result));
      Alcotest.(check bool)
        "a peak" true
        Yojson.Basic.Util.(
          to_number (member "median" (member "peak_kib" result)) > 0.);
      Alcotest.(check bool)
        "an instruction count when a counter counts" counted
        (member "instructions" result <> `Null);
      Alcotest.(check (list string))
        "the phases"
        Yojson.Basic.Util.(
          match to_string (member "command" result) with
          | "scan" ->
              [ "repository"; "read"; "parse"; "facts"; "records"; "output" ]
          | "check-diff" ->
              [
                "repository";
                "base-read";
                "read";
                "parse";
                "facts";
                "findings";
                "base-facts";
                "base-findings";
                "output";
              ]
          | _ ->
              [
                "repository";
                "base-read";
                "read";
                "parse";
                "facts";
                "findings";
                "output";
              ])
        (List.map
           (fun phase -> Yojson.Basic.Util.(to_string (member "phase" phase)))
           Yojson.Basic.Util.(to_list (member "phase_words" result))))
    Yojson.Basic.Util.(to_list (member "results" json));
  Alcotest.(check (list string))
    "outcomes"
    [
      "scan null skipped: the run counted no phase on the tree n1000 or on the \
       tree n10000";
      "check null skipped: the run counted no phase on the tree n1000 or on \
       the tree n10000";
    ]
    (List.map
       (fun outcome ->
         Yojson.Basic.Util.(
           String.concat " "
             [
               to_string (member "command" outcome);
               Yojson.Basic.to_string (member "phase" outcome);
               to_string (member "result" outcome) ^ ":";
               to_string (member "reason" outcome);
             ]))
       Yojson.Basic.Util.(to_list (member "budgets" json)))

let recorded ~platform ~small ~large =
  let summary median =
    Printf.sprintf {|{"median":%g,"min":%g,"max":%g,"spread_percent":0.0}|}
      median median median
  in
  let row tree command (peak, records) =
    Printf.sprintf
      {|{"tree":"%s","declarations":null,"command":"%s","exit":0,"peak_kib":%s,"instructions":null,"footprint_kib":null,"phase_words":[{"phase":"read","words":%g},{"phase":"records","words":%g}]}|}
      tree command (summary peak) (records /. 10.) records
  in
  Printf.sprintf
    {|{"platform":"%s","instruction_counter":null,"no_count_reason":"none","runs":5,"seed":1,"results":[%s],"budgets":[]}|}
    platform
    (String.concat ","
       [
         row "n1000" "scan" small;
         row "n1000" "check" small;
         row "n10000" "scan" large;
         row "n10000" "check" large;
       ])

let check_recorded ~platform ~small ~large budgets =
  let path = Filename.temp_file "sinter-results" ".json" in
  write path (recorded ~platform ~small ~large);
  let code, output, errors =
    run [ "--results"; path; "--budgets"; budgets_file budgets ]
  in
  ( code,
    List.map
      (fun outcome ->
        Yojson.Basic.Util.(
          String.concat " "
            (to_string (member "command" outcome)
             ::
             (match member "phase" outcome with
             | `String phase -> [ phase ]
             | _ -> [])
            @ [ to_string (member "result" outcome) ])))
      Yojson.Basic.Util.(to_list (member "budgets" (json_of output))),
    errors )

let limits =
  "[scan]\nallocation-growth = 10\n\n[check]\nallocation-growth = 10\n"

let run_fails_a_recorded_budget_with_exit_1 () =
  let code, outcomes, errors =
    check_recorded ~platform:"linux" ~small:(20000., 2e6) ~large:(85000., 21e6)
      limits
  in
  Alcotest.(check int) ("exit, with: " ^ errors) 1 code;
  Alcotest.(check (list string))
    "outcomes"
    [
      "scan read fail";
      "scan records fail";
      "check read fail";
      "check records fail";
    ]
    outcomes

let run_passes_recorded_budgets_with_exit_0 () =
  let code, outcomes, errors =
    check_recorded ~platform:"linux" ~small:(20000., 2e6) ~large:(70000., 19e6)
      limits
  in
  Alcotest.(check int) ("exit, with: " ^ errors) 0 code;
  Alcotest.(check (list string))
    "outcomes"
    [
      "scan read pass";
      "scan records pass";
      "check read pass";
      "check records pass";
    ]
    outcomes

let run_checks_the_growth_on_macos () =
  let code, outcomes, errors =
    check_recorded ~platform:"macos" ~small:(20000., 2e6) ~large:(85000., 21e6)
      limits
  in
  Alcotest.(check int) ("exit, with: " ^ errors) 1 code;
  Alcotest.(check (list string))
    "outcomes"
    [
      "scan read fail";
      "scan records fail";
      "check read fail";
      "check records fail";
    ]
    outcomes

let run_writes_its_files () =
  let dir = Git_fixture.temp_dir () in
  let json = Filename.concat dir "out.json" in
  let markdown = Filename.concat dir "summary.md" in
  let outputs = Filename.concat dir "outputs" in
  write markdown "before\n";
  let code, output, errors =
    run
      [
        "--sinter";
        sinter;
        "--generator";
        generator;
        "--trees";
        Lazy.force small_trees;
        "--sizes";
        "1000";
        "--runs";
        "1";
        "--json";
        json;
        "--markdown";
        markdown;
        "--outputs";
        outputs;
      ]
  in
  Alcotest.(check int) ("exit, with: " ^ errors) 0 code;
  Alcotest.(check string) "standard output" "" output;
  ignore (json_of (read json));
  Alcotest.(check bool)
    "the table is appended" true
    (String.starts_with ~prefix:"before\n## Performance\n" (read markdown));
  Alcotest.(check bool)
    "the table goes to standard error" true
    (String.starts_with ~prefix:"measured n1000 scan\n" errors);
  Alcotest.(check bool)
    "the output of scan is kept" true
    (String.starts_with ~prefix:"{\"base\":"
       (read (Filename.concat outputs "n1000-scan.out")));
  Alcotest.(check bool)
    "the output of check is kept" true
    (Sys.file_exists (Filename.concat outputs "n1000-check.out"))

let fake_sinter () =
  let fake = Filename.concat (Git_fixture.temp_dir ()) "sinter" in
  write fake "#!/bin/sh\nexit 0\n";
  Unix.chmod fake 0o755;
  fake

let run_measures_a_sinter_that_counts_no_phase () =
  let code, output, errors =
    run
      [
        "--sinter";
        fake_sinter ();
        "--generator";
        generator;
        "--trees";
        Lazy.force small_trees;
        "--sizes";
        "1000";
        "--runs";
        "1";
      ]
  in
  Alcotest.(check int) ("exit, with: " ^ errors) 0 code;
  List.iter
    (fun result ->
      Alcotest.(check int)
        "no phase" 0
        (List.length Yojson.Basic.Util.(to_list (member "phase_words" result))))
    Yojson.Basic.Util.(to_list (member "results" (json_of output)))

let run_with_budgets_stops_when_sinter_counts_no_phase () =
  let code, output, errors =
    run
      [
        "--sinter";
        fake_sinter ();
        "--generator";
        generator;
        "--trees";
        Lazy.force small_trees;
        "--sizes";
        "1000";
        "--runs";
        "1";
        "--budgets";
        budgets_file budgets_text;
      ]
  in
  Alcotest.(check int) "exit" 2 code;
  Alcotest.(check string) "output" "" output;
  Alcotest.(check string)
    "errors" "run: sinter scan on n1000: it wrote no words of its phases\n"
    errors

let run_makes_a_missing_tree () =
  let dir = Filename.concat (Git_fixture.temp_dir ()) "trees" in
  let code, _, errors =
    run
      [
        "--sinter";
        sinter;
        "--generator";
        generator;
        "--trees";
        dir;
        "--sizes";
        "20";
        "--runs";
        "1";
      ]
  in
  Alcotest.(check int) ("exit, with: " ^ errors) 0 code;
  Alcotest.(check bool)
    "the tree" true
    (Sys.file_exists (Filename.concat dir "n20-seed1/repo/sinter.toml"))

let run_measures_the_checkout_as_self () =
  let repo = Git_fixture.init () in
  Git_fixture.write repo "a.md" "# A\n\n@req a\n";
  ignore (Git_fixture.git repo [ "add"; "a.md" ]);
  ignore (Git_fixture.git repo [ "commit"; "-q"; "-m"; "a" ]);
  let manifest = Filename.temp_file "sinter-self" ".toml" in
  write manifest "[scan]\npacks.markdown.files = [\"**/*.md\"]\n";
  let code, output, errors =
    run
      [
        "--sinter";
        sinter;
        "--self";
        Git_fixture.root repo;
        "--self-manifest";
        manifest;
        "--sizes";
        "";
        "--runs";
        "1";
      ]
  in
  Alcotest.(check int) ("exit, with: " ^ errors) 0 code;
  Alcotest.(check (list (pair string string)))
    "trees and commands"
    [ ("self", "scan"); ("self", "check"); ("self", "check-diff") ]
    (List.map
       (fun result ->
         Yojson.Basic.Util.
           ( to_string (member "tree" result),
             to_string (member "command" result) ))
       Yojson.Basic.Util.(to_list (member "results" (json_of output))))

let run_stops_with_exit_2 () =
  let missing = Filename.concat (Git_fixture.temp_dir ()) "missing" in
  let bad = budgets_file "[scan]\n" in
  let memory =
    budgets_file "[scan]\nallocation-growth = 1\npeak-memory-kib = 90000\n"
  in
  let outside = Git_fixture.temp_dir () in
  let not_json = budgets_file "{" in
  let not_json_message =
    match Yojson.Basic.from_string "{" with
    | _ -> Alcotest.fail "the text reads as JSON"
    | exception Yojson.Json_error message -> message
  in
  let no_runs =
    budgets_file
      {|{"platform":"linux","instruction_counter":null,"no_count_reason":null,"seed":1,"results":[]}|}
  in
  List.iter
    (fun (arguments, expected) ->
      let code, output, errors = run arguments in
      Alcotest.(check int) (expected ^ ": exit") 2 code;
      Alcotest.(check string) (expected ^ ": output") "" output;
      Alcotest.(check string) (expected ^ ": errors") expected errors)
    [
      ([ "--sinter"; missing ], Printf.sprintf "run: %s is missing\n" missing);
      ( [ "--sinter"; sinter; "--runs"; "0" ],
        "run: --runs is 0, and it must be 1 or more\n" );
      ([ "--sinter"; sinter; "--sizes"; "1" ], "run: the size 1 is below 2\n");
      ( [ "--sinter"; sinter; "--budgets"; bad ],
        Printf.sprintf "run: %s: scan.allocation-growth is missing\n" bad );
      ( [ "--sinter"; sinter; "--budgets"; memory ],
        Printf.sprintf "run: %s: [scan]: unknown key peak-memory-kib\n" memory
      );
      ( [ "--sinter"; sinter; "--sizes"; "20" ],
        "run: --generator is missing, and --sizes names trees\n" );
      ([], "run: either --sinter or --results is required\n");
      ( [ "--sinter"; sinter; "--results"; missing ],
        "run: --results and --sinter exclude each other\n" );
      ( [ "--results"; not_json ],
        Printf.sprintf "run: %s: not JSON: %s\n" not_json not_json_message );
      ( [ "--results"; no_runs ],
        Printf.sprintf "run: %s: the key runs is missing\n" no_runs );
      ( [ "--results"; missing ],
        Printf.sprintf "run: %s: No such file or directory\n" missing );
    ];
  let code, output, errors =
    run [ "--sinter"; sinter; "--sizes"; ""; "--self"; outside ]
  in
  Alcotest.(check int) "not a checkout: exit" 2 code;
  Alcotest.(check string) "not a checkout: output" "" output;
  Alcotest.(check bool)
    ("not a checkout: errors: " ^ errors)
    true
    (String.starts_with
       ~prefix:(Printf.sprintf "run: %s is not in a git checkout: " outside)
       errors)

let run_with_an_unknown_option_is_a_usage_error () =
  let code, output, _ = run [ "--sinter"; sinter; "--wall-time" ] in
  Alcotest.(check int) "exit" 124 code;
  Alcotest.(check string) "output" "" output

let tests =
  [
    case "budgets of check-diff are optional" budgets_of_check_diff_are_optional;
    case "check judges the budgets of check-diff"
      check_judges_the_budgets_of_check_diff;
    case "gnu time reads the last line" gnu_time_reads_the_last_line;
    case "gnu time refuses text that is not a number"
      gnu_time_refuses_text_that_is_not_a_number;
    case "bsd time reads bytes as KiB" bsd_time_reads_bytes_as_kib;
    case "bsd time without counts gives none" bsd_time_without_counts_gives_none;
    case "bsd time needs the resident set size"
      bsd_time_needs_the_resident_set_size;
    case "perf stat reads the count" perf_stat_reads_the_count;
    case "perf stat adds the counts of two kinds of core"
      perf_stat_adds_the_counts_of_two_kinds_of_core;
    case "perf stat without a count gives none"
      perf_stat_without_a_count_gives_none;
    case "perf stat refuses text without instructions"
      perf_stat_refuses_text_without_instructions;
    decoders_never_raise;
    case "summary of values" summary_of_values;
    case "summary refuses no value" summary_refuses_no_value;
    summary_orders_its_values;
    case "budgets give each limit" budgets_give_each_limit;
    case "budgets refuse a memory budget" budgets_refuse_a_memory_budget;
    case "budgets refuse a bad file" budgets_refuse_a_bad_file;
    case "check judges each phase" check_judges_each_phase;
    check_passes_a_phase_at_or_under_its_limit;
    case "check skips what the run did not measure"
      check_skips_what_the_run_did_not_measure;
    case "phase words reads a line per phase" phase_words_reads_a_line_per_phase;
    case "phase words refuses a bad file" phase_words_refuses_a_bad_file;
    report_round_trips;
    report_reader_never_raises;
    case "a report names the key it lacks" a_report_names_the_key_it_lacks;
    case "a report reads the first row of a tree and command"
      a_report_reads_the_first_row_of_a_tree_and_command;
    case "run skips every budget that it cannot check"
      run_skips_every_budget_that_it_cannot_check;
    case "run fails a recorded budget with exit 1"
      run_fails_a_recorded_budget_with_exit_1;
    case "run passes recorded budgets with exit 0"
      run_passes_recorded_budgets_with_exit_0;
    case "run checks the growth on macos" run_checks_the_growth_on_macos;
    case "run writes its files" run_writes_its_files;
    case "run measures a sinter that counts no phase"
      run_measures_a_sinter_that_counts_no_phase;
    case "run with budgets stops when sinter counts no phase"
      run_with_budgets_stops_when_sinter_counts_no_phase;
    case "run makes a missing tree" run_makes_a_missing_tree;
    case "run measures the checkout as self" run_measures_the_checkout_as_self;
    case "run stops with exit 2" run_stops_with_exit_2;
    case "run with an unknown option is a usage error"
      run_with_an_unknown_option_is_a_usage_error;
  ]
