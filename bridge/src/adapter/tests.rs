// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 The Sinter Authors

//! Tests of adapters, with modules built from bytes in the tests.

use super::*;
use crate::failure::CAUSE_NOT_A_MODULE;

fn leb(mut value: u64) -> Vec<u8> {
    let mut bytes = Vec::new();
    loop {
        let part = (value & 0x7f) as u8;
        value >>= 7;
        if value == 0 {
            bytes.push(part);
            return bytes;
        }
        bytes.push(part | 0x80);
    }
}

fn sleb(mut value: i64) -> Vec<u8> {
    let mut bytes = Vec::new();
    loop {
        let part = (value & 0x7f) as u8;
        value >>= 7;
        let done = (value == 0 && part & 0x40 == 0) || (value == -1 && part & 0x40 != 0);
        if done {
            bytes.push(part);
            return bytes;
        }
        bytes.push(part | 0x80);
    }
}

fn list(items: &[Vec<u8>]) -> Vec<u8> {
    let mut bytes = leb(items.len() as u64);
    for item in items {
        bytes.extend_from_slice(item);
    }
    bytes
}

fn name(text: &str) -> Vec<u8> {
    [leb(text.len() as u64), text.as_bytes().to_vec()].concat()
}

fn section(identifier: u8, items: &[Vec<u8>]) -> Vec<u8> {
    let body = list(items);
    [vec![identifier], leb(body.len() as u64), body].concat()
}

fn limits(minimum: u32, maximum: Option<u32>) -> Vec<u8> {
    match maximum {
        None => [vec![0x00], leb(minimum.into())].concat(),
        Some(maximum) => [vec![0x01], leb(minimum.into()), leb(maximum.into())].concat(),
    }
}

const I32: u8 = 0x7f;
const I64: u8 = 0x7e;
const FOUR_I32: [u8; 4] = [I32; 4];

fn i32_const(value: i32) -> Vec<u8> {
    [vec![0x41], sleb(value.into())].concat()
}

fn i64_const(value: i64) -> Vec<u8> {
    [vec![0x42], sleb(value)].concat()
}

fn response(address: u32, length: u32) -> Vec<u8> {
    i64_const(((u64::from(address) << 32) | u64::from(length)) as i64)
}

#[derive(Clone)]
struct ModuleFunction {
    export: Option<&'static str>,
    params: Vec<u8>,
    results: Vec<u8>,
    locals: Vec<u8>,
    body: Vec<u8>,
}

fn function(export: &'static str, params: &[u8], results: &[u8], body: Vec<u8>) -> ModuleFunction {
    ModuleFunction {
        export: Some(export),
        params: params.to_vec(),
        results: results.to_vec(),
        locals: vec![],
        body,
    }
}

/// A module, in parts that a test can change.
#[derive(Clone)]
pub(crate) struct Wasm {
    imports: Vec<Vec<u8>>,
    functions: Vec<ModuleFunction>,
    memories: Vec<(u32, Option<u32>)>,
    tables: Vec<u32>,
    globals: Vec<Vec<u8>>,
    exports: Vec<(&'static str, u8, u32)>,
    data: Vec<(i32, Vec<u8>)>,
}

const ALLOC: usize = 1;
const RECOGNISE: usize = 2;
/// The index of the function `sinter_bind` in `Wasm::good`.
pub(crate) const BIND: usize = 3;

/// The response of `sinter_recognise` in `Wasm::good`, at byte 16.
pub(crate) const RECOGNISED: &[u8] = b"{\"recognised\":true}";

fn echo_report() -> Vec<u8> {
    [
        vec![0x20, 2, 0xad],
        i64_const(32),
        vec![0x86, 0x20, 3, 0xad, 0x84],
    ]
    .concat()
}

impl Wasm {
    fn with_next(next: i32) -> Wasm {
        let alloc = [vec![0x23, 0, 0x23, 0, 0x20, 0, 0x6a, 0x24, 0]].concat();
        Wasm {
            imports: vec![],
            functions: vec![
                function("sinter_interface", &[], &[I32], i32_const(1)),
                function("sinter_alloc", &[I32], &[I32], alloc),
                function(
                    "sinter_recognise",
                    &FOUR_I32,
                    &[I64],
                    response(16, RECOGNISED.len() as u32),
                ),
                function("sinter_bind", &FOUR_I32, &[I64], echo_report()),
            ],
            memories: vec![(1, None)],
            tables: vec![],
            globals: vec![[vec![I32, 0x01], i32_const(next), vec![0x0b]].concat()],
            exports: vec![("memory", 0x02, 0)],
            data: vec![(16, RECOGNISED.to_vec())],
        }
    }

    pub(crate) fn good() -> Wasm {
        Wasm::with_next(1024)
    }

    /// The same module, with the body of function `index` replaced.
    pub(crate) fn body(mut self, index: usize, body: Vec<u8>) -> Wasm {
        self.functions[index].body = body;
        self
    }

    pub(crate) fn bytes(&self) -> Vec<u8> {
        let mut bytes = b"\0asm\x01\0\0\0".to_vec();
        let types: Vec<Vec<u8>> = self
            .functions
            .iter()
            .map(|f| {
                let params: Vec<Vec<u8>> = f.params.iter().map(|t| vec![*t]).collect();
                let results: Vec<Vec<u8>> = f.results.iter().map(|t| vec![*t]).collect();
                [vec![0x60], list(&params), list(&results)].concat()
            })
            .collect();
        bytes.extend(section(1, &types));
        if !self.imports.is_empty() {
            bytes.extend(section(2, &self.imports));
        }
        let indices: Vec<Vec<u8>> = (0..self.functions.len())
            .map(|index| leb(index as u64))
            .collect();
        bytes.extend(section(3, &indices));
        if !self.tables.is_empty() {
            let tables: Vec<Vec<u8>> = self
                .tables
                .iter()
                .map(|minimum| [vec![0x70], limits(*minimum, None)].concat())
                .collect();
            bytes.extend(section(4, &tables));
        }
        let memories: Vec<Vec<u8>> = self
            .memories
            .iter()
            .map(|(minimum, maximum)| limits(*minimum, *maximum))
            .collect();
        bytes.extend(section(5, &memories));
        if !self.globals.is_empty() {
            bytes.extend(section(6, &self.globals));
        }
        let mut exports: Vec<Vec<u8>> = self
            .functions
            .iter()
            .enumerate()
            .filter_map(|(index, f)| {
                f.export
                    .map(|export| [name(export), vec![0x00], leb(index as u64)].concat())
            })
            .collect();
        for (export, kind, index) in &self.exports {
            exports.push([name(export), vec![*kind], leb((*index).into())].concat());
        }
        bytes.extend(section(7, &exports));
        let code: Vec<Vec<u8>> = self
            .functions
            .iter()
            .map(|f| {
                let locals: Vec<Vec<u8>> = f.locals.iter().map(|t| vec![1, *t]).collect();
                let body = [list(&locals), f.body.clone(), vec![0x0b]].concat();
                [leb(body.len() as u64), body].concat()
            })
            .collect();
        bytes.extend(section(10, &code));
        if !self.data.is_empty() {
            let data: Vec<Vec<u8>> = self
                .data
                .iter()
                .map(|(offset, content)| {
                    [
                        vec![0x00],
                        i32_const(*offset),
                        vec![0x0b],
                        name_bytes(content),
                    ]
                    .concat()
                })
                .collect();
            bytes.extend(section(11, &data));
        }
        bytes
    }
}

fn name_bytes(content: &[u8]) -> Vec<u8> {
    [leb(content.len() as u64), content.to_vec()].concat()
}

fn engine() -> Engine {
    let mut config = wasmtime::Config::new();
    config.consume_fuel(true);
    Engine::new(&config).unwrap()
}

const FUEL: u64 = 1_000_000;
const PAGE: u64 = 65536;
const MEMORY: u64 = 16 * PAGE;

fn load_wasm(wasm: &Wasm) -> Result<Adapter, Failure> {
    load(&engine(), &wasm.bytes(), FUEL, MEMORY)
}

fn call_with(
    wasm: &Wasm,
    function: Function,
    report: &[u8],
    fuel: u64,
    memory: u64,
) -> Result<Vec<u8>, Failure> {
    let adapter = load_wasm(wasm)?;
    call(
        &adapter,
        function,
        b"{\"interface\":1}",
        report,
        fuel,
        memory,
    )
}

fn bind(wasm: &Wasm, report: &[u8]) -> Result<Vec<u8>, Failure> {
    call_with(wasm, Function::Bind, report, FUEL, MEMORY)
}

fn recognise(wasm: &Wasm) -> Result<Vec<u8>, Failure> {
    call_with(wasm, Function::Recognise, b"", FUEL, MEMORY)
}

fn invalid_with(cause: u32, detail: &str) -> Result<Adapter, Failure> {
    Err(Failure::AdapterInvalid {
        cause,
        details: vec![detail.to_owned()],
    })
}

fn assert_load_fails(wasm: &Wasm, expected: Result<Adapter, Failure>) {
    match (load_wasm(wasm), expected) {
        (Err(found), Err(expected)) => assert_eq!(found, expected),
        (Ok(_), _) => panic!("the module loaded"),
        (Err(found), Ok(_)) => panic!("the module did not load: {found:?}"),
    }
}

#[test]
fn a_valid_adapter_loads_and_gives_its_interface() {
    assert_eq!(load_wasm(&Wasm::good()).unwrap().interface, 1);
}

#[test]
fn the_interface_is_read_as_unsigned() {
    let wasm = Wasm::good().body(0, i32_const(-1));
    assert_eq!(load_wasm(&wasm).unwrap().interface, u32::MAX);
}

#[test]
fn recognise_gives_the_response_of_the_module() {
    assert_eq!(recognise(&Wasm::good()).unwrap(), RECOGNISED);
}

#[test]
fn bind_gets_the_report_as_written() {
    let report = b"<testsuite name=\"a\"/>\n\xff";
    assert_eq!(bind(&Wasm::good(), report).unwrap(), report);
}

#[test]
fn bind_gets_the_request_as_written() {
    let echo_request = [
        vec![0x20, 0, 0xad],
        i64_const(32),
        vec![0x86, 0x20, 1, 0xad, 0x84],
    ]
    .concat();
    let wasm = Wasm::good().body(BIND, echo_request);
    let adapter = load_wasm(&wasm).unwrap();
    assert_eq!(
        call(&adapter, Function::Bind, b"{\"a\":1}", b"r", FUEL, MEMORY).unwrap(),
        b"{\"a\":1}"
    );
}

#[test]
fn an_empty_report_is_written_and_given_back() {
    assert_eq!(bind(&Wasm::good(), b"").unwrap(), b"");
}

#[test]
fn each_call_runs_in_a_new_instance() {
    let body = [
        i32_const(1000),
        i32_const(16),
        vec![0x2d, 0, 0],
        vec![0x3a, 0, 0],
        i32_const(16),
        i32_const(65),
        vec![0x3a, 0, 0],
        response(1000, 1),
    ]
    .concat();
    let adapter = load_wasm(&Wasm::good().body(BIND, body)).unwrap();
    for _ in 0..2 {
        assert_eq!(
            call(&adapter, Function::Bind, b"q", b"r", FUEL, MEMORY).unwrap(),
            b"{"
        );
    }
}

#[test]
fn bytes_that_are_not_a_module_are_not_valid() {
    match load(&engine(), b"not wasm", FUEL, MEMORY) {
        Err(Failure::AdapterInvalid { cause, details }) => {
            assert_eq!(cause, CAUSE_NOT_A_MODULE);
            assert_eq!(details.len(), 1);
        }
        Err(other) => panic!("{other:?}"),
        Ok(_) => panic!("the bytes loaded"),
    }
}

#[test]
fn a_module_that_imports_is_not_valid() {
    let mut wasm = Wasm::good();
    wasm.imports = vec![
        [name("env"), name("g"), vec![0x01, 0x70], limits(0, None)].concat(),
        [name("env"), name("h"), vec![0x01, 0x70], limits(0, None)].concat(),
    ];
    assert_load_fails(
        &wasm,
        Err(Failure::AdapterInvalid {
            cause: CAUSE_IMPORTS,
            details: vec!["env.g".to_owned(), "env.h".to_owned()],
        }),
    );
}

#[test]
fn a_module_without_one_of_the_five_exports_is_not_valid() {
    for (index, export) in [
        "sinter_interface",
        "sinter_alloc",
        "sinter_recognise",
        "sinter_bind",
    ]
    .into_iter()
    .enumerate()
    {
        let mut wasm = Wasm::good();
        wasm.functions[index].export = None;
        assert_load_fails(&wasm, invalid_with(CAUSE_MISSING_EXPORT, export));
    }
    let mut wasm = Wasm::good();
    wasm.exports.clear();
    assert_load_fails(&wasm, invalid_with(CAUSE_MISSING_EXPORT, "memory"));
}

#[test]
fn an_export_of_the_wrong_type_is_not_valid() {
    let mut wasm = Wasm::good();
    wasm.functions[ALLOC].params = vec![I64];
    wasm.functions[ALLOC].body = i32_const(8);
    assert_load_fails(&wasm, invalid_with(CAUSE_EXPORT_TYPE, "sinter_alloc"));

    let mut wasm = Wasm::good();
    wasm.functions[RECOGNISE].results = vec![I32];
    wasm.functions[RECOGNISE].body = i32_const(0);
    assert_load_fails(&wasm, invalid_with(CAUSE_EXPORT_TYPE, "sinter_recognise"));

    let mut wasm = Wasm::good();
    wasm.functions[BIND].params = vec![I32; 3];
    wasm.functions[BIND].body = response(16, 1);
    assert_load_fails(&wasm, invalid_with(CAUSE_EXPORT_TYPE, "sinter_bind"));

    let mut wasm = Wasm::good();
    wasm.exports = vec![("mem", 0x02, 0), ("memory", 0x03, 0)];
    assert_load_fails(&wasm, invalid_with(CAUSE_EXPORT_TYPE, "memory"));

    let mut wasm = Wasm::good();
    wasm.exports = vec![("memory", 0x00, 0)];
    assert_load_fails(&wasm, invalid_with(CAUSE_EXPORT_TYPE, "memory"));
}

#[test]
fn other_exports_are_allowed() {
    let mut wasm = Wasm::good();
    wasm.exports.push(("__heap_base", 0x03, 0));
    wasm.functions.push(function("helper", &[], &[], vec![]));
    assert_eq!(load_wasm(&wasm).unwrap().interface, 1);
}

#[test]
fn a_loop_runs_out_of_fuel() {
    let wasm = Wasm::good().body(BIND, vec![0x03, 0x40, 0x0c, 0, 0x0b, 0x00]);
    assert_eq!(bind(&wasm, b"r"), Err(Failure::AdapterOutOfFuel));
}

#[test]
fn a_loop_in_the_interface_runs_out_of_fuel_while_the_adapter_loads() {
    let wasm = Wasm::good().body(0, vec![0x03, 0x40, 0x0c, 0, 0x0b, 0x00]);
    assert_load_fails(&wasm, Err(Failure::AdapterOutOfFuel));
}

fn least_fuel(wasm: &Wasm) -> u64 {
    let adapter = load_wasm(wasm).unwrap();
    let succeeds = |fuel| call(&adapter, Function::Recognise, b"q", b"r", fuel, MEMORY).is_ok();
    let (mut low, mut high) = (0, 10_000);
    assert!(succeeds(high));
    while low < high {
        let middle = (low + high) / 2;
        if succeeds(middle) {
            high = middle;
        } else {
            low = middle + 1;
        }
    }
    high
}

#[test]
fn one_limit_of_fuel_covers_both_allocations_and_the_call() {
    let plain = Wasm::good();
    let mut alloc = plain.functions[ALLOC].body.clone();
    for _ in 0..5 {
        alloc.extend(i32_const(0));
        alloc.push(0x1a);
    }
    let costly = plain.clone().body(ALLOC, alloc);
    let least = least_fuel(&plain);
    assert_eq!(least_fuel(&costly), least + 10);
    let adapter = load_wasm(&plain).unwrap();
    assert_eq!(
        call(&adapter, Function::Recognise, b"q", b"r", least - 1, MEMORY),
        Err(Failure::AdapterOutOfFuel)
    );
}

#[test]
fn a_trap_gives_its_message() {
    let wasm = Wasm::good().body(BIND, vec![0x00]);
    match bind(&wasm, b"r") {
        Err(Failure::AdapterTrap(message)) => {
            assert!(message.contains("unreachable"), "{message}")
        }
        other => panic!("{other:?}"),
    }
}

#[test]
fn a_trap_in_the_interface_stops_the_load() {
    let wasm = Wasm::good().body(0, vec![0x00]);
    assert!(matches!(load_wasm(&wasm), Err(Failure::AdapterTrap(_))));
}

#[test]
fn a_growth_past_the_limit_fails_with_the_size_refused() {
    let grow = [i32_const(100), vec![0x40, 0x00, 0x1a], echo_report()].concat();
    let wasm = Wasm::good().body(BIND, grow);
    assert_eq!(
        call_with(&wasm, Function::Bind, b"r", FUEL, 2 * PAGE),
        Err(Failure::AdapterMemoryLimit(101 * PAGE))
    );
    assert_eq!(
        call_with(&wasm, Function::Bind, b"r", FUEL, 101 * PAGE).unwrap(),
        b"r"
    );
}

#[test]
fn a_memory_that_starts_above_the_limit_fails_when_the_adapter_loads() {
    let mut wasm = Wasm::good();
    wasm.memories = vec![(2, None)];
    match load(&engine(), &wasm.bytes(), FUEL, PAGE) {
        Err(failure) => assert_eq!(failure, Failure::AdapterMemoryLimit(2 * PAGE)),
        Ok(_) => panic!("the module loaded"),
    }
}

#[test]
fn the_limit_bounds_all_memories_together() {
    let mut wasm = Wasm::good();
    wasm.memories = vec![(1, None), (1, None)];
    match load(&engine(), &wasm.bytes(), FUEL, PAGE) {
        Err(failure) => assert_eq!(failure, Failure::AdapterMemoryLimit(2 * PAGE)),
        Ok(_) => panic!("the module loaded"),
    }
    assert_eq!(
        load(&engine(), &wasm.bytes(), FUEL, 2 * PAGE)
            .unwrap()
            .interface,
        1
    );
}

#[test]
fn a_growth_past_the_declared_maximum_fails_in_the_module_and_not_in_the_call() {
    let mut wasm = Wasm::good();
    wasm.memories = vec![(1, Some(1))];
    let grow = [i32_const(1), vec![0x40, 0x00, 0x1a], echo_report()].concat();
    assert_eq!(bind(&wasm.body(BIND, grow), b"r").unwrap(), b"r");
}

#[test]
fn an_allocation_at_address_0_fails() {
    let wasm = Wasm::good().body(ALLOC, i32_const(0));
    assert_eq!(
        bind(&wasm, b"r"),
        Err(Failure::AdapterAlloc {
            call: CALL_REQUEST,
            address: 0,
            length: 15,
            memory_size: PAGE,
        })
    );
}

#[test]
fn an_allocation_outside_memory_fails() {
    let wasm = Wasm::with_next(PAGE as i32 - 15);
    assert_eq!(
        bind(&wasm, b"rr"),
        Err(Failure::AdapterAlloc {
            call: CALL_REPORT,
            address: PAGE as u32,
            length: 2,
            memory_size: PAGE,
        })
    );
    let wasm = Wasm::good().body(ALLOC, i32_const(-16));
    assert_eq!(
        bind(&wasm, b"r"),
        Err(Failure::AdapterAlloc {
            call: CALL_REQUEST,
            address: (-16i32) as u32,
            length: 15,
            memory_size: PAGE,
        })
    );
}

#[test]
fn an_allocation_that_ends_at_the_end_of_memory_succeeds() {
    let wasm = Wasm::with_next(PAGE as i32 - 15);
    assert_eq!(bind(&wasm, b"").unwrap(), b"");
}

#[test]
fn a_response_outside_memory_fails() {
    let at = |address, length| Wasm::good().body(RECOGNISE, response(address, length));
    assert_eq!(
        recognise(&at(PAGE as u32 - 10, 11)),
        Err(Failure::AdapterResponse {
            address: PAGE as u32 - 10,
            length: 11,
            memory_size: PAGE,
        })
    );
    assert_eq!(
        recognise(&at(0xffff_0000, 0x8000_0000)),
        Err(Failure::AdapterResponse {
            address: 0xffff_0000,
            length: 0x8000_0000,
            memory_size: PAGE,
        })
    );
    assert_eq!(recognise(&at(PAGE as u32 - 1, 1)).unwrap(), vec![0]);
}

#[test]
fn a_table_at_the_bound_loads_and_a_larger_one_does_not() {
    let mut wasm = Wasm::good();
    wasm.tables = vec![TABLE_ELEMENTS_MAX as u32];
    assert_eq!(load_wasm(&wasm).unwrap().interface, 1);
    wasm.tables = vec![
        TABLE_ELEMENTS_MAX as u32 / 2,
        TABLE_ELEMENTS_MAX as u32 / 2 + 1,
    ];
    assert!(matches!(load_wasm(&wasm), Err(Failure::AdapterTrap(_))));
}

#[test]
fn a_table_growth_past_the_bound_fails_in_the_module_and_not_in_the_call() {
    let mut wasm = Wasm::good();
    wasm.tables = vec![0];
    let grow = [
        vec![0xd0, 0x70],
        i32_const(TABLE_ELEMENTS_MAX as i32 + 1),
        vec![0xfc, 15, 0, 0x1a],
        echo_report(),
    ]
    .concat();
    assert_eq!(bind(&wasm.body(BIND, grow), b"r").unwrap(), b"r");
}

#[test]
fn a_function_has_a_number_in_the_c_interface() {
    assert_eq!(Function::of_number(0), Some(Function::Recognise));
    assert_eq!(Function::of_number(1), Some(Function::Bind));
    assert_eq!(Function::of_number(2), None);
}
