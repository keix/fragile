// responsibility:
//   syscall remap for epoll
//
// guarantees:
//   - 1:1 syscall mapping
//   - no policy
//   - errors propagated where applicable
//
// non-goals:
//   - no retry logic
//   - no default values
//
// note:
//   - wait() returns usize (Zig's posix handles EINTR internally)

const std = @import("std");
const posix = std.posix;
const linux = std.os.linux;

pub const Event = linux.epoll_event;
pub const EPOLL = linux.EPOLL;

pub const Epoll = struct {
    fd: posix.fd_t,

    pub fn init() !Epoll {
        return .{
            .fd = try posix.epoll_create1(0),
        };
    }

    pub fn deinit(self: *Epoll) void {
        posix.close(self.fd);
    }

    pub fn add(self: *Epoll, fd: posix.fd_t, events: u32) !void {
        var ev = Event{
            .events = events,
            .data = .{ .fd = fd },
        };
        try posix.epoll_ctl(self.fd, linux.EPOLL.CTL_ADD, fd, &ev);
    }

    pub fn del(self: *Epoll, fd: posix.fd_t) !void {
        try posix.epoll_ctl(self.fd, linux.EPOLL.CTL_DEL, fd, null);
    }

    pub fn wait(self: *Epoll, events: []Event, timeout: i32) usize {
        return posix.epoll_wait(self.fd, events, timeout);
    }
};
