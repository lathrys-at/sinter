/* SPDX-License-Identifier: Apache-2.0 */
/* Copyright 2026 The Sinter Authors */

/* @cites parser-bridge */

/* The C interface of the Sinter parser bridge.

   The bridge loads a tree-sitter grammar that is compiled to
   WebAssembly, parses a source text with that grammar, and runs a
   tree-sitter query over the parse tree.

   Every function that can fail returns NULL. Call
   sinter_bridge_last_error for the reason.

   One thread at a time may use one engine. */

#ifndef SINTER_BRIDGE_H
#define SINTER_BRIDGE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* An engine holds the WebAssembly runtime. It owns every language
   that is loaded into it. */
typedef struct sinter_bridge_engine sinter_bridge_engine;

/* A grammar that is loaded into an engine. */
typedef struct sinter_bridge_language sinter_bridge_language;

/* The result of one run. "data" points to "len" bytes. Write to no
   field: sinter_bridge_result_free reads all three. */
typedef struct sinter_bridge_result {
  const uint8_t *data;
  size_t len;
  size_t capacity;
} sinter_bridge_result;

/* Create an engine. Free it with sinter_bridge_engine_free. */
sinter_bridge_engine *sinter_bridge_engine_new(void);

/* Free an engine and every language that is loaded into it. Every
   language handle from this engine becomes invalid. A NULL pointer is
   allowed and does nothing. */
void sinter_bridge_engine_free(sinter_bridge_engine *engine);

/* Load a grammar into an engine.

   "name" is the grammar name without the "tree_sitter_" prefix, for
   example "json", as a NUL-terminated string. "wasm" points to
   "wasm_len" bytes: the content of a grammar .wasm file. Both must
   stay readable until the call returns.

   The engine owns the returned handle. The handle is valid until
   sinter_bridge_engine_free frees the engine. */
sinter_bridge_language *sinter_bridge_language_load(
    sinter_bridge_engine *engine, const char *name, const uint8_t *wasm,
    size_t wasm_len);

/* Parse a source text and run a query over the parse tree.

   "language" must come from "engine". "source" points to "source_len"
   bytes of source text. "query" points to "query_len" bytes of
   tree-sitter query source, in the syntax of a .scm file; it needs no
   terminating NUL byte. When "query_len" is 0, the bridge runs no
   query, and the output holds the parse tree as an S-expression
   instead of the captures.

   The result holds the captures, or the parse tree, in the encoding
   that README.md beside this crate defines. It is valid until
   sinter_bridge_result_free frees it. */
sinter_bridge_result *sinter_bridge_run(sinter_bridge_engine *engine,
                                        sinter_bridge_language *language,
                                        const uint8_t *source,
                                        size_t source_len, const uint8_t *query,
                                        size_t query_len);

/* Free a result and the bytes it points to. A NULL pointer is allowed
   and does nothing. */
void sinter_bridge_result_free(sinter_bridge_result *result);

/* The message of the last failure on the calling thread, as a
   NUL-terminated UTF-8 string. The string is empty when no call has
   failed on this thread. It is valid until the next call that fails
   on this thread. */
const char *sinter_bridge_last_error(void);

#ifdef __cplusplus
}
#endif

#endif /* SINTER_BRIDGE_H */
