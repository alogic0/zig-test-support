const std = @import("std");
const S = @import("test_support");
pub fn main(init: std.process.Init) !void {
    var workspace = try S.Workspace.init(init.gpa, init.io, .{ .prefix = "test-support-example-" });
    defer workspace.close(.failure) catch {};
    const report = try S.command.runReport(init.gpa, init.io, .{ .run = .{ .spawn = .{ .argv = &.{"/bin/pwd"}, .cwd = .{ .path = workspace.path } }, .stdout_limit = 4096, .stderr_limit = 1024, .timeout_ms = 1000 } });
    defer report.deinit(init.gpa);
    try S.Diagnostic.expectExit(report, .{ .assertion = "command in owned workspace", .code = 0 });
    if (!std.mem.eql(u8, std.mem.trim(u8, report.stdout, "\n"), workspace.path)) return error.WrongWorkingDirectory;
    const record_path = try std.fs.path.join(init.gpa, &.{ workspace.path, "record.json" });
    defer init.gpa.free(record_path);
    try S.json.writeAtomic(init.gpa, init.io, .{ .path = record_path, .replace = false }, .{ .message = "", .status = "passed" });
    const bytes = try S.files.read(init.gpa, init.io, .{ .path = record_path, .limit = 1024 });
    defer init.gpa.free(bytes);
    var parsed = try S.json.parse(init.gpa, bytes);
    defer parsed.deinit();
    if ((try S.json.textField(parsed.value, "message")).len != 0) return error.ExpectedEmptyString;
    const log_path = try std.fs.path.join(init.gpa, &.{ workspace.path, "command.log" });
    defer init.gpa.free(log_path);
    {
        const log = try S.files.createLog(init.io, .{ .path = log_path, .exclusive = true });
        defer log.close(init.io);
        const logged = try S.command.File.run(init.gpa, init.io, .{ .spawn = .{
            .argv = &.{ "/bin/echo", "file-backed command" },
            .stdout = .{ .file = log },
            .stderr = .{ .file = log },
        }, .timeout_ms = 1000 });
        if (!logged.success()) return error.FileCommandFailed;
    }
    try S.files.expectBytes(init.gpa, init.io, .{ .path = log_path, .bytes = "file-backed command\n" });
    try workspace.close(.success);
    std.debug.print("PASS: private workspace, bounded capture, atomic JSON and file command; mode={s}\n", .{@tagName(S.compiled_mode)});
}
