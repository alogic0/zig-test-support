# Ownership and limits

The package composes zig-process instead of implementing process signaling,
reaping, capture bounds or group termination. It installs no signal handlers,
changes no subreaper policy and never signals a /proc observation. The process
dependency is fetched from GitHub at the immutable revision and package hash in
`build.zig.zon` and retains its original MIT license.

Command reports are owned values; deinitialize exactly once with their allocator.
An asynchronous Command owns the result box until it has joined. Readiness races
cancel/join the reading task before freeing any concurrently completed line.
Child polling retains process identity; the caller still owns stop/deinit. A
readiness line or file is an observation, not proof the child remains alive later.

Optional stdin uses a private pipe with a nonblocking parent writer, feeding in
parallel with zig-process capture. The feed closes its writing end and is joined
before the pipe's read end is released. Command outcome remains primary; input
I/O errors are retained as secondary diagnostics. Cancellation used solely to
join the feed is not itself a cleanup failure. Options, argv, environment and
stdin bytes are borrowed through completion. Runtime errors and allocation
failures never transfer a half-initialized owner.

File-backed commands compose the same process owner without capture buffers.
One deadline covers launch and execution, with the launch-specific timeout also
respected. Reports preserve supervision phase and primary/cleanup errors, then
final deinit runs before elapsed time is recorded. File creation and flags stay
with callers; `files.createLog` explicitly creates a new append-safe Linux file.
Pipes are rejected to prevent an undrained pipe from deadlocking this API. A
generic process-module binding preserves standalone source consumption.

File reports store elapsed nanoseconds in u64, sufficient for more than 500 years
and well beyond the u32-millisecond command deadline. This also avoids a confirmed
Zig 0.17.0 Threaded Future storage issue with over-aligned results: a minimal
async function returning a struct containing i128 reproduced invalid-free/corrupt
metadata independently of this library. The delivered report has ordinary
alignment and is exercised through both await and cancel. The installed toolchain
was not modified.

Workspace path storage belongs to its allocator. Close is idempotent; a failed
filesystem cleanup leaves the owner/path valid for retry. Retention on failure
releases path memory but deliberately leaves the directory. Consumers may copy
the path before close when recording retained evidence. Cleanup never walks a
caller-selected unrelated tree. Symlinks inside a workspace are removed as links.

File reads stream under an explicit limit, including virtual files whose stat
size is zero. JSON parsed owners retain copied strings until deinit; projections
borrow the parsed value. PNG dimensions allocate nothing. Linux resource helpers
reject invalid PIDs, preserve I/O errors and distinguish unavailable data from
zero. They provide measurements, not identity guarantees or lifecycle policy.

Atomic file writes wrap std.Io.File.Atomic. Named temporary files are random and
exclusive in the destination directory; nonreplacing creation may use an unnamed
file. Replacement is explicit and occurs only after all bytes are written.
Uncancelable deinit attempts cleanup on every exit; inability to unlink remains
best effort. Atomic visibility does not promise power-loss durability, preserve
old inode metadata, or create parent directories. Filesystem symlink/path policy
remains with the caller. JSON writing retains the indented text/newline format.

JSON text extraction is distinct from nonempty validation; old aliases keep their
behavior. Structural equality compares number tags and exact integer/number-string
values without floating-point coercion. Float equality follows ==. Sorted-key
serialization preserves array order and number spelling, rejects nonfinite floats,
and uses a temporary arena that is released before returning caller-owned bytes.
It is deterministic serialization rather than a standards-level canonicalization.

All maintained code and tests are Zig. A few provider regression children invoke
standard Linux utilities to verify actual process-group behavior. No browser,
database, broker, application checkout or Python interpreter is required.
