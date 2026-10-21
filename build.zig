const std = @import("std");
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const process = b.dependency("process", .{ .target = target, .optimize = optimize }).module("process");
    const support = b.addModule("test_support", .{ .root_source_file = b.path("src/root.zig"), .target = target, .optimize = optimize, .imports = &.{.{ .name = "process", .module = process }} });
    inline for (.{ "files", "json", "png", "resources" }) |name| {
        _ = b.addModule(name, .{ .root_source_file = b.path("src/" ++ name ++ ".zig"), .target = target, .optimize = optimize });
    }
    const fixture = b.addExecutable(.{ .name = "support-fixture", .root_module = b.createModule(.{ .root_source_file = b.path("tests/fixture.zig"), .target = target, .optimize = optimize }) });
    const options = b.addOptions();
    options.addOptionPath("fixture", fixture.getEmittedBin());
    const test_mod = b.createModule(.{ .root_source_file = b.path("tests/support.zig"), .target = target, .optimize = optimize, .imports = &.{.{ .name = "test_support", .module = support }} });
    test_mod.addOptions("test_options", options);
    const tests = b.addTest(.{ .root_module = test_mod });
    const run_tests = b.addRunArtifact(tests);
    run_tests.has_side_effects = true;
    b.step("test", "Check bounded ownership, diagnostics and independent helpers").dependOn(&run_tests.step);
    const example = b.addExecutable(.{ .name = "support-example", .root_module = b.createModule(.{ .root_source_file = b.path("examples/basic.zig"), .target = target, .optimize = optimize, .imports = &.{.{ .name = "test_support", .module = support }} }) });
    const run_example = b.addRunArtifact(example);
    run_example.has_side_effects = true;
    b.step("example", "Run a finite command in a private workspace").dependOn(&run_example.step);
}
