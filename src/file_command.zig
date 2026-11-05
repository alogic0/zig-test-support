//! File-backed command composition. A process module parameter also supports
//! standalone source consumers without a second process implementation.
const std = @import("std");

pub fn WithProcess(comptime P: type) type {
    return struct {
        pub const Options = struct {
            spawn: P.SpawnOptions,
            timeout_ms: u32 = 30_000,
            cancel_grace_ms: u32 = 0,
        };
        /// Value-only report: streams are borrowed and remain caller-owned.
        /// wall_ns includes launch, waiting and cleanup, excluding log creation.
        pub const Report = struct {
            outcome: P.ReportOutcome = .completed,
            term: ?P.Child.Term = null,
            cleanup_failure: ?anyerror = null,
            wall_ns: u64 = 0,
            pub fn success(self: Report) bool {
                return self.outcome == .completed and self.cleanup_failure == null and
                    if (self.term) |term| term.success() else false;
            }
        };

        /// One deadline covers launch and execution. Pipes are rejected because
        /// this API never drains them. No file flags or caller bytes are changed.
        pub fn run(a: std.mem.Allocator, io: std.Io, options: Options) !Report {
            if (options.timeout_ms == 0 or options.spawn.launch_timeout_ms == 0 or
                options.spawn.stdin == .pipe or options.spawn.stdout == .pipe or options.spawn.stderr == .pipe)
                return error.InvalidOptions;
            const start = std.Io.Clock.awake.now(io);
            var report = try execute(a, io, options, start);
            report.wall_ns = @intCast(std.Io.Clock.awake.now(io).nanoseconds - start.nanoseconds);
            return report;
        }

        fn execute(a: std.mem.Allocator, io: std.Io, options: Options, start: std.Io.Timestamp) !Report {
            const end = start.addDuration(.fromMilliseconds(options.timeout_ms));
            const launch_end = start.addDuration(.fromMilliseconds(@min(options.timeout_ms, options.spawn.launch_timeout_ms)));
            var child = P.Child.spawnUntil(a, io, options.spawn, launch_end) catch |err| switch (err) {
                error.OutOfMemory, error.InvalidOptions => return err,
                else => return .{ .outcome = .{ .failed = .{ .phase = .launch, .cause = err } } },
            };
            defer child.deinit();
            const observed = child.pollUntil(end, options.spawn.cancellation) catch |err| {
                return interrupted(&child, if (err == error.Canceled) .canceled else .{ .failed = .{ .phase = .poll, .cause = err } }, if (err == error.Canceled) options.cancel_grace_ms else 0);
            };
            if (observed == null) return interrupted(&child, .timed_out, 0);
            const term = child.finish() catch |err| {
                return interrupted(&child, .{ .failed = .{ .phase = .finish, .cause = err } }, 0);
            };
            return .{ .term = term };
        }

        fn interrupted(child: *P.Child, outcome: P.ReportOutcome, grace_ms: u32) Report {
            var report: Report = .{ .outcome = outcome };
            report.term = child.stop(grace_ms) catch |err| {
                report.cleanup_failure = err;
                return report;
            };
            return report;
        }
    };
}
