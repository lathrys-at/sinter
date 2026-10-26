/* SPDX-License-Identifier: Apache-2.0 */
/* Copyright 2026 The Sinter Authors */

/* @cites rust-bridge */

/* The C interface of the Sinter parser bridge.

   The bridge loads a tree-sitter grammar that is compiled to
   WebAssembly, parses a source text with that grammar, and runs a
   tree-sitter query over the parse tree. It calls a function of a
   runner adapter, a WebAssembly module, with bytes in and bytes out,
   under limits of fuel and memory. It also computes the SHA-256 digest
   of a byte string, and reads a TOML document.

   Every function that can fail returns NULL. Call
   sinter_bridge_last_failure for the reason.

   A handle is an engine, a language, a tree, a query, or an adapter.
   Each handle owns what it needs, so the handles can be freed in any
   order: a language, a tree, a query, and an adapter stay valid after
   the engine is freed, and a tree and a query stay valid after their
   language is freed.
   One thread at a time may use one handle. */

#ifndef SINTER_BRIDGE_H
#define SINTER_BRIDGE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* An engine holds the WebAssembly runtime for grammars and a parser. */
typedef struct sinter_bridge_engine sinter_bridge_engine;

/* A grammar. */
typedef struct sinter_bridge_language sinter_bridge_language;

/* A parse tree, with a copy of the source text it was parsed from. */
typedef struct sinter_bridge_tree sinter_bridge_tree;

/* A compiled query. */
typedef struct sinter_bridge_query sinter_bridge_query;

/* A runner adapter: a compiled WebAssembly module that passed the
   checks of its interface. */
typedef struct sinter_bridge_adapter sinter_bridge_adapter;

/* The limits of one instance of an adapter. */
typedef struct sinter_bridge_limits {
  /* The units of fuel for everything that the instance runs. Most
     WebAssembly instructions cost one unit. */
  uint64_t fuel;
  /* The most bytes that all linear memories of the instance may hold
     together. */
  uint64_t memory;
} sinter_bridge_limits;

/* The result of one call. "data" points to "len" bytes. Write to no
   field: sinter_bridge_result_free reads all three. */
typedef struct sinter_bridge_result {
  const uint8_t *data;
  size_t len;
  size_t capacity;
} sinter_bridge_result;

/* Create an engine. Free it with sinter_bridge_engine_free. */
sinter_bridge_engine *sinter_bridge_engine_new(void);

/* Free an engine. A NULL pointer is allowed and does nothing. */
void sinter_bridge_engine_free(sinter_bridge_engine *engine);

/* Load a grammar.

   "name" is the grammar name without the "tree_sitter_" prefix, for
   example "json", as a NUL-terminated UTF-8 string. "wasm" points to
   "wasm_len" bytes: the content of a grammar .wasm file. Both must
   stay readable until the call returns.

   The call fails when tree-sitter does not load the grammar, and when
   the ABI version of the grammar is outside 13 to 15. The caller owns
   the returned handle and frees it with sinter_bridge_language_free. */
sinter_bridge_language *sinter_bridge_language_load(
    sinter_bridge_engine *engine, const char *name, const uint8_t *wasm,
    size_t wasm_len);

/* Free a language. A NULL pointer is allowed and does nothing. */
void sinter_bridge_language_free(sinter_bridge_language *language);

/* Parse a source text.

   "language" must come from "engine". "source" points to "source_len"
   bytes; it may be NULL when "source_len" is 0. The bridge parses the
   bytes as they are, and the tree keeps a copy of them.

   A source of 2^32 bytes or more fails before the bridge reads it.
   The call also fails when the parser gives no tree. The caller owns
   the returned handle and frees it with sinter_bridge_tree_free. */
sinter_bridge_tree *sinter_bridge_parse(sinter_bridge_engine *engine,
                                        const sinter_bridge_language *language,
                                        const uint8_t *source,
                                        size_t source_len);

/* Free a tree. A NULL pointer is allowed and does nothing. */
void sinter_bridge_tree_free(sinter_bridge_tree *tree);

/* An estimate, in bytes, of the memory that a tree holds: the length
   of its source and an amount for each node. 0 for a NULL pointer. */
size_t sinter_bridge_tree_memory(const sinter_bridge_tree *tree);

/* The tree as an S-expression, in the encoding that README.md beside
   this crate defines. The S-expression leaves out a MISSING node that
   tree-sitter hides. The call fails when the S-expression is 2^32
   bytes or more. */
sinter_bridge_result *sinter_bridge_tree_sexp(const sinter_bridge_tree *tree);

/* The error report of a tree, in the encoding that README.md beside
   this crate defines: the error flag of the root, each ERROR node and
   each MISSING node that no ERROR node holds, and the first lowest
   error node. */
sinter_bridge_result *sinter_bridge_tree_errors(
    const sinter_bridge_tree *tree);

/* Compile a query.

   "text" points to "len" bytes of tree-sitter query source in UTF-8,
   in the syntax of a .scm file; it needs no terminating NUL byte, and
   it may be NULL when "len" is 0.

   The call fails when tree-sitter does not compile the query, and
   when a pattern uses a predicate that the bridge does not apply or a
   directive such as #set!. The bridge applies the predicates eq?,
   not-eq?, any-eq?, any-not-eq?, match?, not-match?, any-match?,
   any-not-match?, any-of?, and not-any-of?. The caller owns the
   returned handle and frees it with sinter_bridge_query_free. */
sinter_bridge_query *sinter_bridge_query_new(
    const sinter_bridge_language *language, const uint8_t *text,
    size_t len);

/* Free a query. A NULL pointer is allowed and does nothing. */
void sinter_bridge_query_free(sinter_bridge_query *query);

/* Run a query over a tree, and give the captures with their match
   numbers, in the encoding that README.md beside this crate defines.
   The call fails when the query and the tree come from different
   languages. */
sinter_bridge_result *sinter_bridge_query_run(const sinter_bridge_query *query,
                                              const sinter_bridge_tree *tree);

/* Load a runner adapter.

   "wasm" points to "wasm_len" bytes: the content of a .wasm file. The
   bridge compiles the module once. It checks that the module imports
   nothing and exports "memory", a 32-bit memory that is not shared,
   and the functions sinter_interface () -> i32, sinter_alloc (i32) ->
   i32, sinter_recognise (i32, i32, i32, i32) -> i64, and sinter_bind
   (i32, i32, i32, i32) -> i64. Other exports are allowed. It then calls
   sinter_interface in a new instance under "limits".

   The call fails when the module is not valid, and when the instance
   or sinter_interface fails as a call can fail. The caller owns the
   returned handle and frees it with sinter_bridge_adapter_free. */
sinter_bridge_adapter *sinter_bridge_adapter_load(sinter_bridge_engine *engine,
                                                  const uint8_t *wasm,
                                                  size_t wasm_len,
                                                  sinter_bridge_limits limits);

/* The version that sinter_interface gave when the adapter loaded, read
   as unsigned. 0 for a NULL pointer. */
uint32_t sinter_bridge_adapter_interface(const sinter_bridge_adapter *adapter);

/* Free an adapter. A NULL pointer is allowed and does nothing. */
void sinter_bridge_adapter_free(sinter_bridge_adapter *adapter);

/* Call a function of an adapter, and give the bytes of its response,
   in the encoding that README.md beside this crate defines.

   "function" is 0 for sinter_recognise and 1 for sinter_bind.
   "request" points to "request_len" bytes and "report" to "report_len"
   bytes; either may be NULL when its length is 0.

   The bridge makes a new instance of the module for the call. It calls
   sinter_alloc for the length of the request and writes the request
   there, then does the same for the report. It calls the function with
   the address and the length of the request and of the report. The
   high 32 bits of the result are the address of the response, and the
   low 32 bits its length. Every address and every length is unsigned.
   One limit of fuel covers the start of the instance, both calls of
   sinter_alloc, and the function. The tables of the instance hold at
   most 1,048,576 elements together; a growth past that bound fails
   inside the module, as a growth past a declared maximum does.

   The call fails when the module traps, when it runs out of fuel, when
   it asks for more memory than the limit, when sinter_alloc gives 0 or
   a range outside "memory", and when the response lies outside
   "memory". */
sinter_bridge_result *sinter_bridge_adapter_call(
    const sinter_bridge_adapter *adapter, uint32_t function,
    const uint8_t *request, size_t request_len, const uint8_t *report,
    size_t report_len, sinter_bridge_limits limits);

/* Compute the SHA-256 digest of a byte string.

   "data" points to "len" bytes; it may be NULL when "len" is 0. The
   bytes must stay readable until the call returns.

   The result holds the 32 bytes of the digest, in the encoding that
   README.md beside this crate defines. It is valid until
   sinter_bridge_result_free frees it. */
sinter_bridge_result *sinter_bridge_sha256(const uint8_t *data, size_t len);

/* Read a TOML 1.0.0 document.

   "text" points to "len" bytes of UTF-8 text; it may be NULL when
   "len" is 0. The bytes must stay readable until the call returns.

   The result holds the document, or the error that makes the text not
   a TOML document, in the encoding that README.md beside this crate
   defines. It is valid until sinter_bridge_result_free frees it. The
   call fails when the text is not UTF-8, and when it is 2^32 bytes or
   more. */
sinter_bridge_result *sinter_bridge_toml_parse(const uint8_t *text,
                                               size_t len);

/* Free a result and the bytes it points to. A NULL pointer is allowed
   and does nothing. */
void sinter_bridge_result_free(sinter_bridge_result *result);

/* The last failure on the calling thread, in the encoding that
   README.md beside this crate defines. The caller frees the result
   with sinter_bridge_result_free. The call returns NULL only when the
   bridge stops on an internal fault. */
sinter_bridge_result *sinter_bridge_last_failure(void);

#ifdef __cplusplus
}
#endif

#endif
