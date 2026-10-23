/* SPDX-License-Identifier: Apache-2.0 */
/* Copyright 2026 The Sinter Authors */

/* @cites parser-bridge */

/* The C interface of the Sinter parser bridge.

   The bridge loads a tree-sitter grammar that is compiled to
   WebAssembly, parses a source text with that grammar, and runs a
   tree-sitter query over the parse tree. It also computes the SHA-256
   digest of a byte string, and reads a TOML document.

   Every function that can fail returns NULL. Call
   sinter_bridge_last_failure for the reason.

   A handle is an engine, a language, a tree, or a query. Each handle
   owns what it needs, so the handles can be freed in any order: a
   language, a tree, and a query stay valid after the engine is freed,
   and a tree and a query stay valid after their language is freed.
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

   The encoding holds every offset in 32 bits, so a source of 2^32
   bytes or more fails before the bridge reads it. The call also fails
   when the parser gives no tree. The caller owns the returned handle
   and frees it with sinter_bridge_tree_free. */
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

/* Parse a source text and run a query over the parse tree.

   "language" must come from "engine". "source" points to "source_len"
   bytes of source text. "query" points to "query_len" bytes of
   tree-sitter query source, in the syntax of a .scm file; it needs no
   terminating NUL byte. When "query_len" is 0, the bridge runs no
   query, and the output holds the parse tree as an S-expression
   instead of the captures.

   The encoding holds every offset and every length in 32 bits. A
   source of 2^32 bytes or more fails with a message before the bridge
   reads it, and so does a parse tree whose text is that long.

   The result holds the captures, or the parse tree, in the encoding
   that README.md beside this crate defines. It is valid until
   sinter_bridge_result_free frees it. */
sinter_bridge_result *sinter_bridge_run(sinter_bridge_engine *engine,
                                        sinter_bridge_language *language,
                                        const uint8_t *source,
                                        size_t source_len, const uint8_t *query,
                                        size_t query_len);

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
   more: the encoding holds every offset in 32 bits. */
sinter_bridge_result *sinter_bridge_toml_parse(const uint8_t *text,
                                               size_t len);

/* Free a result and the bytes it points to. A NULL pointer is allowed
   and does nothing. */
void sinter_bridge_result_free(sinter_bridge_result *result);

/* The message of the last failure on the calling thread, as a
   NUL-terminated UTF-8 string. The string is empty when no call has
   failed on this thread. It is valid until the next call that fails
   on this thread. */
const char *sinter_bridge_last_error(void);

/* The last failure on the calling thread, in the encoding that
   README.md beside this crate defines. The caller frees the result
   with sinter_bridge_result_free. The call returns NULL only when the
   bridge stops on an internal fault. */
sinter_bridge_result *sinter_bridge_last_failure(void);

#ifdef __cplusplus
}
#endif

#endif /* SINTER_BRIDGE_H */
