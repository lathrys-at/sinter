<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# Serve mode is a child process that answers JSON lines on standard input
@decision serve-mode
@cites json-handling
@cites exit-codes
@cites parser-bridge
`sinter serve` reads one request per line from standard input, answers each request with the JSONL that the one-shot command would print, and exits when standard input ends.

## Context

A caller that runs `sinter` many times in one turn pays the same
setup every time. Each run starts the WebAssembly runtime, reads the
grammar file, and compiles the grammar again before the first parse.
An agent, an editor, and a hook all call the tool in bursts, and each
call in a burst uses the same grammar as the last.

The design notes rule out two ways to hold that setup between calls.
Section 9.1 lists "no daemon" and "no MCP server" among the absences,
and it gives the reason for each: a stateless tool has no process to
host a server, and a shim over the command line adds a tool surface
without adding a capability.

Sinter still needs a way to answer many requests with one warm
runtime, and the answers must be the same lines that the one-shot
commands print.

## Decision

`sinter serve` is a filter, not a server. It reads standard input line
by line and writes standard output. It handles one request at a time,
in the order the requests come, and it writes the whole answer of one
request before it reads the next. It holds no socket, no pid file, and
no state on disk. It exits with code 0 when standard input reaches
end of file. It is a child of its caller and it dies with the pipe.

**A request is one JSON object on one line.** `yojson` reads it.

| field | type | meaning |
|---|---|---|
| `id` | string or integer | the caller's tag for the request |
| `op` | string | the operation: the name of a command line verb |

The other fields of the object are the arguments of the operation.
Each one is named as the long option of that verb. For `op` of
`parse`, they are `grammar` (a string), `query` (a string, the path of
a query file) or `tree` (a boolean), and `files` (an array of
strings). A field that the operation does not name is an error, as an
unknown option is on the command line.

**A response is every line that the one-shot command would print,
followed by exactly one control line.** Each line is a canonical JSONL
object. Each line carries one added field, `req`, that holds the `id`
of the request, exactly as the request gave it. The field is `req` and
not `id` because every fact line already carries `id`, which is the
identity of the fact itself.

| line | fields |
|---|---|
| a result of `parse` with a query | the fields of the capture, and `req` |
| a result of `parse` with `tree` | `req`, `path`, and the S-expression in `tree` |
| the control line, when the operation ran | `event` of `done`, `code`, and `req` |
| the control line, when the operation did not run | `event` of `error`, `code`, `message`, and `req` |

The `code` of a control line is the exit code that the one-shot
command would have returned: 0 when it succeeded, 2 when the request
is wrong, and 3 when the environment stopped the work. The `message`
of an `error` line is the text that the one-shot command would have
written to standard error after `sinter: `.

A line that the loop cannot read as a request with an `id` gets one
`error` line with code 2 and no `req` field. This covers a line that
is not JSON, a line that is not an object, an object with no `id`, and
an `id` that is neither a string nor an integer. The loop continues
after every error. The loop never ends because of what a line holds.

**The process holds one engine and a cache of grammars.** It starts
the WebAssembly runtime once. It loads a grammar once for each
`grammar` path and uses the loaded grammar again for every later
request that names the same path. It loads the file again when the
size or the modification time of the file differs from the load. It
does not cache a grammar that fails to load.

**The loop knows nothing about a channel.** `Serve` in `sinter.core`
takes one request line and returns the lines of the answer. The
executable connects it to standard input and standard output. A later
adapter — for the Model Context Protocol, or for the Language Server
Protocol — is another caller of the same loop, and it is not part of
this decision.

## Alternatives considered

- **A daemon that listens on a socket** — rejected. A daemon needs a
  lifetime that nobody owns: a start, a stop, a pid file, and a rule
  for a stale process that holds an old index. Serve mode has none of
  these. It has no socket and no name, one caller finds it because
  that caller started it, and it dies when the pipe closes. This is
  the reason section 9.1 of the design notes gives for "no daemon",
  and serve mode does not meet it.
- **A shim that speaks the Model Context Protocol over the command
  line** — rejected, and for the reason section 9.1 gives: a shim that
  starts `sinter` once for each tool call adds a surface and no
  capability. The loop here adds the capability first, a warm runtime
  and loaded grammars, and a protocol adapter over the loop is then
  worth its code. The adapter waits for a later plan step.
- **A process that leaves its caller, under `--detach`** — deferred,
  not rejected. A process that outlives the caller that started it
  needs the lifetime rules that this decision avoids. `--detach` is a
  separate decision, and the loop does not change when it comes.

## Consequences

The tool now has two ways to reach the same work. Each verb that gains
an operation must answer to both, and both must give the same lines.
The one-shot command and the operation therefore share one
implementation, and the difference between them is only how a line is
tagged and written.

A caller reads an outcome from the `code` of a control line, not from
the status of a process. The five exit codes keep their meanings
inside the output.

The request and the response shape above are the shape a caller
depends on. `spec/protocol.md` will state them as a specification, and
a change to them will then be a change to a specification.

Serve mode holds a grammar in memory for the life of the process. A
caller that never ends the process holds that memory. The caller ends
the process by closing the pipe.

`--detach`, `--mcp`, and `--lsp` are not options of `serve`. Each one
is a separate surface over the same loop, and each needs its own
decision.
