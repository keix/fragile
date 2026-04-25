// responsibility:
//   forks worker processes and monitors them
//
// guarantees:
//   - no shared state between workers
//   - no locks
//   - kernel distributes connections via SO_REUSEPORT
//
// non-goals:
//   - no IPC
//   - no coordination

const std = @import("std");
const process = @import("../net/sys/process.zig");
const Listener = @import("../net/listener.zig").Listener;
const Loop = @import("loop.zig").Loop;
const handler = @import("../http/handler.zig");
const gate = @import("../http/gate.zig");

pub const Worker = struct {
    listener: *Listener,
    handler: handler.Handler,
    gates: []const gate.Gate,
    num_workers: usize,
    children: [16]process.pid_t,
    child_count: usize,

    pub fn init(
        listener: *Listener,
        gates: []const gate.Gate,
        h: handler.Handler,
        num_workers: usize,
    ) Worker {
        return .{
            .listener = listener,
            .handler = h,
            .gates = gates,
            .num_workers = @min(num_workers, 16),
            .children = undefined,
            .child_count = 0,
        };
    }

    /// Spawn worker processes and run event loops.
    /// Returns only in parent after all children exit.
    pub fn run(self: *Worker) !void {
        // Install SIGCHLD handler in parent
        try installSigchldHandler();

        // Fork workers
        for (0..self.num_workers) |_| {
            const pid = try process.fork();

            if (pid == 0) {
                // Child: run event loop (never returns)
                self.runWorker();
            } else {
                // Parent: track child
                self.children[self.child_count] = pid;
                self.child_count += 1;
            }
        }

        // Parent: wait for all children
        self.waitChildren();
    }

    fn runWorker(self: *Worker) noreturn {
        var loop = Loop.init(self.listener, self.gates, self.handler) catch {
            std.process.exit(1);
        };
        defer loop.deinit();

        loop.run();

        // loop.run() is infinite, but just in case
        std.process.exit(0);
    }

    fn waitChildren(self: *Worker) void {
        while (self.child_count > 0) {
            const result = process.waitpid(-1, 0) catch break;

            // Find and remove from children list
            for (0..self.child_count) |i| {
                if (self.children[i] == result.pid) {
                    self.children[i] = self.children[self.child_count - 1];
                    self.child_count -= 1;
                    break;
                }
            }
        }
    }
};

fn installSigchldHandler() !void {
    const act = process.Sigaction{
        .handler = .{ .handler = handleSigchld },
        .mask = process.sigemptyset(),
        .flags = process.SA.RESTART | process.SA.NOCLDSTOP,
    };
    try process.sigaction(process.SIG.CHLD, &act, null);
}

fn handleSigchld(_: c_int) callconv(.c) void {
    // Do nothing here. waitChildren handles reaping.
    // This handler exists only to interrupt blocking waitpid with EINTR.
}
