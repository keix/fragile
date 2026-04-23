// responsibility:
//   syscall remap for process operations
//
// guarantees:
//   - 1:1 syscall mapping
//   - no policy
//
// non-goals:
//   - no process management logic

const std = @import("std");
const posix = std.posix;

pub const pid_t = posix.pid_t;

pub fn fork() !pid_t {
    return posix.fork();
}

pub fn waitpid(pid: pid_t, flags: u32) !posix.WaitPidResult {
    return posix.waitpid(pid, flags);
}

pub const WNOHANG = posix.W.NOHANG;

pub const Sigaction = posix.Sigaction;
pub const sigset_t = posix.sigset_t;
pub const SIG = posix.SIG;
pub const SA = posix.SA;

pub fn sigemptyset() sigset_t {
    return posix.sigemptyset();
}

pub fn sigaction(sig: u6, act: ?*const Sigaction, oact: ?*Sigaction) !void {
    return posix.sigaction(sig, act, oact);
}
