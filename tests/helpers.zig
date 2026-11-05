const std = @import("std");
const S = @import("test_support");
const t = std.testing;
const Io = std.Io;

fn onlyEntries(dir: Io.Dir, expected: usize) !void {
    var iterator = dir.iterate();
    var count: usize = 0;
    while (try iterator.next(t.io)) |_| count += 1;
    try t.expectEqual(expected, count);
}

test "atomic writes replace completely, preserve existing paths on request, and hash bytes" {
    var tmp = t.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    const root = try tmp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    const path = try std.fs.path.join(t.allocator, &.{ root, "value" });
    defer t.allocator.free(path);
    try S.files.writeAtomic(t.io, .{ .path = path, .replace = false, .permissions = .fromMode(0o600) }, &.{"abc"});
    try S.files.expectMode(t.io, .{ .path = path, .mode = 0o600 });
    try t.expectEqualStrings("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", &std.fmt.bytesToHex(try S.files.sha256(t.io, path), .lower));
    try t.expectError(error.PathAlreadyExists, S.files.writeAtomic(t.io, .{ .path = path, .replace = false }, &.{"bad"}));
    try S.files.expectBytes(t.allocator, t.io, .{ .path = path, .bytes = "abc" });
    const large: [65537]u8 = @splat(0xff);
    try S.files.writeAtomic(t.io, .{ .path = path, .replace = true }, &.{ &large, "tail" });
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    hash.update(&large);
    hash.update("tail");
    try t.expectEqualSlices(u8, &hash.finalResult(), &try S.files.sha256(t.io, path));
    try onlyEntries(tmp.dir, 1);
}

test "atomic write and publication failures retain the destination and clean temporary files" {
    var tmp = t.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    const root = try tmp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    const path = try std.fs.path.join(t.allocator, &.{ root, "value" });
    defer t.allocator.free(path);
    try S.files.writeAtomic(t.io, .{ .path = path, .replace = true }, &.{"original"});
    const Faults = struct {
        fn diskFull(userdata: ?*anyopaque, operation: Io.Operation) Io.Cancelable!Io.Operation.Result {
            if (operation == .file_write_streaming) return .{ .file_write_streaming = error.NoSpaceLeft };
            return t.io.vtable.operate(userdata, operation);
        }
        fn canceled(userdata: ?*anyopaque, operation: Io.Operation) Io.Cancelable!Io.Operation.Result {
            if (operation == .file_write_streaming) return error.Canceled;
            return t.io.vtable.operate(userdata, operation);
        }
    };
    var vtable = t.io.vtable.*;
    const failing_io: Io = .{ .userdata = t.io.userdata, .vtable = &vtable };
    vtable.operate = Faults.diskFull;
    try t.expectError(error.NoSpaceLeft, S.files.writeAtomic(failing_io, .{ .path = path, .replace = true }, &.{"replacement"}));
    vtable.operate = Faults.canceled;
    try t.expectError(error.Canceled, S.files.writeAtomic(failing_io, .{ .path = path, .replace = true }, &.{"replacement"}));
    try S.files.expectBytes(t.allocator, t.io, .{ .path = path, .bytes = "original" });
    try onlyEntries(tmp.dir, 1);
    try tmp.dir.createDir(t.io, "directory", .default_dir);
    const directory = try std.fs.path.join(t.allocator, &.{ root, "directory" });
    defer t.allocator.free(directory);
    if (S.files.writeAtomic(t.io, .{ .path = directory, .replace = true }, &.{"bad"})) |_| {
        return error.ExpectedPublicationFailure;
    } else |_| {}
    try onlyEntries(tmp.dir, 2);
}

test "concurrent atomic writers never expose partial or mixed output" {
    var tmp = t.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    const root = try tmp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    const path = try std.fs.path.join(t.allocator, &.{ root, "value" });
    defer t.allocator.free(path);
    const first: [16387]u8 = @splat('a');
    const second: [16387]u8 = @splat('b');
    try S.files.writeAtomic(t.io, .{ .path = path, .replace = true }, &.{&first});
    const Writer = struct {
        fn run(destination: []const u8, bytes: []const u8) !void {
            for (0..25) |_| try S.files.writeAtomic(t.io, .{ .path = destination, .replace = true }, &.{ bytes[0..8192], bytes[8192..] });
        }
    };
    var a = try t.io.concurrent(Writer.run, .{ path, &first });
    defer _ = a.cancel(t.io) catch {};
    var b = try t.io.concurrent(Writer.run, .{ path, &second });
    defer _ = b.cancel(t.io) catch {};
    for (0..50) |_| {
        const bytes = try S.files.read(t.allocator, t.io, .{ .path = path, .limit = first.len + 1 });
        defer t.allocator.free(bytes);
        try t.expect(std.mem.eql(u8, bytes, &first) or std.mem.eql(u8, bytes, &second));
    }
    try a.await(t.io);
    try b.await(t.io);
    try onlyEntries(tmp.dir, 1);
}

test "JSON extraction, ordering and exact number semantics are explicit" {
    var lhs = try S.json.parse(t.allocator, "{\"z\":[18446744073709551615,\"é\"],\"a\":\"\"}");
    defer lhs.deinit();
    var rhs = try S.json.parse(t.allocator, "{\"a\":\"\",\"z\":[18446744073709551615,\"é\"]}");
    defer rhs.deinit();
    try t.expect(S.json.eql(lhs.value, rhs.value));
    try t.expectEqualStrings("", try S.json.textField(lhs.value, "a"));
    try t.expectEqualStrings(" \t", try S.json.text(.{ .string = " \t" }));
    try t.expectError(error.ExpectedString, S.json.nonEmptyString(.{ .string = " \t" }));
    try t.expectError(error.ExpectedString, S.json.str(lhs.value, "a"));
    try t.expectError(error.ExpectedString, S.json.text(.{ .integer = 1 }));
    const encoded = try S.json.canonicalAlloc(t.allocator, lhs.value);
    defer t.allocator.free(encoded);
    try t.expectEqualStrings("{\"a\":\"\",\"z\":[18446744073709551615,\"\\u00e9\"]}", encoded);
    try t.expect(!S.json.eql(.{ .integer = 1 }, .{ .float = 1.0 }));
    try t.expect(!S.json.eql(.{ .integer = 1 }, .{ .number_string = "1" }));
    try t.expect(!S.json.eql(.{ .number_string = "1e2" }, .{ .number_string = "100" }));
    try t.expect(S.json.eql(.{ .float = 0.0 }, .{ .float = -0.0 }));
    try t.expect(!S.json.eql(.{ .float = std.math.nan(f64) }, .{ .float = std.math.nan(f64) }));
    try t.expectError(error.NonFiniteNumber, S.json.canonicalAlloc(t.allocator, .{ .float = std.math.inf(f64) }));
    std.mem.reverse(S.json.Value, (try S.json.field(rhs.value, "z")).array.items);
    try t.expect(!S.json.eql(lhs.value, rhs.value));
}

fn jsonAllocations(a: std.mem.Allocator) !void {
    var parsed = try S.json.parse(a, "{\"z\":[{\"b\":2,\"a\":1}],\"a\":\"owned\"}");
    defer parsed.deinit();
    const encoded = try S.json.canonicalAlloc(a, parsed.value);
    defer a.free(encoded);
    var again = try S.json.parse(a, encoded);
    defer again.deinit();
    try t.expect(S.json.eql(parsed.value, again.value));
}
test "canonical JSON releases scratch storage on every allocation failure" {
    try t.checkAllAllocationFailures(t.allocator, jsonAllocations, .{});
}

test "atomic JSON writes preserve their text format and explicit replacement policy" {
    var tmp = t.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    const root = try tmp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    const path = try std.fs.path.join(t.allocator, &.{ root, "record.json" });
    defer t.allocator.free(path);
    try S.json.writeAtomic(t.allocator, t.io, .{ .path = path, .replace = false }, .{ .value = "" });
    try S.files.expectBytes(t.allocator, t.io, .{ .path = path, .bytes = "{\n  \"value\": \"\"\n}\n" });
    try t.expectError(error.PathAlreadyExists, S.json.writeAtomic(t.allocator, t.io, .{ .path = path, .replace = false }, .{ .value = "bad" }));
    try onlyEntries(tmp.dir, 1);
}

test "file commands preserve positional and binary logs, nonzero results and borrowed handles" {
    var tmp = t.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    const path = try std.fs.path.join(t.allocator, &.{ root, "command.log" });
    defer t.allocator.free(path);
    const exe = try Io.Dir.cwd().realPathFileAlloc(t.io, @import("test_options").fixture, t.allocator);
    defer t.allocator.free(exe);
    const log = try S.files.createLog(t.io, .{ .path = path, .exclusive = true });
    defer log.close(t.io);
    const report = try S.command.File.run(t.allocator, t.io, .{ .spawn = .{
        .argv = &.{ exe, "positional" },
        .stdout = .{ .file = log },
        .stderr = .{ .file = log },
    } });
    try t.expect(report.outcome == .completed);
    try t.expectEqual(7, S.command.code(report.term.?));
    try t.expect(!report.success());
    try t.expect(report.wall_ns > 0);
    try log.writeStreamingAll(t.io, "tail");
    try S.files.expectBytes(t.allocator, t.io, .{ .path = path, .bytes = "first\x00\xff\nsecond\ndiagnostic\ntail" });
    try t.expectError(error.PathAlreadyExists, S.files.createLog(t.io, .{ .path = path, .exclusive = true }));

    const plain = try Io.Dir.cwd().createFile(t.io, path, .{});
    defer plain.close(t.io);
    const before = std.os.linux.fcntl(plain.handle, std.os.linux.F.GETFL, 0);
    const binary = try S.command.File.run(t.allocator, t.io, .{ .spawn = .{ .argv = &.{ exe, "binary" }, .stdout = .{ .file = plain } } });
    try t.expectEqual(7, S.command.code(binary.term.?));
    try t.expectEqual(before, std.os.linux.fcntl(plain.handle, std.os.linux.F.GETFL, 0));
    try S.files.expectBytes(t.allocator, t.io, .{ .path = path, .bytes = "a\x00\xff" });
}

test "file commands stream output beyond their allocator capacity and reject undrained pipes" {
    var tmp = t.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    const path = try std.fs.path.join(t.allocator, &.{ root, "bulk.log" });
    defer t.allocator.free(path);
    const exe = try Io.Dir.cwd().realPathFileAlloc(t.io, @import("test_options").fixture, t.allocator);
    defer t.allocator.free(exe);
    const log = try S.files.createLog(t.io, .{ .path = path });
    defer log.close(t.io);
    var storage: [128 * 1024]u8 = undefined;
    var fixed = std.heap.FixedBufferAllocator.init(&storage);
    const report = try S.command.File.run(fixed.allocator(), t.io, .{ .spawn = .{ .argv = &.{ exe, "bulk" }, .stdout = .{ .file = log }, .stderr = .{ .file = log } } });
    try t.expect(report.success());
    try t.expectEqual(8 * 65537, (try log.stat(t.io)).size);
    try t.expectError(error.InvalidOptions, S.command.File.run(t.allocator, t.io, .{ .spawn = .{ .argv = &.{exe}, .stdout = .pipe } }));
    try t.expectError(error.InvalidOptions, S.command.File.run(t.allocator, t.io, .{ .spawn = .{ .argv = &.{exe} }, .timeout_ms = 0 }));
    const failed = try S.command.File.run(t.allocator, t.io, .{ .spawn = .{ .argv = &.{"/missing-test-support-file-command"} } });
    try t.expect(failed.outcome == .failed and failed.outcome.failed.phase == .launch);
    try t.expect(failed.term == null and failed.cleanup_failure == null);
}

test "file commands retain timeout and both cancellation outcomes and join the exact child" {
    var tmp = t.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    const path = try std.fs.path.join(t.allocator, &.{ root, "hold.log" });
    defer t.allocator.free(path);
    const ready_path = try std.fs.path.join(t.allocator, &.{ root, "ready" });
    defer t.allocator.free(ready_path);
    const exe = try Io.Dir.cwd().realPathFileAlloc(t.io, @import("test_options").fixture, t.allocator);
    defer t.allocator.free(exe);
    const log = try S.files.createLog(t.io, .{ .path = path });
    defer log.close(t.io);
    var foreign = try S.process.Child.spawn(t.allocator, t.io, .{ .argv = &.{ "/bin/sleep", "10" } });
    defer foreign.deinit();
    const timeout = try S.command.File.run(t.allocator, t.io, .{ .spawn = .{ .argv = &.{ exe, "hold" }, .stdout = .{ .file = log } }, .timeout_ms = 100 });
    try t.expect(timeout.outcome == .timed_out);
    try t.expect(timeout.term != null and timeout.cleanup_failure == null);
    for (0..2) |kind| {
        var token: S.process.Cancellation = .{};
        var future = try t.io.concurrent(S.command.File.run, .{ t.allocator, t.io, S.command.File.Options{
            .spawn = .{ .argv = &.{ exe, "hold", ready_path }, .stdout = .{ .file = log }, .cancellation = &token },
            .timeout_ms = 3000,
        } });
        defer _ = future.cancel(t.io) catch {};
        try S.readiness.file(t.io, .{ .path = ready_path, .timeout_ms = 2000 });
        const bytes = try S.files.read(t.allocator, t.io, .{ .path = ready_path, .limit = 32 });
        defer t.allocator.free(bytes);
        const pid = try std.fmt.parseInt(i32, bytes, 10);
        const canceled = if (kind == 0) blk: {
            token.request();
            break :blk try future.await(t.io);
        } else try future.cancel(t.io);
        try t.expect(canceled.outcome == .canceled);
        try t.expect(canceled.term != null and canceled.cleanup_failure == null);
        try t.expect(!try S.resources.present(t.io, pid));
        try Io.Dir.cwd().deleteFile(t.io, ready_path);
    }
    try t.expectEqual(null, try foreign.poll());
    try log.writeStreamingAll(t.io, "still owned");
}

test "file command primary and cleanup failures remain separate after final owner cleanup" {
    const FakeProcess = struct {
        pub const SpawnOptions = S.process.SpawnOptions;
        pub const ReportOutcome = S.process.ReportOutcome;
        pub const Child = struct {
            pub const Term = S.process.Child.Term;
            pub var cleaned = false;
            pub fn spawnUntil(_: std.mem.Allocator, _: Io, _: SpawnOptions, _: Io.Timestamp) !@This() {
                return .{};
            }
            pub fn pollUntil(_: *@This(), _: Io.Timestamp, _: ?*const S.process.Cancellation) !?Term {
                return error.PrimaryObservationFailure;
            }
            pub fn finish(_: *@This()) !Term {
                return error.UnexpectedFinish;
            }
            pub fn stop(_: *@This(), _: u32) !Term {
                return error.SecondaryCleanupFailure;
            }
            pub fn deinit(_: *@This()) void {
                cleaned = true;
            }
        };
    };
    FakeProcess.Child.cleaned = false;
    const report = try S.command.FileWithProcess(FakeProcess).run(t.allocator, t.io, .{ .spawn = .{ .argv = &.{"fake"} } });
    try t.expect(report.outcome == .failed);
    try t.expectEqual(error.PrimaryObservationFailure, report.outcome.failed.cause);
    try t.expectEqual(error.SecondaryCleanupFailure, report.cleanup_failure.?);
    try t.expect(report.term == null and FakeProcess.Child.cleaned);
}
