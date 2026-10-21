# zig-test-support

Small native acceptance helpers for Zig 0.17.0 on Linux. Application policy and
process-wide signal handling belong to callers. The HTTP fixture library is an
independent package; this library does not depend on it.

```sh
zig build test example -Doptimize=Debug
zig build test example -Doptimize=ReleaseSafe
```

Import `test_support` for bounded commands, asynchronous capture owners,
readiness, private workspaces, diagnostic snapshots and file/JSON/PNG/resource
helpers. Separate `files`, `json`, `png` and `resources` modules require only the
standard library. The [example](examples/basic.zig) runs a real command and removes
its private workspace.

`command.runReport` composes the pinned zig-process 0.5.1 report API. Pass explicit
capture limits and timeouts in `Options.run`; optional `stdin` feeds a pipe while
both output streams drain. Reports own binary output and must be deinitialized.
Nonzero exits are results, not discarded output. `Diagnostic.expectExit` provides
bounded assertion diagnostics; `Diagnostic.fromReport` owns its excerpts after
the report is released. Primary and cleanup errors remain distinct.

`Command.start` returns a stable allocated asynchronous owner. Borrowed arguments,
environment and stdin must outlive `takeReport` or `cancel`; `deinit` joins and
frees any untaken report. Readiness never releases that owner. Readiness lines
compose a borrowed zig-process Child and PipeReader; callers retain the child
and reader for subsequent operations and cleanup.

Workspaces use exclusive random names and mode 0700. Call `close(.success)` or
`close(.failure)` explicitly; failure retention is opt-in. Report cleanup errors
alongside the original assertion failure. Do not hand this owner a foreign path.
PNG inspection validates only the signature, IHDR and dimensions, not CRCs or
pixels. RSS is in bytes; descriptor counts and RSS return null when unavailable.
`resources.measure` requires both measurements and cannot turn absence into zero.

See [ownership and limits](DESIGN.md). CI checks both native modes and an isolated
archive consumer. The zig-process revision and package hash are pinned in
[build.zig.zon](build.zig.zon); Zig fetches it from GitHub on the first build.
Browser/application acceptance remains a consumer obligation.
