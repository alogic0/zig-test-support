const std = @import("std");
const S = @import("test_support");
const t = std.testing;
const Io = std.Io;
test {
    _ = @import("helpers.zig");
}
fn fixture(a: std.mem.Allocator) ![:0]u8 {
    return Io.Dir.cwd().realPathFileAlloc(t.io, @import("test_options").fixture, a);
}

test "workspace is private, exclusive, removable, idempotent and optionally retained" {
    for (0..3) |_| {
        var ws = try S.Workspace.init(t.allocator, t.io, .{ .prefix = "support-test-" });
        defer ws.close(.failure) catch {};
        const path = try t.allocator.dupe(u8, ws.path);
        defer t.allocator.free(path);
        try S.files.expectMode(t.io, .{ .path = ws.path, .mode = 0o700 });
        try ws.close(.success);
        try ws.close(.success);
        try t.expectError(error.FileNotFound, Io.Dir.cwd().access(t.io, path, .{}));
    }
    var retained = try S.Workspace.init(t.allocator, t.io, .{ .prefix = "support-retain-", .policy = .retain_on_failure });
    const path = try t.allocator.dupe(u8, retained.path);
    defer t.allocator.free(path);
    defer Io.Dir.cwd().deleteTree(t.io, path) catch {};
    try retained.close(.failure);
    try Io.Dir.cwd().access(t.io, path, .{});
}
test "independent file byte, permission, symlink and owned JSON assertions" {
    var ws = try S.Workspace.init(t.allocator, t.io, .{ .prefix = "support-file-" });
    defer ws.close(.failure) catch {};
    const path = try std.fs.path.join(t.allocator, &.{ ws.path, "value" });
    defer t.allocator.free(path);
    try Io.Dir.cwd().writeFile(t.io, .{ .sub_path = path, .data = "a\x00\xff" });
    try S.files.expectBytes(t.allocator, t.io, .{ .path = path, .bytes = "a\x00\xff" });
    try t.expectError(error.FileBytesMismatch, S.files.expectBytes(t.allocator, t.io, .{ .path = path, .bytes = "x\x00\xff" }));
    const link = try std.fs.path.join(t.allocator, &.{ ws.path, "link" });
    defer t.allocator.free(link);
    try Io.Dir.cwd().symLink(t.io, "value", link, .{});
    try S.files.expectSymlink(t.io, .{ .path = link, .target = "value" });
    var parsed = try S.json.parse(t.allocator, "{\"name\":\"owned\",\"n\":3}");
    defer parsed.deinit();
    try S.json.exact(parsed.value, &.{ "name", "n" });
    try t.expectEqualStrings("owned", try S.json.str(parsed.value, "name"));
    try t.expectEqual(3, try S.json.integer(try S.json.field(parsed.value, "n")));
    try t.expectError(error.MissingField, S.json.field(parsed.value, "absent"));
    try t.expectError(error.ExpectedArray, S.json.array(parsed.value));
}
test "PNG header bounds and dimensions without decoding" {
    var bytes: [33]u8 = @splat(0);
    @memcpy(bytes[0..8], "\x89PNG\r\n\x1a\n");
    std.mem.writeInt(u32, bytes[8..12], 13, .big);
    @memcpy(bytes[12..16], "IHDR");
    std.mem.writeInt(u32, bytes[16..20], 640, .big);
    std.mem.writeInt(u32, bytes[20..24], 480, .big);
    try t.expectEqual(S.png.Dimensions{ .width = 640, .height = 480 }, try S.png.dimensions(&bytes));
    try t.expectError(error.TruncatedPng, S.png.dimensions(bytes[0..24]));
    bytes[12] = 'X';
    try t.expectError(error.InvalidPng, S.png.dimensions(&bytes));
}
test "resource measurements require a live PID and distinguish unavailable from zero" {
    const pid: i32 = @intCast(std.os.linux.getpid());
    try t.expect(try S.resources.present(t.io, pid));
    const metrics = try S.resources.measure(t.allocator, t.io, pid);
    try t.expect(metrics.rss_bytes > 0 and metrics.descriptors > 0);
    try t.expectEqual(null, try S.resources.rssBytes(t.allocator, t.io, std.math.maxInt(i32)));
    try t.expectError(error.MeasurementUnavailable, S.resources.measure(t.allocator, t.io, std.math.maxInt(i32)));
    try t.expectError(error.InvalidPid, S.resources.present(t.io, 0));
}
test "bounded commands preserve binary nonzero results and exact independent capture limits" {
    const exe = try fixture(t.allocator);
    defer t.allocator.free(exe);
    for (0..2) |overflow| {
        const report = try S.command.runReport(t.allocator, t.io, .{ .run = .{ .spawn = .{ .argv = &.{ exe, "binary" } }, .stdout_limit = 3 - overflow, .stderr_limit = 3, .timeout_ms = 2000 } });
        defer report.deinit(t.allocator);
        if (overflow == 0) {
            try S.Diagnostic.expectExit(report, .{ .assertion = "binary command nonzero", .code = 7 });
            try t.expectEqualStrings("a\x00\xff", report.stdout);
            try t.expectEqualStrings("b\x00\xfe", report.stderr);
        } else try t.expect(report.outcome == .output_limit);
    }
}
test "stdin and both output pipes progress under pressure and preserve binary input" {
    const exe = try fixture(t.allocator);
    defer t.allocator.free(exe);
    const bytes = try t.allocator.alloc(u8, 262144);
    defer t.allocator.free(bytes);
    for (bytes, 0..) |*byte, i| byte.* = @truncate(i);
    const report = try S.command.runReport(t.allocator, t.io, .{ .run = .{ .spawn = .{ .argv = &.{ exe, "pressure" } }, .stdout_limit = 131072 + bytes.len, .stderr_limit = 131072, .timeout_ms = 5000 }, .stdin = bytes });
    defer report.deinit(t.allocator);
    try S.Diagnostic.expectExit(report, .{ .assertion = "full duplex pressure", .code = 0 });
    try t.expectEqualStrings(bytes, report.stdout[131072..]);
    try t.expectEqual(131072, report.stderr.len);
}
test "environment, cwd and separate cleanup diagnostics survive report release" {
    const exe = try fixture(t.allocator);
    defer t.allocator.free(exe);
    var env = std.process.Environ.Map.init(t.allocator);
    defer env.deinit();
    try env.put("EXAMPLE_VALUE", "sentinel");
    var ws = try S.Workspace.init(t.allocator, t.io, .{ .prefix = "support-env-" });
    defer ws.close(.failure) catch {};
    const report = try S.command.runReport(t.allocator, t.io, .{ .run = .{ .spawn = .{ .argv = &.{ exe, "env" }, .cwd = .{ .path = ws.path }, .environ_map = &env }, .timeout_ms = 1000 } });
    defer report.deinit(t.allocator);
    try t.expectEqualStrings("sentinel", report.stdout);
    const out = try t.allocator.alloc(u8, 5000);
    @memset(out, 0xff);
    var fake: S.process.Report = .{ .outcome = .{ .failed = .{ .phase = .stdout, .cause = error.PrimaryFailure } }, .term = null, .stdout = out, .stderr = try t.allocator.dupe(u8, "cleanup"), .cleanup_failure = error.SecondaryFailure };
    const diagnostic = S.Diagnostic.fromReport(fake).?;
    fake.deinit(t.allocator);
    try t.expectEqual(error.PrimaryFailure, diagnostic.cause);
    try t.expectEqual(error.SecondaryFailure, diagnostic.cleanup_failure.?);
    try t.expectEqual(5000, diagnostic.stdout_bytes);
    try t.expectEqual(0xff, diagnostic.stdout[4095]);
}
test "asynchronous command cancellation retains its joined report and repeated cleanup" {
    const exe = try fixture(t.allocator);
    defer t.allocator.free(exe);
    for (0..3) |_| {
        const command = try S.command.Command.start(t.allocator, t.io, .{ .run = .{ .spawn = .{ .argv = &.{ exe, "hold" } }, .timeout_ms = 3000 } });
        defer command.deinit();
        try t.io.sleep(.fromMilliseconds(30), .awake);
        command.cancel();
        command.cancel();
        const report = try command.takeReport();
        defer report.deinit(t.allocator);
        try t.expect(report.outcome == .canceled);
        try t.expectError(error.ReportAlreadyTaken, command.takeReport());
    }
}
test "readiness line and file races retain exact child ownership" {
    const exe = try fixture(t.allocator);
    defer t.allocator.free(exe);
    var child = try S.process.Child.spawn(t.allocator, t.io, .{ .argv = &.{ exe, "hold" }, .stdout = .pipe });
    defer child.deinit();
    var buffer: [128]u8 = undefined;
    var reader = S.process.PipeReader.init(child.stdout.?, t.io, &buffer);
    const line = try S.readiness.line(t.allocator, t.io, &child, &reader, .{ .max_bytes = 5, .timeout_ms = 1000 });
    defer t.allocator.free(line);
    try t.expectEqualStrings("ready", line);
    try t.expect(child.pid != null);
    try t.expectError(error.ReadinessTimeout, S.readiness.file(t.io, .{ .path = "/proc/2147483647/support-ready", .timeout_ms = 20, .child = &child }));
    _ = try child.stop(50);
    try t.expectError(error.ExitedBeforeReady, S.readiness.file(t.io, .{ .path = "/proc/2147483647/support-ready", .timeout_ms = 20, .child = &child }));
}
test "timeout drains exited leader descendants without touching an unrelated child" {
    var foreign = try S.process.Child.spawn(t.allocator, t.io, .{ .argv = &.{ "/bin/sleep", "5" } });
    defer foreign.deinit();
    const report = try S.command.runReport(t.allocator, t.io, .{ .run = .{ .spawn = .{ .argv = &.{ "/bin/sh", "-c", "sleep 5 & printf leader" } }, .timeout_ms = 100, .exit_policy = .drain_output } });
    defer report.deinit(t.allocator);
    try t.expect(report.outcome == .timed_out);
    try t.expectEqualStrings("leader", report.stdout);
    try t.expectEqual(null, try foreign.poll());
}
fn allocations(a: std.mem.Allocator) !void {
    var ws = try S.Workspace.init(a, t.io, .{ .prefix = "support-alloc-" });
    defer ws.close(.failure) catch {};
    const command = try S.command.Command.start(a, t.io, .{ .run = .{ .spawn = .{ .argv = &.{"/bin/cat"} }, .timeout_ms = 1000 }, .stdin = "owned" });
    defer command.deinit();
    const report = try command.takeReport();
    defer report.deinit(a);
}
test "allocation failures release workspace and command captures" {
    try t.checkAllAllocationFailures(t.allocator, allocations, .{});
}

test "readiness overflow, early exit and success remain bounded with owners retained" {
    const exe = try fixture(t.allocator);
    defer t.allocator.free(exe);
    var ws = try S.Workspace.init(t.allocator, t.io, .{ .prefix = "support-ready-" });
    defer ws.close(.failure) catch {};
    try S.readiness.file(t.io, .{ .path = ws.path, .timeout_ms = 100 });
    inline for (.{ "hold", "binary" }) |mode| {
        var child = try S.process.Child.spawn(t.allocator, t.io, .{ .argv = &.{ exe, mode }, .stdout = .pipe });
        defer child.deinit();
        var buffer: [32]u8 = undefined;
        var reader = S.process.PipeReader.init(child.stdout.?, t.io, &buffer);
        if (S.readiness.line(t.allocator, t.io, &child, &reader, .{ .max_bytes = 2, .timeout_ms = 1000 })) |line| {
            t.allocator.free(line);
            return error.UnexpectedReadiness;
        } else |err| try t.expect(err == error.ReadinessLineTooLong or err == error.ExitedBeforeReady);
        try t.expect(child.pid != null);
    }
    const command = try S.command.Command.start(t.allocator, t.io, .{ .run = .{ .spawn = .{ .argv = &.{ exe, "binary" } }, .timeout_ms = 1000 } });
    defer command.deinit();
    try t.expectError(error.ExitedBeforeReady, S.readiness.file(t.io, .{ .path = "/proc/2147483647/support-ready", .timeout_ms = 1000, .command = command }));
    const report = try command.takeReport();
    defer report.deinit(t.allocator);
    try S.Diagnostic.expectExit(report, .{ .assertion = "retained early exit", .code = 7 });
}
test "blocked input joins on timeout and failed launch" {
    const bytes = try t.allocator.alloc(u8, 262144);
    defer t.allocator.free(bytes);
    @memset(bytes, 'i');
    for ([_][]const []const u8{ &.{ "/bin/sleep", "5" }, &.{"/missing-test-support-command"} }) |argv| {
        const report = try S.command.runReport(t.allocator, t.io, .{ .run = .{ .spawn = .{ .argv = argv }, .timeout_ms = 30 }, .stdin = bytes });
        defer report.deinit(t.allocator);
        try t.expect(report.outcome == .timed_out or report.outcome == .failed);
    }
}

test "command signal outcome and finite admission remain explicit" {
    try t.expectEqual(@import("builtin").mode, S.compiled_mode);
    const report = try S.command.runReport(t.allocator, t.io, .{ .run = .{ .spawn = .{ .argv = &.{ "/bin/sh", "-c", "kill -TERM $$" } }, .timeout_ms = 1000 } });
    defer report.deinit(t.allocator);
    try t.expectEqual(-15, S.command.code(report.term.?));
    try t.expectError(error.InvalidOptions, S.command.runReport(t.allocator, t.io, .{ .run = .{ .spawn = .{ .argv = &.{"/bin/true"} }, .stdout_limit = std.math.maxInt(usize) } }));
}
