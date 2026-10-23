(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

module A = Sinter_bridge.Adapter
module W = Wasm_builder

let page = 65536
let fuel = 1_000_000
let memory = 4 * page

(* One engine for every test below. The collector frees it when the
   test binary ends. *)
let engine = lazy (Sinter_bridge.create ())

let property ?(count = 100) ~name ~print generator check =
  QCheck_alcotest.to_alcotest ~speed_level:`Quick
    (QCheck2.Test.make ~count ~name ~print generator check)

let error_t =
  Alcotest.testable
    (fun formatter error -> Format.pp_print_string formatter (A.message error))
    ( = )

let load ?(fuel = fuel) ?(memory = memory) spec =
  A.load (Lazy.force engine) ~wasm:(W.adapter_module spec) ~fuel ~memory

let loaded ?fuel ?memory spec =
  match load ?fuel ?memory spec with
  | Ok adapter -> adapter
  | Error error -> Alcotest.fail (A.message error)

let load_error ?fuel ?memory spec =
  match load ?fuel ?memory spec with
  | Ok _ -> Alcotest.fail "the module loaded"
  | Error error -> error

let call ?(fuel = fuel) ?(memory = memory) ?(request = "{}") ?(report = "<r/>")
    ?(function_ = A.Bind) spec =
  A.call (loaded spec) function_ ~request ~report ~fuel ~memory

let call_error ?fuel ?memory ?request ?report ?function_ spec =
  match call ?fuel ?memory ?request ?report ?function_ spec with
  | Ok _ -> Alcotest.fail "the call gave a response"
  | Error error -> error

let loads_a_valid_adapter () =
  let adapter = loaded W.adapter in
  Alcotest.(check int) "the version" 1 (A.version adapter);
  Alcotest.(check (result string error_t))
    "recognise" (Ok {|{"recognised":true}|})
    (A.call adapter A.Recognise ~request:"{}" ~report:"<r/>" ~fuel ~memory)

let reads_the_version_as_unsigned () =
  Alcotest.(check int)
    "-1 is 2^32 - 1" 0xFFFFFFFF
    (A.version (loaded { W.adapter with version = 0xFFFFFFFF }))

let allows_other_exports () =
  Alcotest.(check int)
    "a module with __data_end and __heap_base loads" 1
    (A.version (loaded { W.adapter with extra_exports = true }))

let bind_gives_back_the_report =
  property ~name:"bind gives back the report, any bytes" ~print:String.escaped
    QCheck2.Gen.(string_size ~gen:char (int_bound 200))
    (fun report -> call ~report W.adapter = Ok report)

let a_call_gives_back_the_request =
  property ~name:"a call gives back the request, any bytes"
    ~print:String.escaped
    QCheck2.Gen.(string_size ~gen:char (int_bound 200))
    (fun request ->
      call ~request ~function_:A.Recognise
        { W.adapter with recognise = W.Echo_request }
      = Ok request)

let invalid cause = A.Invalid cause

let refuses_bytes_that_are_not_a_module () =
  match A.load (Lazy.force engine) ~wasm:"not wasm" ~fuel ~memory with
  | Error (A.Invalid (A.Not_a_module _)) -> ()
  | Error error -> Alcotest.fail (A.message error)
  | Ok _ -> Alcotest.fail "the bytes loaded"

let refuses_an_import () =
  Alcotest.check error_t "a function import"
    (invalid (A.Imports [ "env.f" ]))
    (load_error
       { W.adapter with extra_imports = [ ("env", "f", W.Import_func 0) ] });
  Alcotest.check error_t "a memory import"
    (invalid (A.Imports [ "env.memory" ]))
    (load_error
       {
         W.adapter with
         extra_imports = [ ("env", "memory", W.Import_memory 1) ];
       })

let refuses_a_missing_export () =
  List.iter
    (fun name ->
      Alcotest.check error_t name
        (invalid (A.Missing_export name))
        (load_error { W.adapter with missing = [ name ] }))
    [
      "memory";
      "sinter_interface";
      "sinter_alloc";
      "sinter_recognise";
      "sinter_bind";
    ]

let refuses_an_export_of_the_wrong_type () =
  List.iter
    (fun (name, kind) ->
      Alcotest.check error_t name
        (invalid (A.Wrong_export_type name))
        (load_error { W.adapter with wrong_types = [ (name, kind) ] }))
    [
      ("sinter_interface", ([ W.I32 ], [ W.I32 ]));
      ("sinter_alloc", ([ W.I32 ], [ W.I64 ]));
      ("sinter_recognise", ([ W.I32; W.I32; W.I32 ], [ W.I64 ]));
      ("sinter_bind", ([ W.I32; W.I32; W.I32; W.I32 ], [ W.I32 ]));
    ];
  Alcotest.check error_t "memory as a global"
    (invalid (A.Wrong_export_type "memory"))
    (load_error { W.adapter with memory_as_global = true })

(* The runtime of adapters does not read the threads or the memory64
   proposals, so it refuses both memories as it compiles the module. *)
let refuses_a_shared_memory_and_a_64_bit_memory () =
  List.iter
    (fun (feature, change) ->
      match load_error { W.adapter with memory_kind = change } with
      | A.Invalid (A.Not_a_module message) ->
          Alcotest.(check bool)
            ("the message names " ^ feature)
            true
            (String.length message > 0
            && List.exists
                 (fun word -> String.equal word feature)
                 (String.split_on_char ' ' message))
      | error -> Alcotest.fail (A.message error))
    [
      ("threads", fun m -> { m with W.shared = true; maximum = Some 2 });
      ("memory64", fun m -> { m with W.memory64 = true });
    ]

let runs_the_interface_under_the_limits () =
  Alcotest.check error_t "a loop" A.Out_of_fuel
    (load_error
       {
         W.adapter with
         interface_body = Some [ W.loop_forever; W.unreachable ];
       });
  (match
     load_error { W.adapter with interface_body = Some [ W.unreachable ] }
   with
  | A.Trap _ -> ()
  | error -> Alcotest.fail (A.message error));
  Alcotest.check error_t "a memory above the limit"
    (A.Memory_limit (3 * page))
    (load_error ~memory:(2 * page) { W.adapter with pages = 3 })

let stops_a_call_that_runs_out_of_fuel () =
  Alcotest.check error_t "a loop" A.Out_of_fuel
    (call_error { W.adapter with bind = W.Loop })

(* The two calls of sinter_alloc cost more than five units, and the
   function alone costs fewer. *)
let counts_the_allocations_in_the_fuel () =
  let spec = { W.adapter with bind = W.Respond "{}" } in
  Alcotest.check error_t "five units" A.Out_of_fuel (call_error ~fuel:5 spec);
  Alcotest.(check (result string error_t))
    "enough units" (Ok "{}") (call ~fuel:100 spec)

let stops_a_growth_past_the_memory_limit () =
  Alcotest.check error_t "100 pages more than one"
    (A.Memory_limit (101 * page))
    (call_error ~memory:(2 * page) { W.adapter with bind = W.Grow 100 })

let reports_a_trap () =
  match call_error { W.adapter with bind = W.Trap } with
  | A.Trap message ->
      Alcotest.(check bool) "the message of the runtime" true (message <> "")
  | error -> Alcotest.fail (A.message error)

let reports_an_allocator_that_gives_zero () =
  Alcotest.check error_t "the request"
    (A.Alloc { input = A.Request; address = 0; length = 2; memory_size = page })
    (call_error ~request:"{}" { W.adapter with alloc = W.Zero })

let reports_an_allocation_outside_memory () =
  Alcotest.check error_t "an address near 2^32"
    (A.Alloc
       {
         input = A.Request;
         address = 0xFFFFFFF0;
         length = 2;
         memory_size = page;
       })
    (call_error ~request:"{}" { W.adapter with alloc = W.Address 0xFFFFFFF0 });
  (* The bump allocator does not grow the memory, so a report longer
     than the memory gets an address whose bytes run past it. *)
  match call_error ~report:(String.make (page + 1) 'x') W.adapter with
  | A.Alloc { input = A.Report; length; _ } ->
      Alcotest.(check int) "the length of the report" (page + 1) length
  | error -> Alcotest.fail (A.message error)

let reports_a_response_outside_memory () =
  Alcotest.check error_t "an address near 2^32"
    (A.Response_outside_memory
       { address = 0xFFFFFFF0; length = 16; memory_size = page })
    (call_error { W.adapter with bind = W.Range (0xFFFFFFF0, 16) });
  Alcotest.check error_t "one byte past the end"
    (A.Response_outside_memory
       { address = page - 6; length = 7; memory_size = page })
    (call_error { W.adapter with bind = W.Range (page - 6, 7) })

let takes_a_response_at_the_end_of_memory () =
  Alcotest.(check (result string error_t))
    "six bytes that end the memory"
    (Ok (String.make 6 '\000'))
    (call { W.adapter with bind = W.Range (page - 6, 6) });
  Alcotest.(check (result string error_t))
    "no byte at the end of the memory" (Ok "")
    (call { W.adapter with bind = W.Range (page, 0) })

let writes_an_empty_report () =
  Alcotest.(check (result string error_t))
    "an empty report" (Ok "")
    (call ~report:"" W.adapter)

(* The response is the first bytes of the memory, as many as the
   allocation pointer says, so a call that saw the pointer of an earlier
   call would give a longer response. *)
let makes_each_call_in_a_new_instance () =
  let spec =
    { W.adapter with bind = W.Custom [ W.global_get 0; W.i64_extend_i32_u ] }
  in
  let adapter = loaded spec in
  let once () =
    A.call adapter A.Bind ~request:"{}" ~report:"<r/>" ~fuel ~memory
  in
  let first = once () in
  Alcotest.(check (result int error_t))
    "the pointer after two allocations"
    (Ok (1024 + 2 + 4))
    (Result.map String.length first);
  Alcotest.(check (result string error_t)) "the second call" first (once ())

let refuses_a_limit_below_zero () =
  let adapter = loaded W.adapter in
  Alcotest.check_raises "fuel"
    (Invalid_argument "Sinter_bridge.Adapter: the fuel limit is below 0")
    (fun () ->
      ignore (A.call adapter A.Bind ~request:"" ~report:"" ~fuel:(-1) ~memory));
  Alcotest.check_raises "memory"
    (Invalid_argument "Sinter_bridge.Adapter: the memory limit is below 0")
    (fun () -> ignore (load ~memory:(-1) W.adapter))

(* A limit of 0 is a limit, not a fault of the caller: the module runs
   out of fuel at once, and its one page of memory is past the limit. *)
let takes_a_limit_of_zero () =
  Alcotest.check error_t "a load with no fuel" A.Out_of_fuel
    (load_error ~fuel:0 W.adapter);
  Alcotest.check error_t "a load with no memory" (A.Memory_limit page)
    (load_error ~memory:0 W.adapter);
  Alcotest.check error_t "a call with no fuel" A.Out_of_fuel
    (call_error ~fuel:0 W.adapter);
  Alcotest.check error_t "a call with no memory" (A.Memory_limit page)
    (call_error ~memory:0 W.adapter)

let an_adapter_outlives_its_engine () =
  let engine = Sinter_bridge.create () in
  let adapter =
    match A.load engine ~wasm:(W.adapter_module W.adapter) ~fuel ~memory with
    | Ok adapter -> adapter
    | Error error -> Alcotest.fail (A.message error)
  in
  Sinter_bridge.close engine;
  Alcotest.(check (result string error_t))
    "a call after the engine is closed" (Ok "<r/>")
    (A.call adapter A.Bind ~request:"{}" ~report:"<r/>" ~fuel ~memory);
  Alcotest.check_raises "a load with the closed engine"
    (Invalid_argument "Sinter_bridge: the engine is closed") (fun () ->
      ignore (A.load engine ~wasm:(W.adapter_module W.adapter) ~fuel ~memory));
  A.close adapter;
  let closed = Invalid_argument "Sinter_bridge: the adapter is closed" in
  Alcotest.check_raises "version" closed (fun () -> ignore (A.version adapter));
  Alcotest.check_raises "call" closed (fun () ->
      ignore (A.call adapter A.Bind ~request:"" ~report:"" ~fuel ~memory));
  A.close adapter

let gives_a_message_for_each_error () =
  let check expected error =
    Alcotest.(check string) expected expected (A.message error)
  in
  check "the adapter is not a WebAssembly module: m"
    (invalid (A.Not_a_module "m"));
  check "the adapter imports env.f, env.g, and an adapter imports nothing"
    (invalid (A.Imports [ "env.f"; "env.g" ]));
  check "the adapter does not export memory"
    (invalid (A.Missing_export "memory"));
  check "the export memory of the adapter has the wrong type"
    (invalid (A.Wrong_export_type "memory"));
  check "the adapter ran past its limit of fuel" A.Out_of_fuel;
  check "the adapter stopped: m" (A.Trap "m");
  check "the adapter asked for 131072 bytes of memory, which is past its limit"
    (A.Memory_limit 131072);
  check "sinter_alloc gave 0 for the 2 bytes of the request"
    (A.Alloc { input = A.Request; address = 0; length = 2; memory_size = 65536 });
  check
    "sinter_alloc gave the address 9 for the 3 bytes of the report, and the \
     memory holds 10 bytes"
    (A.Alloc { input = A.Report; address = 9; length = 3; memory_size = 10 });
  check
    "the response at the address 9 holds 3 bytes, and the memory holds 10 bytes"
    (A.Response_outside_memory { address = 9; length = 3; memory_size = 10 })

let tests =
  [
    Alcotest.test_case "loads a valid adapter" `Quick loads_a_valid_adapter;
    Alcotest.test_case "reads the version as unsigned" `Quick
      reads_the_version_as_unsigned;
    Alcotest.test_case "allows other exports" `Quick allows_other_exports;
    Alcotest.test_case "refuses bytes that are not a module" `Quick
      refuses_bytes_that_are_not_a_module;
    Alcotest.test_case "refuses an import" `Quick refuses_an_import;
    Alcotest.test_case "refuses a missing export" `Quick
      refuses_a_missing_export;
    Alcotest.test_case "refuses an export of the wrong type" `Quick
      refuses_an_export_of_the_wrong_type;
    Alcotest.test_case "refuses a shared memory and a 64-bit memory" `Quick
      refuses_a_shared_memory_and_a_64_bit_memory;
    Alcotest.test_case "runs the interface under the limits" `Quick
      runs_the_interface_under_the_limits;
    Alcotest.test_case "stops a call that runs out of fuel" `Quick
      stops_a_call_that_runs_out_of_fuel;
    Alcotest.test_case "counts the allocations in the fuel" `Quick
      counts_the_allocations_in_the_fuel;
    Alcotest.test_case "stops a growth past the memory limit" `Quick
      stops_a_growth_past_the_memory_limit;
    Alcotest.test_case "reports a trap" `Quick reports_a_trap;
    Alcotest.test_case "reports an allocator that gives zero" `Quick
      reports_an_allocator_that_gives_zero;
    Alcotest.test_case "reports an allocation outside memory" `Quick
      reports_an_allocation_outside_memory;
    Alcotest.test_case "reports a response outside memory" `Quick
      reports_a_response_outside_memory;
    Alcotest.test_case "takes a response at the end of memory" `Quick
      takes_a_response_at_the_end_of_memory;
    Alcotest.test_case "writes an empty report" `Quick writes_an_empty_report;
    Alcotest.test_case "makes each call in a new instance" `Quick
      makes_each_call_in_a_new_instance;
    Alcotest.test_case "refuses a limit below zero" `Quick
      refuses_a_limit_below_zero;
    Alcotest.test_case "takes a limit of zero" `Quick takes_a_limit_of_zero;
    Alcotest.test_case "an adapter outlives its engine" `Quick
      an_adapter_outlives_its_engine;
    Alcotest.test_case "gives a message for each error" `Quick
      gives_a_message_for_each_error;
    bind_gives_back_the_report;
    a_call_gives_back_the_request;
  ]
