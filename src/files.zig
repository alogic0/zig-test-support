const std = @import("std");
pub fn read(a: std.mem.Allocator, io: std.Io, options: struct { path: []const u8, limit: usize }) ![]u8 {
    const file = try std.Io.Dir.cwd().openFile(io, options.path, .{});
    defer file.close(io);
    var buffer: [4096]u8 = undefined;
    var reader = file.readerStreaming(io, &buffer);
    return reader.interface.allocRemaining(a, .limited(options.limit));
}
pub fn expectBytes(a: std.mem.Allocator, io: std.Io, options: struct { path: []const u8, bytes: []const u8 }) !void {
    const actual = try read(a, io, .{ .path = options.path, .limit = options.bytes.len +| 1 });
    defer a.free(actual);
    if (!std.mem.eql(u8, options.bytes, actual)) return error.FileBytesMismatch;
}
pub fn expectMode(io: std.Io, options: struct { path: []const u8, mode: u32 }) !void {
    const stat = try std.Io.Dir.cwd().statFile(io, options.path, .{ .follow_symlinks = false });
    if (stat.permissions.toMode() & 0o777 != options.mode) return error.FileModeMismatch;
}
pub fn expectSymlink(io: std.Io, options: struct { path: []const u8, target: []const u8 }) !void {
    var buffer: [4096]u8 = undefined;
    const n = try std.Io.Dir.cwd().readLink(io, options.path, &buffer);
    if (!std.mem.eql(u8, buffer[0..n], options.target)) return error.SymlinkMismatch;
}
