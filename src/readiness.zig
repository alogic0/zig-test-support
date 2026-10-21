//! Readiness never releases the child or command owner, even when exit wins a race.
const std = @import("std");
const P = @import("process");
const Io = std.Io;
const A = std.mem.Allocator;
const Command = @import("command.zig").Command;
pub fn file(io: Io, options: struct { path: []const u8, timeout_ms: u32, child: ?*P.Child = null, command: ?*Command = null }) !void {
    if (options.timeout_ms == 0 or (options.child != null and options.command != null)) return error.InvalidOptions;
    const end = Io.Clock.awake.now(io).addDuration(.fromMilliseconds(options.timeout_ms));
    while (true) {
        if (options.child) |child| if (try child.poll() != null) return error.ExitedBeforeReady;
        if (options.command) |command| if (command.isDone()) return error.ExitedBeforeReady;
        if (Io.Dir.cwd().access(io, options.path, .{})) |_| return else |err| if (err != error.FileNotFound) return err;
        if (Io.Clock.awake.now(io).nanoseconds >= end.nanoseconds) return error.ReadinessTimeout;
        try io.sleep(.fromMilliseconds(5), .awake);
    }
}
pub fn absent(io: Io, options: struct { path: []const u8, timeout_ms: u32 }) !void {
    if (options.timeout_ms == 0) return error.InvalidOptions;
    const end = Io.Clock.awake.now(io).addDuration(.fromMilliseconds(options.timeout_ms));
    while (true) {
        Io.Dir.cwd().access(io, options.path, .{}) catch |err| {
            if (err == error.FileNotFound) return;
            return err;
        };
        if (Io.Clock.awake.now(io).nanoseconds >= end.nanoseconds) return error.ReadinessTimeout;
        try io.sleep(.fromMilliseconds(5), .awake);
    }
}
pub fn line(a: A, io: Io, child: *P.Child, reader: *P.PipeReader, options: struct { max_bytes: usize, timeout_ms: u32 }) ![]u8 {
    if (options.timeout_ms == 0 or options.max_bytes == 0) return error.InvalidOptions;
    const Box = struct {
        a: A,
        reader: *P.PipeReader,
        limit: usize,
        bytes: ?[]u8 = null,
        fn read(self: *@This()) anyerror!void {
            var result: std.ArrayList(u8) = .empty;
            errdefer result.deinit(self.a);
            while (true) {
                const byte = self.reader.interface.takeByte() catch |err| return self.reader.err orelse err;
                if (byte == '\n') break;
                if (result.items.len == self.limit) return error.ReadinessLineTooLong;
                try result.append(self.a, byte);
            }
            self.bytes = try result.toOwnedSlice(self.a);
        }
        fn exit(owner: *P.Child, end: Io.Timestamp) anyerror!void {
            if (try owner.pollUntil(end, null) != null) return error.ExitedBeforeReady;
            return error.ReadinessTimeout;
        }
    };
    var box: Box = .{ .a = a, .reader = reader, .limit = options.max_bytes };
    errdefer if (box.bytes) |bytes| a.free(bytes);
    const Result = union(enum) { ready: anyerror!void, exit: anyerror!void };
    var storage: [2]Result = undefined;
    var select: Io.Select(Result) = .init(io, &storage);
    // Join before releasing a concurrently completed line allocation.
    defer select.cancelDiscard();
    try select.concurrent(.ready, Box.read, .{&box});
    try select.concurrent(.exit, Box.exit, .{ child, Io.Clock.awake.now(io).addDuration(.fromMilliseconds(options.timeout_ms)) });
    switch (try select.await()) {
        .ready => |result| try result,
        .exit => |result| try result,
    }
    select.cancelDiscard();
    return box.bytes orelse error.ExitedBeforeReady;
}
