# zig-test-support

Small native acceptance-test helpers, version 0.2.0, for Zig 0.17.0 on Linux:
bounded commands, asynchronous capture, readiness checks, private workspaces,
diagnostic snapshots and file/JSON/PNG/resource helpers. Application policy and
process-wide signal handling belong to callers.

Licensed under the [MIT License](LICENSE).

## Build and check

Use Zig 0.17.0, pinned in [.zigversion](.zigversion), on Linux. Zig fetches the
[zig-process](https://github.com/alogic0/zig-process) dependency automatically
using the revision and package hash in [build.zig.zon](build.zig.zon).
The first build needs network access. From the repository root:

```sh
zig build test example -Doptimize=Debug
zig build test example -Doptimize=ReleaseSafe
```

## Use as a package

For a sibling project, add this entry to `.dependencies` in its `build.zig.zon`:

```zig
.test_support = .{ .path = "../zig-test-support" },
```

In the consuming project's `build.zig`, add the module to your executable or
test artifact (`exe` below), using its target and optimization mode:

```zig
const support = b.dependency("test_support", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("test_support", support.module("test_support"));
```

Then import `test_support` in your Zig source:

```zig
const std = @import("std");
const S = @import("test_support");

pub fn main(init: std.process.Init) !void {
    const report = try S.command.runReport(init.gpa, init.io, .{
        .run = .{
            .spawn = .{ .argv = &.{ "/bin/echo", "hello" } },
            .stdout_limit = 4096,
            .stderr_limit = 1024,
            .timeout_ms = 1000,
        },
    });
    defer report.deinit(init.gpa);
    try S.Diagnostic.expectExit(report, .{ .assertion = "echo", .code = 0 });
}
```

Separate `files`, `json`, `png` and `resources` modules require only the standard
library; select one with, for example, `support.module("files")`. The
[complete example](examples/basic.zig) also creates and removes a private
workspace, writes atomic JSON and captures command output in a file.

## Commands and diagnostics

`command.runReport` composes the pinned [zig-process](https://github.com/alogic0/zig-process)
0.6.1 report API. Pass explicit capture limits and timeouts in `Options.run`;
optional `stdin` feeds a pipe while both output streams drain.
Reports own binary output and must be deinitialized.
Nonzero exits are results, not discarded output. `Diagnostic.expectExit` provides
bounded assertion diagnostics; `Diagnostic.fromReport` owns its excerpts after
the report is released. Primary and cleanup errors remain distinct.

`command.File.run(allocator, io, options)` writes directly to the borrowed files
in `options.spawn`. Its timeout includes launch and execution; its value-only
report retains outcome, actual termination, cleanup failure and elapsed `wall_ns`
without capturing output or requiring deinit. Pipes are rejected. Log creation
and filesystem limits belong to the caller. `files.createLog` creates an owned
Linux append descriptor so independent positional writers retain earlier output.
Ordinary borrowed descriptors keep their original flags. Standalone source
consumers can bind `file_command.zig.WithProcess(process)` to their process module.

`command.Command.start` returns a stable allocated asynchronous owner. Borrowed
arguments, environment and stdin must outlive `takeReport` or `cancel`; `deinit`
joins and frees any untaken report. Readiness never releases that owner. Readiness
lines compose a borrowed zig-process Child and PipeReader; callers retain the
child and reader for subsequent operations and cleanup.

## Files and JSON

`files.writeAtomic(io, options, chunks)` publishes complete bytes with explicit
`options.replace` behavior. It uses std.Io's exclusive temporary/unnamed files;
failure cleanup is uncancelable and best effort. `json.writeAtomic` composes this
with indented JSON and a trailing newline. These helpers promise atomic visibility,
not crash durability. `files.sha256` streams file bytes with bounded memory.

`json.text` and `textField` accept all strings. `nonEmptyString` rejects blank
strings; legacy `string`, `str` and `strings` retain their nonempty behavior.
`canonicalAlloc` returns owned sorted-key JSON with escaped Unicode; it is not
RFC 8785 and preserves std.json number spelling. `eql` compares objects independent
of key order and arrays in order, without allocating. Number tags are significant:
integers compare exactly, number strings compare exact text, and floats use `==`
(positive/negative zero equal, NaN unequal). Serialization rejects nonfinite floats.
Pass valid JSON tokens when constructing `number_string` values yourself.

## Workspaces and resource checks

Workspaces use exclusive random names and mode 0700. Call `close(.success)` or
`close(.failure)` explicitly; failure retention is opt-in. Report cleanup errors
alongside the original assertion failure. Do not hand this owner a foreign path.
PNG inspection validates only the signature, IHDR and dimensions, not CRCs or
pixels. RSS is in bytes; descriptor counts and RSS return null when unavailable.
`resources.measure` requires both measurements and cannot turn absence into zero.

## Design and validation

See [ownership and limits](DESIGN.md). CI checks both native modes and an isolated
source-directory consumer using a fresh package cache. The process revision and
package hash are pinned in [build.zig.zon](build.zig.zon). Browser/application
acceptance remains a consumer obligation. See the [changelog](CHANGELOG.md) and
[implementation plan](docs/plans/2026-11-05-validation-helpers.md).

## License

This project is licensed under the [MIT License](LICENSE).
The [zig-process](https://github.com/alogic0/zig-process) dependency retains its own
[MIT license](https://github.com/alogic0/zig-process/blob/e9fcfccecc84f44a362b12de1bee78258b1e811f/LICENSE)
and copyright notice.
See [NOTICE](NOTICE) for attribution.
