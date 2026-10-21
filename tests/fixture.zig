const std = @import("std");
pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const mode = args[1];
    if (std.mem.eql(u8, mode, "pressure")) {
        const bytes = try init.arena.allocator().alloc(u8, 131072);
        @memset(bytes, 'o');
        try std.Io.File.stdout().writeStreamingAll(init.io, bytes);
        @memset(bytes, 'e');
        try std.Io.File.stderr().writeStreamingAll(init.io, bytes);
        var buffer: [4096]u8 = undefined;
        var reader = std.Io.File.stdin().readerStreaming(init.io, &buffer);
        const input = try reader.interface.allocRemaining(init.arena.allocator(), .limited(1024 * 1024));
        try std.Io.File.stdout().writeStreamingAll(init.io, input);
    } else if (std.mem.eql(u8, mode, "hold")) {
        try std.Io.File.stdout().writeStreamingAll(init.io, "ready\n");
        try init.io.sleep(.fromSeconds(30), .awake);
    } else if (std.mem.eql(u8, mode, "binary")) {
        try std.Io.File.stdout().writeStreamingAll(init.io, "a\x00\xff");
        try std.Io.File.stderr().writeStreamingAll(init.io, "b\x00\xfe");
        std.process.exit(7);
    } else if (std.mem.eql(u8, mode, "env")) {
        try std.Io.File.stdout().writeStreamingAll(init.io, init.environ_map.get("EXAMPLE_VALUE") orelse "missing");
    } else return error.UnknownMode;
}
