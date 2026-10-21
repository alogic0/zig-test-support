//! Borrowed JSON projections. Parsed owners are explicit and must be deinitialized.
const std = @import("std");
pub const Value = std.json.Value;
pub fn parse(a: std.mem.Allocator, bytes: []const u8) !std.json.Parsed(Value) {
    return std.json.parseFromSlice(Value, a, bytes, .{ .allocate = .alloc_always });
}
pub fn field(v: Value, key: []const u8) !Value {
    if (v != .object) return error.ExpectedObject;
    return v.object.get(key) orelse error.MissingField;
}
pub fn string(v: Value) ![]const u8 {
    if (v != .string or std.mem.trim(u8, v.string, " \t\r\n").len == 0) return error.ExpectedString;
    return v.string;
}
pub fn array(v: Value) ![]Value {
    if (v != .array) return error.ExpectedArray;
    return v.array.items;
}
pub fn str(v: Value, key: []const u8) ![]const u8 {
    return string(try field(v, key));
}
pub fn arr(v: Value, key: []const u8) ![]Value {
    return array(try field(v, key));
}
pub fn exact(v: Value, keys: []const []const u8) !void {
    if (v != .object or v.object.count() != keys.len) return error.UnexpectedKeys;
    for (keys) |key| _ = try field(v, key);
}
pub fn strings(v: Value) !void {
    for (try array(v)) |item| _ = try string(item);
}
pub fn integer(v: Value) !i64 {
    if (v != .integer) return error.ExpectedInteger;
    return v.integer;
}
pub fn is(v: Value, expected: []const u8) bool {
    return v == .string and std.mem.eql(u8, v.string, expected);
}
pub fn has(v: Value, key: []const u8) bool {
    return v == .object and v.object.contains(key);
}
