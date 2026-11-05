# Reusable validation helpers

Status: library implemented and validated, 2026-11-05. Consumer qualification is
recorded separately in z_llvm's validation evidence.

## Problem and scope

The z_llvm Python-to-Zig migration duplicated atomic JSON writes, append-safe
command logs, file-backed command reporting, deterministic JSON serialization,
and structural JSON comparison. Add these mechanisms to the existing package.
Evidence layout, compiler acceptance, retention and disk-space rules stay in
consumers. Existing workspace, readiness, capture and diagnostic APIs remain.

## Implementation

1. Adopt the completed zig-process readiness-wait revision as an external
   dependency pinned to a GitHub commit and package hash in `build.zig.zon`.
2. Add an atomic file writer with exclusive random temporary files in the target
   directory, cleanup on failure, explicit replacement behavior, and rename only
   after a complete write. State its visibility and durability guarantees.
   Compose atomic JSON writing from it.
3. Add explicit creation of append-safe log files and command reports that write
   stdout/stderr to caller-owned files. Reuse zig-process for deadlines, process
   groups and reaping; preserve primary and cleanup failures separately. Files
   remain borrowed, and output is never accumulated in a capture buffer.
   Keep the implementation usable by standalone source consumers.
4. Separate ordinary string extraction from nonempty-string validation, preserving
   the old entry points for compatibility. Add deterministic sorted-key JSON
   serialization and structural comparison with documented number semantics,
   array ordering and allocation ownership. Do not claim an external canonical
   JSON standard. Provide a bounded-memory file hash helper if needed by adoption.
5. Add focused native tests for failures and ownership, concurrent atomic writes,
   append-safe positional writers, binary file output, deadlines, cancellation,
   JSON ordering and number cases, and allocator cleanup. Update package version,
   examples and documentation. Adopt the APIs in z_llvm with exact source digests.

## Validation and completion

Run formatting, provider tests and examples in Debug and ReleaseSafe, plus an
isolated source-directory package consumer. Run z_llvm's provider-source checks
and validation policy tests in both modes, and focused standalone CLI smoke and
data parity checks. The compiler and Fibonacci pipeline are outside this slice;
do not restart the long full compiler qualification solely for helper changes.
Run `git diff --check`, review the changes, and commit valid slices separately.

## Results

- Implemented as version 0.2.0. `command.File.run` also supports a standalone
  `file_command.WithProcess` source binding. Existing string helpers retain their
  nonempty semantics; `text`/`textField` accept empty strings.
- Pin zig-process 0.6.1 at `e9fcfccecc84f44a362b12de1bee78258b1e811f`
  with its package hash in `build.zig.zon`. CI's isolated consumer copies this
  package's sources and fetches its dependencies from GitHub.
- Debug and ReleaseSafe: all 25 native tests and the extended example pass.
  The tests cover atomic write/cancellation/publication failures, concurrent
  replacement, binary and positional logs, output larger than allocator capacity,
  live token/std.Io cancellation, timeout cleanup, independent children, separate
  primary/cleanup failures, JSON number semantics, and allocation-failure cleanup.
- Isolated source-directory package consumption passes in both profiles using a
  private global cache, copied package sources and the fetched dependency. Temporary
  consumer directories and caches were removed afterward.
- A minimal independent reproducer confirmed an installed Zig 0.17.0 async-result
  alignment issue for structs containing i128. File reports use u64 nanoseconds
  and pass real asynchronous cancellation/await tests. The toolchain is unchanged.
- z_llvm adopts these helpers, removes its indefinite benchmark wait, and records
  a new measurement-engine identity. Downstream policy tests and CLI replay/smoke
  evidence are kept in that repository; provider tests do not imply compiler or
  Fibonacci qualification.
- Formatting, package hash verification and `git diff --check` pass.
