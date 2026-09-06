/* SPDX-License-Identifier: Apache-2.0 */
/* Copyright 2026 The Sinter Authors */

/* The C interface of the Sinter parser bridge. The bridge loads a
   tree-sitter grammar that is compiled to WebAssembly, parses a source
   text with it, and runs a tree-sitter query over the parse tree. The
   bridge returns the captures of the query, or the parse tree as an
   S-expression, in one flat buffer. bridge/README.md defines the
   layout of that buffer. */

#ifndef SINTER_BRIDGE_H
#define SINTER_BRIDGE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* An engine holds the WebAssembly runtime and every language that was
   loaded into it. */
typedef struct sinter_bridge_engine sinter_bridge_engine;

/* A language handle. The engine owns the language. The handle stays
   valid until the engine is freed. There is no function that frees a
   single language. */
typedef struct sinter_bridge_language sinter_bridge_language;

/* The result of one run. The bridge owns the bytes. Read them before
   you call sinter_bridge_result_free. */
typedef struct sinter_bridge_result {
  const uint8_t *data;
  size_t len;
  size_t capacity; /* the bridge needs this to free the buffer */
} sinter_bridge_result;

/* Create an engine. Returns NULL on failure; call
   sinter_bridge_last_error for the reason. */
sinter_bridge_engine *sinter_bridge_engine_new(void);

/* Free an engine and every language that was loaded into it. A NULL
   pointer is allowed and does nothing. */
void sinter_bridge_engine_free(sinter_bridge_engine *engine);

/* Load a grammar from WebAssembly bytes. "name" is the grammar name
   without the "tree_sitter_" prefix, for example "json"; it must be a
   NUL-terminated string. The bytes are the content of a grammar .wasm
   file. Returns NULL on failure; call sinter_bridge_last_error for the
   reason. */
sinter_bridge_language *sinter_bridge_language_load(
    sinter_bridge_engine *engine, const char *name, const uint8_t *wasm,
    size_t wasm_len);

/* Parse "source" with "language" and run "query" over the parse tree.
   "query" is tree-sitter query source in the S-expression syntax of a
   .scm file; it does not have to be NUL-terminated. When query_len is
   0 the bridge runs no query and returns the parse tree as an
   S-expression instead. The language must come from the same engine.
   Returns NULL on failure; call sinter_bridge_last_error for the
   reason. */
sinter_bridge_result *sinter_bridge_run(sinter_bridge_engine *engine,
                                        sinter_bridge_language *language,
                                        const uint8_t *source,
                                        size_t source_len, const uint8_t *query,
                                        size_t query_len);

/* Free a result. A NULL pointer is allowed and does nothing. */
void sinter_bridge_result_free(sinter_bridge_result *result);

/* The message of the last failure on the calling thread, as a
   NUL-terminated UTF-8 string. Returns an empty string when the thread
   has had no failure. The bridge owns the string. The next call that
   fails on the same thread replaces it. */
const char *sinter_bridge_last_error(void);

#ifdef __cplusplus
}
#endif

#endif /* SINTER_BRIDGE_H */
