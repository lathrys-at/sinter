/* SPDX-License-Identifier: Apache-2.0 */
/* Copyright 2026 The Sinter Authors */

/* The stubs hold the OCaml runtime lock for the whole call, so a long
   parse blocks every other thread of the process. */

#include <string.h>

#include <caml/alloc.h>
#include <caml/callback.h>
#include <caml/custom.h>
#include <caml/fail.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>

#include "sinter_bridge.h"

static void raise_bridge_error(const char *message) {
  const value *exception = caml_named_value("Sinter_bridge.Error");
  if (exception == NULL) {
    caml_failwith(message);
  }
  caml_raise_with_string(*exception, message);
}

/* Raise Sinter_bridge.Failed with the buffer of the last failure.
   Without that exception, or without the buffer, raise
   Sinter_bridge.Error with the fallback message. */
static void raise_failure(const char *fallback) {
  CAMLparam0();
  CAMLlocal1(buffer);
  const value *failed = caml_named_value("Sinter_bridge.Failed");
  sinter_bridge_result *failure = sinter_bridge_last_failure();
  if (failed == NULL || failure == NULL) {
    sinter_bridge_result_free(failure);
    raise_bridge_error(fallback);
  }
  buffer =
      caml_alloc_initialized_string(failure->len, (const char *)failure->data);
  sinter_bridge_result_free(failure);
  caml_raise_with_arg(*failed, buffer);
  CAMLnoreturn;
}

/* Copy a result into an OCaml string and free it. A NULL result
   raises the last failure. No OCaml value points into memory that the
   bridge owns. */
static value take_result(sinter_bridge_result *result, const char *fallback) {
  CAMLparam0();
  CAMLlocal1(copy);
  if (result == NULL) {
    raise_failure(fallback);
  }
  copy = caml_alloc_initialized_string(result->len, (const char *)result->data);
  sinter_bridge_result_free(result);
  CAMLreturn(copy);
}

/* A custom block holds one pointer to a handle of the bridge. The
   pointer is NULL once the handle is freed. Nothing frees a handle
   twice, and a later call raises Invalid_argument. A finalizer only
   frees the handle: it allocates nothing on the OCaml heap, raises
   nothing, and calls no OCaml code. */

#define Handle_val(v) (*((void **)Data_custom_val(v)))

static void *live_handle(value v, const char *closed) {
  void *handle = Handle_val(v);
  if (handle == NULL) {
    caml_invalid_argument(closed);
  }
  return handle;
}

static value alloc_handle(struct custom_operations *operations, void *handle,
                          mlsize_t memory) {
  value block = caml_alloc_custom_mem(operations, sizeof(void *), memory);
  Handle_val(block) = handle;
  return block;
}

#define HANDLE_OPERATIONS(kind, free_function)                                 \
  static void finalize_##kind(value v) {                                       \
    void *handle = Handle_val(v);                                              \
    Handle_val(v) = NULL;                                                      \
    free_function(handle);                                                     \
  }                                                                            \
  static struct custom_operations kind##_operations = {                        \
      "sinter.bridge." #kind,     finalize_##kind,                             \
      custom_compare_default,     custom_hash_default,                         \
      custom_serialize_default,   custom_deserialize_default,                  \
      custom_compare_ext_default, custom_fixed_length_default};                \
  CAMLprim value sinter_bridge_##kind##_free_stub(value v) {                   \
    CAMLparam1(v);                                                             \
    finalize_##kind(v);                                                        \
    CAMLreturn(Val_unit);                                                      \
  }

HANDLE_OPERATIONS(engine, sinter_bridge_engine_free)
HANDLE_OPERATIONS(language, sinter_bridge_language_free)
HANDLE_OPERATIONS(tree, sinter_bridge_tree_free)
HANDLE_OPERATIONS(query, sinter_bridge_query_free)
HANDLE_OPERATIONS(adapter, sinter_bridge_adapter_free)

#define Engine_val(v)                                                          \
  ((sinter_bridge_engine *)live_handle(v, "Sinter_bridge: the engine is closed"))
#define Language_val(v)                                                        \
  ((sinter_bridge_language *)live_handle(                                      \
      v, "Sinter_bridge: the language is closed"))
#define Tree_val(v)                                                            \
  ((sinter_bridge_tree *)live_handle(v, "Sinter_bridge: the tree is closed"))
#define Query_val(v)                                                           \
  ((sinter_bridge_query *)live_handle(v, "Sinter_bridge: the query is closed"))
#define Adapter_val(v)                                                         \
  ((sinter_bridge_adapter *)live_handle(                                       \
      v, "Sinter_bridge: the adapter is closed"))

/* The OCaml side passes limits of 0 or more. */
static sinter_bridge_limits limits_of(value fuel, value memory) {
  sinter_bridge_limits limits;
  limits.fuel = (uint64_t)Long_val(fuel);
  limits.memory = (uint64_t)Long_val(memory);
  return limits;
}

CAMLprim value sinter_bridge_engine_new_stub(value unit) {
  CAMLparam1(unit);
  sinter_bridge_engine *engine = sinter_bridge_engine_new();
  if (engine == NULL) {
    raise_failure("the bridge could not create an engine");
  }
  /* The last argument is the memory outside the OCaml heap that an
     engine holds. */
  CAMLreturn(alloc_handle(&engine_operations, engine, 4 << 20));
}

CAMLprim value sinter_bridge_language_load_stub(value engine, value name,
                                                value wasm) {
  CAMLparam3(engine, name, wasm);
  sinter_bridge_engine *pointer = Engine_val(engine);
  /* String_val gives a whole C string here. The OCaml side rejects a
     name that holds a NUL byte. */
  sinter_bridge_language *language = sinter_bridge_language_load(
      pointer, String_val(name), (const uint8_t *)String_val(wasm),
      caml_string_length(wasm));
  if (language == NULL) {
    raise_failure("the bridge could not load the grammar");
  }
  CAMLreturn(
      alloc_handle(&language_operations, language, caml_string_length(wasm)));
}

CAMLprim value sinter_bridge_parse_stub(value engine, value language,
                                        value source) {
  CAMLparam3(engine, language, source);
  /* C leaves the order of the arguments of a call open, so each check
     of a closed handle runs on its own line. */
  sinter_bridge_engine *engine_pointer = Engine_val(engine);
  sinter_bridge_language *language_pointer = Language_val(language);
  sinter_bridge_tree *tree =
      sinter_bridge_parse(engine_pointer, language_pointer,
                          (const uint8_t *)String_val(source),
                          caml_string_length(source));
  if (tree == NULL) {
    raise_failure("the bridge could not parse the source text");
  }
  CAMLreturn(
      alloc_handle(&tree_operations, tree, sinter_bridge_tree_memory(tree)));
}

CAMLprim value sinter_bridge_tree_sexp_stub(value tree) {
  CAMLparam1(tree);
  CAMLreturn(take_result(sinter_bridge_tree_sexp(Tree_val(tree)),
                         "the bridge could not write the parse tree"));
}

CAMLprim value sinter_bridge_tree_errors_stub(value tree) {
  CAMLparam1(tree);
  CAMLreturn(take_result(sinter_bridge_tree_errors(Tree_val(tree)),
                         "the bridge could not report the errors of a tree"));
}

CAMLprim value sinter_bridge_query_new_stub(value language, value text) {
  CAMLparam2(language, text);
  sinter_bridge_query *query = sinter_bridge_query_new(
      Language_val(language), (const uint8_t *)String_val(text),
      caml_string_length(text));
  if (query == NULL) {
    raise_failure("the bridge could not compile the query");
  }
  CAMLreturn(alloc_handle(&query_operations, query, caml_string_length(text)));
}

CAMLprim value sinter_bridge_query_run_stub(value query, value tree) {
  CAMLparam2(query, tree);
  sinter_bridge_query *query_pointer = Query_val(query);
  sinter_bridge_tree *tree_pointer = Tree_val(tree);
  CAMLreturn(take_result(sinter_bridge_query_run(query_pointer, tree_pointer),
                         "the bridge could not run the query"));
}

CAMLprim value sinter_bridge_adapter_load_stub(value engine, value wasm,
                                               value fuel, value memory) {
  CAMLparam4(engine, wasm, fuel, memory);
  sinter_bridge_adapter *adapter = sinter_bridge_adapter_load(
      Engine_val(engine), (const uint8_t *)String_val(wasm),
      caml_string_length(wasm), limits_of(fuel, memory));
  if (adapter == NULL) {
    raise_failure("the bridge could not load the adapter");
  }
  CAMLreturn(
      alloc_handle(&adapter_operations, adapter, caml_string_length(wasm)));
}

CAMLprim value sinter_bridge_adapter_interface_stub(value adapter) {
  CAMLparam1(adapter);
  CAMLreturn(Val_long(sinter_bridge_adapter_interface(Adapter_val(adapter))));
}

CAMLprim value sinter_bridge_adapter_call_stub(value adapter, value function,
                                               value request, value report,
                                               value fuel, value memory) {
  CAMLparam5(adapter, function, request, report, fuel);
  CAMLxparam1(memory);
  sinter_bridge_result *response = sinter_bridge_adapter_call(
      Adapter_val(adapter), (uint32_t)Long_val(function),
      (const uint8_t *)String_val(request), caml_string_length(request),
      (const uint8_t *)String_val(report), caml_string_length(report),
      limits_of(fuel, memory));
  CAMLreturn(take_result(response, "the bridge could not call the adapter"));
}

/* The bytecode form of a stub of more than five arguments. */
CAMLprim value sinter_bridge_adapter_call_byte(value *argv, int argn) {
  (void)argn;
  return sinter_bridge_adapter_call_stub(argv[0], argv[1], argv[2], argv[3],
                                         argv[4], argv[5]);
}

CAMLprim value sinter_bridge_sha256_stub(value data) {
  CAMLparam1(data);
  CAMLreturn(take_result(sinter_bridge_sha256((const uint8_t *)String_val(data),
                                              caml_string_length(data)),
                         "the bridge could not compute the digest"));
}

CAMLprim value sinter_bridge_toml_parse_stub(value text) {
  CAMLparam1(text);
  CAMLreturn(
      take_result(sinter_bridge_toml_parse((const uint8_t *)String_val(text),
                                           caml_string_length(text)),
                  "the bridge could not read the TOML text"));
}
