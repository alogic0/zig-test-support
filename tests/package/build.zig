const std = @import("std");
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const support = b.dependency("test_support", .{ .target = target, .optimize = optimize }).module("test_support");
    const exe = b.addExecutable(.{ .name = "package-consumer", .root_module = b.createModule(.{ .root_source_file = b.path("main.zig"), .target = target, .optimize = optimize, .imports = &.{.{ .name = "test_support", .module = support }} }) });
    const run = b.addRunArtifact(exe);
    run.has_side_effects = true;
    b.step("test", "Verify isolated immutable package consumption").dependOn(&run.step);
}
