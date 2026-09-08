<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# Keep a warm parser through a serve loop, first as a child process
@decision serve-mode
@cites parser-bridge
Sinter has a serve loop that answers many requests in one process; its first form is `sinter serve`, a child of its caller over standard input and output, and later adapters put the same loop on a socket, behind the Model Context Protocol, and behind the Language Server Protocol.

## Context

Every call to `sinter` starts the WebAssembly runtime and compiles
the grammar before it does its work. An agent, an editor, and a hook
call the tool in bursts, with the same grammar each time, and each
call in a burst pays that setup again.

Section 9.1 of the design notes lists "no daemon" and "no MCP
server" among the absences of the tool. Its reasons: a stateless tool
has no process to host a server, and a shim over the command line
adds a surface without adding a capability. The roadmap lists a
detached mode on a socket, an adapter for the Model Context Protocol,
and an adapter for the Language Server Protocol. The section and the
roadmap had to be reconciled.

## Decision

- Sinter has one serve loop, in the core library. The loop takes a
  request and gives the lines of the answer. It knows nothing about a
  channel, a socket, or a protocol.
- The first form of the loop is `sinter serve`: a process that reads
  requests from standard input, writes answers to standard output,
  and exits when its input ends. It is a child of its caller. It
  holds no socket, no process id file, and no state on disk.
- The later forms are adapters over the same loop: a detached process
  on a socket, a Model Context Protocol server, and a Language Server
  Protocol server. Each comes as its own plan step with its own
  record.
- A loop that holds a warm runtime and loaded grammars is a
  capability, not only a surface. On that point, section 9.1 of the
  design notes is older than this decision, and this decision wins.
- Every verb that gains an operation in the loop answers the command
  line and the loop from one implementation, with the same lines.

## Alternatives considered

- **No serve loop: every call starts fresh**, the position of section
  9.1 of the design notes — not chosen. A burst of calls pays the
  runtime start and the grammar compile on each call, and the
  measurements in the parser-bridge record show what that costs.
- **A detached process on a socket as the first form** — deferred, by
  the maintainer's ruling in the bootstrap session. It needs lifetime
  rules that a child process does not: a start, a stop, and a rule
  for a stale process. The loop is the same, so the detached form
  loses nothing by coming later.

## Consequences

The request and the answer of `sinter serve` are the shape that a
caller depends on. The help text of the command states them until
`spec/protocol.md` states them as a specification. The interface
files of the core library state what the loop holds and for how long.
