/* SPDX-License-Identifier: Apache-2.0 */
/* Copyright 2026 The Sinter Authors */

/* The C stubs over the parser bridge. Each stub is a thin wrapper: it
   converts the arguments, calls one function of the bridge, and
   converts the result. The stubs decode no record. The OCaml module
   Sinter_bridge decodes the result buffer.

   No function of the bridge allocates on the OCaml heap, and none of
   them calls back into OCaml. The stubs therefore hold the OCaml
   runtime lock for the whole call. A long parse blocks the other
   OCaml threads of the process. */

#include <string.h>

#include <caml/alloc.h>
#include <caml/callback.h>
#include <caml/custom.h>
#include <caml/fail.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>

#include "sinter_bridge.h"

/* Raise Sinter_bridge.Error with the message of the last
   failure. */
static void raise_bridge_error(const char *fallback) {
  const char *message = sinter_bridge_last_error();
  const value *exception = caml_named_value("Sinter_bridge.Error");
  if (message == NULL || message[0] == '\0') {
    message = fallback;
  }
  if (exception == NULL) {
    caml_failwith(message);
  }
  caml_raise_with_string(*exception, message);
}

/* An engine. The pointer is NULL after sinter_bridge_engine_free_stub
   ran, so that the finalizer does not free the engine a second time
   and so that a later call reports a clear failure. */

#define Engine_val(v) (*((sinter_bridge_engine **)Data_custom_val(v)))

static void finalize_engine(value v) {
  sinter_bridge_engine *engine = Engine_val(v);
  Engine_val(v) = NULL;
  sinter_bridge_engine_free(engine);
}

static struct custom_operations engine_operations = {
    "sinter.bridge.engine",     finalize_engine,
    custom_compare_default,     custom_hash_default,
    custom_serialize_default,   custom_deserialize_default,
    custom_compare_ext_default, custom_fixed_length_default};

static sinter_bridge_engine *live_engine(value v) {
  sinter_bridge_engine *engine = Engine_val(v);
  if (engine == NULL) {
    caml_invalid_argument("Sinter_bridge: the engine is closed");
  }
  return engine;
}

/* A language handle. The engine owns the language, so the handle has
   no finalizer. The OCaml side keeps the engine alive for as long as
   any handle from that engine is alive. */

#define Language_val(v) (*((sinter_bridge_language **)Data_custom_val(v)))

static struct custom_operations language_operations = {
    "sinter.bridge.language",   custom_finalize_default,
    custom_compare_default,     custom_hash_default,
    custom_serialize_default,   custom_deserialize_default,
    custom_compare_ext_default, custom_fixed_length_default};

CAMLprim value sinter_bridge_engine_new_stub(value unit) {
  CAMLparam1(unit);
  CAMLlocal1(result);
  sinter_bridge_engine *engine = sinter_bridge_engine_new();
  if (engine == NULL) {
    raise_bridge_error("the bridge could not create an engine");
  }
  /* An engine holds the WebAssembly runtime, so it is expensive in
     memory that the OCaml heap does not see. Tell the garbage
     collector how much, so that it frees an unused engine promptly.
     The number is an estimate, not a measurement. */
  result = caml_alloc_custom_mem(&engine_operations,
                                 sizeof(sinter_bridge_engine *), 4 << 20);
  Engine_val(result) = engine;
  CAMLreturn(result);
}

CAMLprim value sinter_bridge_engine_free_stub(value engine) {
  CAMLparam1(engine);
  sinter_bridge_engine *pointer = Engine_val(engine);
  Engine_val(engine) = NULL;
  sinter_bridge_engine_free(pointer);
  CAMLreturn(Val_unit);
}

CAMLprim value sinter_bridge_language_load_stub(value engine, value name,
                                                value wasm) {
  CAMLparam3(engine, name, wasm);
  CAMLlocal1(result);
  sinter_bridge_engine *pointer = live_engine(engine);
  /* An OCaml string is NUL-terminated in memory. The OCaml side
     rejects a name that holds a NUL byte of its own, so String_val
     gives a whole C string here. */
  sinter_bridge_language *language = sinter_bridge_language_load(
      pointer, String_val(name), (const uint8_t *)String_val(wasm),
      caml_string_length(wasm));
  if (language == NULL) {
    raise_bridge_error("the bridge could not load the grammar");
  }
  result = caml_alloc_custom(&language_operations,
                             sizeof(sinter_bridge_language *), 0, 1);
  Language_val(result) = language;
  CAMLreturn(result);
}

CAMLprim value sinter_bridge_run_stub(value engine, value language,
                                      value source, value query) {
  CAMLparam4(engine, language, source, query);
  CAMLlocal1(result);
  sinter_bridge_engine *pointer = live_engine(engine);
  sinter_bridge_result *run = sinter_bridge_run(
      pointer, Language_val(language), (const uint8_t *)String_val(source),
      caml_string_length(source), (const uint8_t *)String_val(query),
      caml_string_length(query));
  if (run == NULL) {
    raise_bridge_error("the bridge could not parse the source text");
  }
  /* Copy the buffer into an OCaml string and free the result at once.
     No OCaml value then points into memory that the bridge owns. */
  result = caml_alloc_initialized_string(run->len, (const char *)run->data);
  sinter_bridge_result_free(run);
  CAMLreturn(result);
}
