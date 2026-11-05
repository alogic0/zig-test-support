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
        if (args.len > 2) {
            var ready = try std.Io.Dir.cwd().createFileAtomic(init.io, args[2], .{ .replace = true });
            defer ready.deinit(init.io);
            try ready.file.writeStreamingAll(init.io, try init.arena.allocator().print("{d}", .{std.os.linux.getpid()}));
            try ready.replace(init.io);
        }
        try init.io.sleep(.fromSeconds(30), .awake);
    } else if (std.mem.eql(u8, mode, "positional")) {
        var first_buffer: [32]u8 = undefined;
        var first = std.Io.File.stdout().writer(init.io, &first_buffer);
        try first.interface.writeAll("first\x00\xff\n");
        try first.interface.flush();
        var second_buffer: [32]u8 = undefined;
        var second = std.Io.File.stdout().writer(init.io, &second_buffer);
        try second.interface.writeAll("second\n");
        try second.interface.flush();
        var error_buffer: [32]u8 = undefined;
        var diagnostic = std.Io.File.stderr().writer(init.io, &error_buffer);
        try diagnostic.interface.writeAll("diagnostic\n");
        try diagnostic.interface.flush();
        std.process.exit(7);
    } else if (std.mem.eql(u8, mode, "bulk")) {
        const bytes: [65537]u8 = @splat(0xff);
        for (0..4) |_| {
            try std.Io.File.stdout().writeStreamingAll(init.io, &bytes);
            try std.Io.File.stderr().writeStreamingAll(init.io, &bytes);
        }
    } else if (std.mem.eql(u8, mode, "binary")) {
        try std.Io.File.stdout().writeStreamingAll(init.io, "a\x00\xff");
        try std.Io.File.stderr().writeStreamingAll(init.io, "b\x00\xfe");
        std.process.exit(7);
    } else if (std.mem.eql(u8, mode, "env")) {
        try std.Io.File.stdout().writeStreamingAll(init.io, init.environ_map.get("EXAMPLE_VALUE") orelse "missing");
    } else return error.UnknownMode;
}
