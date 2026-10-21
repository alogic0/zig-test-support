const std = @import("std");
pub const Dimensions = struct { width: u32, height: u32 };
/// Checks signature and first IHDR layout/dimensions. No CRC or pixel decoding.
pub fn dimensions(bytes: []const u8) !Dimensions {
    if (!std.mem.startsWith(u8, bytes, "\x89PNG\r\n\x1a\n")) return error.InvalidPng;
    if (bytes.len < 33) return error.TruncatedPng;
    if (std.mem.readInt(u32, bytes[8..12], .big) != 13 or !std.mem.eql(u8, bytes[12..16], "IHDR")) return error.InvalidPng;
    const size: Dimensions = .{ .width = std.mem.readInt(u32, bytes[16..20], .big), .height = std.mem.readInt(u32, bytes[20..24], .big) };
    if (size.width == 0 or size.height == 0 or size.width > 0x7fffffff or size.height > 0x7fffffff) return error.InvalidPng;
    return size;
}
