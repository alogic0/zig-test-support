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

All maintained code and tests are Zig. A few provider regression children invoke
standard Linux utilities to verify actual process-group behavior. No browser,
database, broker, application checkout or Python interpreter is required.
