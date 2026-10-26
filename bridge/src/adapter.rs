// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 The Sinter Authors

//! Runner adapters: WebAssembly modules that the bridge calls with
//! bytes in and bytes out, each call in a new instance, under a limit
//! of fuel and a limit of memory.

use tree_sitter::wasmtime::{self, Engine, ExternType, Instance, Module, Store, Trap, ValType};

use crate::failure::{
    Failure, CALL_REPORT, CALL_REQUEST, CAUSE_EXPORT_TYPE, CAUSE_IMPORTS, CAUSE_MISSING_EXPORT,
    CAUSE_NOT_A_MODULE,
};

/// The most table elements that the instance of an adapter may hold,
/// in all of its tables together.
pub(crate) const TABLE_ELEMENTS_MAX: usize = 1 << 20;

/// A compiled adapter, and the version of the interface that its
/// `sinter_interface` gave.
pub(crate) struct Adapter {
    pub(crate) module: Module,
    pub(crate) interface: u32,
}

/// The function of an adapter that a call runs.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum Function {
    Recognise,
    Bind,
}

impl Function {
    /// The function for its number in the C interface: 0 for
    /// `recognise`, 1 for `bind`.
    pub(crate) fn of_number(number: u32) -> Option<Function> {
        match number {
            0 => Some(Function::Recognise),
            1 => Some(Function::Bind),
            _ => None,
        }
    }

    fn export(self) -> &'static str {
        match self {
            Function::Recognise => "sinter_recognise",
            Function::Bind => "sinter_bind",
        }
    }
}

struct Limits {
    memory_limit: usize,
    memory_total: usize,
    memory_growth: usize,
    table_total: usize,
    table_growth: usize,
    refused: Option<usize>,
}

impl wasmtime::ResourceLimiter for Limits {
    fn memory_growing(
        &mut self,
        current: usize,
        desired: usize,
        maximum: Option<usize>,
    ) -> wasmtime::Result<bool> {
        if maximum.is_some_and(|maximum| desired > maximum) {
            return Ok(false);
        }
        let growth = desired.saturating_sub(current);
        let total = self.memory_total.saturating_add(growth);
        if total > self.memory_limit {
            self.refused = Some(total);
            return Err(wasmtime::Error::msg(
                "the adapter asked for more memory than its limit",
            ));
        }
        self.memory_total = total;
        self.memory_growth = growth;
        Ok(true)
    }

    fn memory_grow_failed(&mut self, _error: wasmtime::Error) -> wasmtime::Result<()> {
        self.memory_total -= self.memory_growth;
        Ok(())
    }

    fn table_growing(
        &mut self,
        current: usize,
        desired: usize,
        maximum: Option<usize>,
    ) -> wasmtime::Result<bool> {
        if maximum.is_some_and(|maximum| desired > maximum) {
            return Ok(false);
        }
        let growth = desired.saturating_sub(current);
        let total = self.table_total.saturating_add(growth);
        if total > TABLE_ELEMENTS_MAX {
            return Ok(false);
        }
        self.table_total = total;
        self.table_growth = growth;
        Ok(true)
    }

    fn table_grow_failed(&mut self, _error: wasmtime::Error) -> wasmtime::Result<()> {
        self.table_total -= self.table_growth;
        Ok(())
    }
}

fn invalid(cause: u32, details: Vec<String>) -> Failure {
    Failure::AdapterInvalid { cause, details }
}

fn stopped(store: &Store<Limits>, error: wasmtime::Error) -> Failure {
    if let Some(size) = store.data().refused {
        return Failure::AdapterMemoryLimit(size as u64);
    }
    match error.downcast_ref::<Trap>() {
        Some(Trap::OutOfFuel) => Failure::AdapterOutOfFuel,
        Some(trap) => Failure::AdapterTrap(trap.to_string()),
        None => Failure::AdapterTrap(format!("{error:#}")),
    }
}

type Signature = (&'static [ValType], &'static [ValType]);

const FOUR_I32: &[ValType] = &[ValType::I32, ValType::I32, ValType::I32, ValType::I32];

const FUNCTIONS: [(&str, Signature); 4] = [
    ("sinter_interface", (&[], &[ValType::I32])),
    ("sinter_alloc", (&[ValType::I32], &[ValType::I32])),
    ("sinter_recognise", (FOUR_I32, &[ValType::I64])),
    ("sinter_bind", (FOUR_I32, &[ValType::I64])),
];

fn same_types(found: impl ExactSizeIterator<Item = ValType>, wanted: &[ValType]) -> bool {
    found.len() == wanted.len()
        && found
            .zip(wanted)
            .all(|(found, wanted)| ValType::eq(&found, wanted))
}

fn check(module: &Module) -> Result<(), Failure> {
    let imports: Vec<String> = module
        .imports()
        .map(|import| format!("{}.{}", import.module(), import.name()))
        .collect();
    if !imports.is_empty() {
        return Err(invalid(CAUSE_IMPORTS, imports));
    }
    match module.get_export("memory") {
        Some(ExternType::Memory(memory)) if !memory.is_64() && !memory.is_shared() => {}
        Some(_) => return Err(invalid(CAUSE_EXPORT_TYPE, vec!["memory".to_owned()])),
        None => return Err(invalid(CAUSE_MISSING_EXPORT, vec!["memory".to_owned()])),
    }
    for (name, (params, results)) in FUNCTIONS {
        match module.get_export(name) {
            Some(ExternType::Func(function))
                if same_types(function.params(), params)
                    && same_types(function.results(), results) => {}
            Some(_) => return Err(invalid(CAUSE_EXPORT_TYPE, vec![name.to_owned()])),
            None => return Err(invalid(CAUSE_MISSING_EXPORT, vec![name.to_owned()])),
        }
    }
    Ok(())
}

fn start(module: &Module, fuel: u64, memory: u64) -> Result<(Store<Limits>, Instance), Failure> {
    let limits = Limits {
        memory_limit: usize::try_from(memory).unwrap_or(usize::MAX),
        memory_total: 0,
        memory_growth: 0,
        table_total: 0,
        table_growth: 0,
        refused: None,
    };
    let mut store = Store::new(module.engine(), limits);
    store.limiter(|limits| limits);
    store.set_fuel(fuel).map_err(|error| {
        Failure::Internal(format!("cannot set the fuel of an adapter: {error}"))
    })?;
    match Instance::new(&mut store, module, &[]) {
        Ok(instance) => Ok((store, instance)),
        Err(error) => Err(stopped(&store, error)),
    }
}

fn lost(error: wasmtime::Error) -> Failure {
    Failure::Internal(format!("an export of the adapter is gone: {error}"))
}

/// Compile and check an adapter, and read its `sinter_interface` in a
/// new instance under the limits.
pub(crate) fn load(
    engine: &Engine,
    bytes: &[u8],
    fuel: u64,
    memory: u64,
) -> Result<Adapter, Failure> {
    let module = Module::new(engine, bytes)
        .map_err(|error| invalid(CAUSE_NOT_A_MODULE, vec![format!("{error:#}")]))?;
    check(&module)?;
    let (mut store, instance) = start(&module, fuel, memory)?;
    let interface = instance
        .get_typed_func::<(), i32>(&mut store, "sinter_interface")
        .map_err(lost)?;
    let version = match interface.call(&mut store, ()) {
        Ok(version) => version,
        Err(error) => return Err(stopped(&store, error)),
    };
    Ok(Adapter {
        module,
        interface: version as u32,
    })
}

fn place(
    store: &mut Store<Limits>,
    instance: &Instance,
    bytes: &[u8],
    call: u32,
) -> Result<u32, Failure> {
    let alloc = instance
        .get_typed_func::<i32, i32>(&mut *store, "sinter_alloc")
        .map_err(lost)?;
    let memory = instance
        .get_memory(&mut *store, "memory")
        .ok_or_else(|| lost(wasmtime::Error::msg("memory")))?;
    let length = bytes.len() as u32;
    let address = match alloc.call(&mut *store, length as i32) {
        Ok(address) => address as u32,
        Err(error) => return Err(stopped(store, error)),
    };
    let size = memory.data_size(&*store) as u64;
    if address == 0 || u64::from(address) + u64::from(length) > size {
        return Err(Failure::AdapterAlloc {
            call,
            address,
            length,
            memory_size: size,
        });
    }
    let start = address as usize;
    memory.data_mut(&mut *store)[start..start + bytes.len()].copy_from_slice(bytes);
    Ok(address)
}

/// Call `function` of an adapter with the request and the report, in a
/// new instance under the limits, and give the bytes of the response.
pub(crate) fn call(
    adapter: &Adapter,
    function: Function,
    request: &[u8],
    report: &[u8],
    fuel: u64,
    memory: u64,
) -> Result<Vec<u8>, Failure> {
    let request_length = u32::try_from(request.len())
        .map_err(|_| Failure::Internal("the request is 4 GiB or more".to_owned()))?;
    let report_length = u32::try_from(report.len())
        .map_err(|_| Failure::Internal("the report is 4 GiB or more".to_owned()))?;
    let (mut store, instance) = start(&adapter.module, fuel, memory)?;
    let main = instance
        .get_typed_func::<(i32, i32, i32, i32), i64>(&mut store, function.export())
        .map_err(lost)?;
    let request_address = place(&mut store, &instance, request, CALL_REQUEST)?;
    let report_address = place(&mut store, &instance, report, CALL_REPORT)?;
    let arguments = (
        request_address as i32,
        request_length as i32,
        report_address as i32,
        report_length as i32,
    );
    let packed = match main.call(&mut store, arguments) {
        Ok(packed) => packed as u64,
        Err(error) => return Err(stopped(&store, error)),
    };
    let address = (packed >> 32) as u32;
    let length = packed as u32;
    let memory = instance
        .get_memory(&mut store, "memory")
        .ok_or_else(|| lost(wasmtime::Error::msg("memory")))?;
    let size = memory.data_size(&store) as u64;
    if u64::from(address) + u64::from(length) > size {
        return Err(Failure::AdapterResponse {
            address,
            length,
            memory_size: size,
        });
    }
    let start = address as usize;
    Ok(memory.data(&store)[start..start + length as usize].to_vec())
}

#[cfg(test)]
pub(crate) mod tests;
