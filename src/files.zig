const std = @import("std");
pub const AtomicOptions = struct {
    path: []const u8,
    replace: bool,
    permissions: std.Io.File.Permissions = .default_file,
};

/// Atomically publish complete bytes, optionally replacing the destination.
/// Uses a same-directory exclusive temporary file (or an unnamed OS file).
/// Cleanup is uncancelable; filesystem cleanup failures remain best effort.
/// This guarantees atomic visibility, not persistence through power loss.
pub fn writeAtomic(io: std.Io, options: AtomicOptions, data: []const []const u8) !void {
    var file = try std.Io.Dir.cwd().createFileAtomic(io, options.path, .{
        .replace = options.replace,
        .permissions = options.permissions,
    });
    defer {
        const protection = io.swapCancelProtection(.blocked);
        defer _ = io.swapCancelProtection(protection);
        file.deinit(io);
    }
    for (data) |bytes| try file.file.writeStreamingAll(io, bytes);
    if (options.replace) try file.replace(io) else try file.link(io);
}

/// Create an owned Linux log descriptor. O_APPEND also protects independent
/// positional stdout/stderr writers. No borrowed descriptor is modified.
pub fn createLog(io: std.Io, options: struct {
    path: []const u8,
    exclusive: bool = false,
    truncate: bool = true,
    permissions: std.Io.File.Permissions = .default_file,
}) !std.Io.File {
    if (@import("builtin").os.tag != .linux) return error.UnsupportedPlatform;
    const file = try std.Io.Dir.cwd().createFile(io, options.path, .{
        .exclusive = options.exclusive,
        .truncate = options.truncate,
        .permissions = options.permissions,
    });
    errdefer file.close(io);
    const linux = std.os.linux;
    const flags = linux.fcntl(file.handle, linux.F.GETFL, 0);
    if (linux.errno(flags) != .SUCCESS) return error.LogFlagsUnavailable;
    const append = flags | @as(u32, @bitCast(linux.O{ .APPEND = true }));
    if (linux.errno(linux.fcntl(file.handle, linux.F.SETFL, append)) != .SUCCESS) return error.LogAppendUnavailable;
    return file;
}

/// Hash file bytes using bounded storage, including files with unknown size.
pub fn sha256(io: std.Io, path: []const u8) ![32]u8 {
    const file = try std.Io.Dir.cwd().openFile(io, path, .{});
    defer file.close(io);
    var buffer: [65536]u8 = undefined;
    var reader = file.readerStreaming(io, &buffer);
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    while (true) {
        const bytes = reader.interface.peekGreedy(1) catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        };
        hash.update(bytes);
        reader.interface.toss(bytes.len);
    }
    return hash.finalResult();
}

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
