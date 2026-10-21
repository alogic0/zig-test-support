const std = @import("std");
const P = @import("process");
pub const Diagnostic = struct {
    pub const excerpt_limit = 4096;
    cause: anyerror,
    outcome: std.meta.Tag(P.ReportOutcome),
    phase: ?P.FailurePhase,
    code: ?i32,
    cleanup_failure: ?anyerror,
    stdout_bytes: usize,
    stderr_bytes: usize,
    stdout: [excerpt_limit]u8 = undefined,
    stderr: [excerpt_limit]u8 = undefined,
    pub fn fromReport(report: P.Report) ?Diagnostic {
        const cause = switch (report.outcome) {
            .completed => report.cleanup_failure orelse if (report.term == null) error.MissingCommandTermination else return null,
            .timed_out => error.Timeout,
            .canceled => error.Canceled,
            .output_limit => error.CommandOutputLimit,
            .failed => |failure| failure.cause,
        };
        var result: Diagnostic = .{ .cause = cause, .outcome = report.outcome, .phase = if (report.outcome == .failed) report.outcome.failed.phase else null, .code = if (report.term) |term| @import("command.zig").code(term) else null, .cleanup_failure = report.cleanup_failure, .stdout_bytes = report.stdout.len, .stderr_bytes = report.stderr.len };
        @memcpy(result.stdout[0..@min(report.stdout.len, excerpt_limit)], report.stdout[0..@min(report.stdout.len, excerpt_limit)]);
        @memcpy(result.stderr[0..@min(report.stderr.len, excerpt_limit)], report.stderr[0..@min(report.stderr.len, excerpt_limit)]);
        return result;
    }
    pub fn expectExit(report: P.Report, expected: struct { assertion: []const u8, code: i32 }) !void {
        const actual = if (report.term) |term| @import("command.zig").code(term) else null;
        if (report.outcome == .completed and report.cleanup_failure == null and actual == expected.code) return;
        std.debug.print("{s}: expected exit {d}, actual {any}, outcome {s}, cleanup {s}; stderr: {s}\n", .{ expected.assertion, expected.code, actual, @tagName(report.outcome), if (report.cleanup_failure) |err| @errorName(err) else "none", report.stderr[0..@min(report.stderr.len, excerpt_limit)] });
        return error.CommandExpectationFailed;
    }
};
