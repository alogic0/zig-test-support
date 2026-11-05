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
/// Extract any JSON string, including empty and whitespace-only strings.
pub fn text(v: Value) ![]const u8 {
    if (v != .string) return error.ExpectedString;
    return v.string;
}
pub fn textField(v: Value, key: []const u8) ![]const u8 {
    return text(try field(v, key));
}
pub fn nonEmptyString(v: Value) ![]const u8 {
    if (v != .string or std.mem.trim(u8, v.string, " \t\r\n").len == 0) return error.ExpectedString;
    return v.string;
}
/// Compatibility alias: historically string/str reject blank strings.
pub const string = nonEmptyString;
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

/// Recursively compare values without allocating. Object order is irrelevant;
/// array order and number tags are significant. number_string compares exact
/// text, integers compare exactly, floats use == (NaN unequal, +/-0 equal).
pub fn eql(lhs: Value, rhs: Value) bool {
    if (@as(std.meta.Tag(Value), lhs) != @as(std.meta.Tag(Value), rhs)) return false;
    return switch (lhs) {
        .null => true,
        .bool => |v| v == rhs.bool,
        .integer => |v| v == rhs.integer,
        .float => |v| v == rhs.float,
        .string => |v| std.mem.eql(u8, v, rhs.string),
        .number_string => |v| std.mem.eql(u8, v, rhs.number_string),
        .array => |items| blk: {
            if (items.items.len != rhs.array.items.len) break :blk false;
            for (items.items, rhs.array.items) |a, b| if (!eql(a, b)) break :blk false;
            break :blk true;
        },
        .object => |map| blk: {
            if (map.count() != rhs.object.count()) break :blk false;
            for (map.keys(), map.values()) |key, value| {
                if (!eql(value, rhs.object.get(key) orelse break :blk false)) break :blk false;
            }
            break :blk true;
        },
    };
}

/// Owned, compact sorted-key JSON with escaped Unicode. This is deterministic
/// serialization, not RFC 8785. Number spelling/tags follow std.json; callers
/// must supply valid number_string tokens. Free the result with a.free().
pub fn canonicalAlloc(a: std.mem.Allocator, value: Value) ![]u8 {
    var scratch = std.heap.ArenaAllocator.init(a);
    defer scratch.deinit();
    return std.json.Stringify.valueAlloc(a, try ordered(scratch.allocator(), value), .{ .escape_unicode = true });
}
fn ordered(a: std.mem.Allocator, value: Value) error{ OutOfMemory, NonFiniteNumber }!Value {
    return switch (value) {
        .object => |map| blk: {
            const keys = try a.dupe([]const u8, map.keys());
            std.mem.sort([]const u8, keys, {}, struct {
                fn less(_: void, lhs: []const u8, rhs: []const u8) bool {
                    return std.mem.lessThan(u8, lhs, rhs);
                }
            }.less);
            var result: std.json.ObjectMap = .empty;
            for (keys) |key| try result.put(a, key, try ordered(a, map.get(key).?));
            break :blk .{ .object = result };
        },
        .array => |items| blk: {
            var result: std.json.Array = .init(a);
            for (items.items) |item| try result.append(try ordered(a, item));
            break :blk .{ .array = result };
        },
        .float => |number| if (std.math.isFinite(number)) value else error.NonFiniteNumber,
        else => value,
    };
}

/// Write indented JSON followed by a newline using atomic file replacement.
pub fn writeAtomic(a: std.mem.Allocator, io: std.Io, options: @import("files.zig").AtomicOptions, value: anytype) !void {
    const bytes = try std.json.Stringify.valueAlloc(a, value, .{ .whitespace = .indent_2 });
    defer a.free(bytes);
    try @import("files.zig").writeAtomic(io, options, &.{ bytes, "\n" });
}
