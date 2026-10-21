//! Linux observations only: never signal or reap a PID read from /proc.
const std = @import("std");
const Io = std.Io;
const A = std.mem.Allocator;
fn path(buffer: []u8, pid: i32, suffix: []const u8) ![]const u8 {
    if (@import("builtin").os.tag != .linux) return error.UnsupportedPlatform;
    if (pid <= 0) return error.InvalidPid;
    return std.fmt.bufPrint(buffer, "/proc/{d}{s}", .{ pid, suffix });
}
pub fn present(io: Io, pid: i32) !bool {
    var buffer: [64]u8 = undefined;
    Io.Dir.cwd().access(io, try path(&buffer, pid, ""), .{}) catch |err| return if (err == error.FileNotFound) false else err;
    return true;
}
pub fn rssBytes(a: A, io: Io, pid: i32) !?u64 {
    var buffer: [64]u8 = undefined;
    const bytes = @import("files.zig").read(a, io, .{ .path = try path(&buffer, pid, "/status"), .limit = 65536 }) catch |err| return if (err == error.FileNotFound) null else err;
    defer a.free(bytes);
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    while (lines.next()) |line| if (std.mem.startsWith(u8, line, "VmRSS:")) {
        var words = std.mem.tokenizeAny(u8, line[6..], " \t");
        const kib = try std.fmt.parseInt(u64, words.next() orelse return error.InvalidRss, 10);
        if (!std.mem.eql(u8, words.next() orelse return error.InvalidRss, "kB")) return error.InvalidRss;
        return std.math.mul(u64, kib, 1024) catch return error.InvalidRss;
    };
    return null;
}
pub fn descriptorCount(io: Io, pid: i32) !?usize {
    var buffer: [64]u8 = undefined;
    var dir = Io.Dir.cwd().openDir(io, try path(&buffer, pid, "/fd"), .{ .iterate = true }) catch |err| return if (err == error.FileNotFound) null else err;
    defer dir.close(io);
    var iterator = dir.iterate();
    var count: usize = 0;
    while (try iterator.next(io)) |_| count += 1;
    return count;
}
pub fn measure(a: A, io: Io, pid: i32) !struct { rss_bytes: u64, descriptors: usize } {
    return .{ .rss_bytes = try rssBytes(a, io, pid) orelse return error.MeasurementUnavailable, .descriptors = try descriptorCount(io, pid) orelse return error.MeasurementUnavailable };
}
