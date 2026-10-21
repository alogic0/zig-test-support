const std = @import("std");
const Self = @This();
a: std.mem.Allocator,
io: std.Io,
path: []const u8,
policy: enum { remove, retain_on_failure },
closed: bool = false,
pub const Outcome = enum { success, failure };
pub fn init(a: std.mem.Allocator, io: std.Io, options: struct { parent: []const u8 = "/tmp", prefix: []const u8, policy: @FieldType(Self, "policy") = .remove }) !Self {
    if (options.prefix.len == 0 or std.mem.indexOfAny(u8, options.prefix, "/\\\x00") != null) return error.InvalidPrefix;
    var random: [12]u8 = undefined;
    io.random(&random);
    const name = try a.print("{s}{s}", .{ options.prefix, std.fmt.bytesToHex(random, .lower) });
    defer a.free(name);
    const path = try std.fs.path.join(a, &.{ options.parent, name });
    errdefer a.free(path);
    try std.Io.Dir.cwd().createDir(io, path, .fromMode(0o700));
    return .{ .a = a, .io = io, .path = path, .policy = options.policy };
}
/// Failure leaves ownership intact for retry and preserves the primary error.
/// Successful close frees path, including when the directory is intentionally retained.
pub fn close(self: *Self, outcome: Outcome) !void {
    if (self.closed) return;
    if (!(outcome == .failure and self.policy == .retain_on_failure)) try std.Io.Dir.cwd().deleteTree(self.io, self.path);
    self.a.free(self.path);
    self.closed = true;
}
