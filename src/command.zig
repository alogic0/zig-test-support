//! Thin capture composition: zig-process owns launch, capture, deadlines and groups.
const std = @import("std");
const P = @import("process");
const Io = std.Io;
const A = std.mem.Allocator;
pub const Options = struct { run: P.RunOptions, stdin: ?[]const u8 = null };
pub fn code(term: P.Child.Term) i32 {
    return switch (term) {
        .exited => |n| n,
        .signal => |n| -@as(i32, @intCast(@backingInt(n))),
        else => -255,
    };
}
const Feed = struct {
    io: Io,
    file: Io.File,
    bytes: []const u8,
    failure: ?anyerror = null,
    fn run(self: *@This()) void {
        defer self.file.close(self.io);
        var buffer: [4096]u8 = undefined;
        var writer = P.PipeWriter.init(self.file, self.io, &buffer);
        self.write(&writer) catch |err| {
            self.failure = writer.err orelse err;
        };
    }
    fn write(self: *@This(), writer: *P.PipeWriter) !void {
        try writer.interface.writeAll(self.bytes);
        try writer.interface.flush();
    }
};
pub fn runReport(a: A, io: Io, options: Options) !P.Report {
    if (options.run.stdout_limit == std.math.maxInt(usize) or options.run.stderr_limit == std.math.maxInt(usize)) return error.InvalidOptions;
    const bytes = options.stdin orelse return P.runReport(a, io, options.run);
    if (options.run.spawn.stdin != .ignore) return error.InvalidOptions;
    const linux = std.os.linux;
    var fds: [2]linux.fd_t = undefined;
    if (linux.errno(linux.pipe2(&fds, .{ .CLOEXEC = true })) != .SUCCESS) return error.InputPipeFailed;
    const read: Io.File = .{ .handle = fds[0], .flags = .{ .nonblocking = false } };
    defer read.close(io);
    var write: ?Io.File = .{ .handle = fds[1], .flags = .{ .nonblocking = true } };
    defer if (write) |file| file.close(io);
    if (linux.errno(linux.fcntl(fds[1], linux.F.SETFL, @as(u32, @bitCast(linux.O{ .NONBLOCK = true })))) != .SUCCESS) return error.InputPipeFailed;
    var feed: Feed = .{ .io = io, .file = write.?, .bytes = bytes };
    var future = try io.concurrent(Feed.run, .{&feed});
    write = null; // Joined feed owns the writing end, including failed launch.
    defer _ = future.cancel(io);
    var run = options.run;
    run.spawn.stdin = .{ .file = read };
    var report = try P.runReport(a, io, run);
    _ = future.cancel(io);
    // Keep primary command outcome; input failure is secondary diagnostic data.
    if (feed.failure) |err| if (err != error.Canceled) {
        report.cleanup_failure = report.cleanup_failure orelse err;
    };
    return report;
}

/// Stable heap owner. Options/argv/env/stdin are borrowed until join/cancel.
/// The report survives readiness/cancellation races until takeReport or deinit.
pub const Command = struct {
    a: A,
    io: Io,
    options: Options,
    future: ?Io.Future(void) = null,
    done: std.atomic.Value(bool) = .init(false),
    result: ?anyerror!P.Report = null,
    pub fn start(a: A, io: Io, options: Options) !*Command {
        const self = try a.create(Command);
        errdefer a.destroy(self);
        self.* = .{ .a = a, .io = io, .options = options };
        self.future = try io.concurrent(capture, .{self});
        return self;
    }
    fn capture(self: *Command) void {
        self.result = runReport(self.a, self.io, self.options);
        self.done.store(true, .release);
    }
    pub fn isDone(self: *const Command) bool {
        return self.done.load(.acquire);
    }
    /// Cancellable completion observation; does not consume or release the result.
    pub fn wait(self: *const Command) Io.Cancelable!void {
        while (!self.isDone()) try self.io.sleep(.fromMilliseconds(1), .awake);
    }
    pub fn cancel(self: *Command) void {
        if (self.future) |*future| {
            _ = future.cancel(self.io);
            self.future = null;
        }
    }
    pub fn takeReport(self: *Command) !P.Report {
        if (self.future) |*future| {
            _ = future.await(self.io);
            self.future = null;
        }
        const result = self.result orelse return error.ReportAlreadyTaken;
        self.result = null;
        return result;
    }
    pub fn deinit(self: *Command) void {
        self.cancel();
        if (self.result) |result| {
            if (result) |report| report.deinit(self.a) else |_| {}
        }
        self.a.destroy(self);
    }
};
