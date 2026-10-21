const std = @import("std");
const S = @import("test_support");
pub fn main(init: std.process.Init) !void {
    var workspace = try S.Workspace.init(init.gpa, init.io, .{ .prefix = "test-support-example-" });
    defer workspace.close(.failure) catch {};
    const report = try S.command.runReport(init.gpa, init.io, .{ .run = .{ .spawn = .{ .argv = &.{"/bin/pwd"}, .cwd = .{ .path = workspace.path } }, .stdout_limit = 4096, .stderr_limit = 1024, .timeout_ms = 1000 } });
    defer report.deinit(init.gpa);
    try S.Diagnostic.expectExit(report, .{ .assertion = "command in owned workspace", .code = 0 });
    if (!std.mem.eql(u8, std.mem.trim(u8, report.stdout, "\n"), workspace.path)) return error.WrongWorkingDirectory;
    try workspace.close(.success);
    std.debug.print("PASS: private workspace and bounded command; mode={s}\n", .{@tagName(S.compiled_mode)});
}
