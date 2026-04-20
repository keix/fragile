// responsibility:
//   thin wrapper around epoll syscalls
//
// guarantees:
//   - no abstraction beyond syscall
//   - no state interpretation
//
// non-goals:
//   - does not know HTTP
//   - does not know Connection

const std = @import("std");
const posix = std.posix;
const linux = std.os.linux;

pub const Event = linux.epoll_event;

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

    pub fn add(self: *Epoll, fd: posix.fd_t) !void {
        var ev = Event{
            .events = linux.EPOLL.IN,
            .data = .{ .fd = fd },
        };
        try posix.epoll_ctl(self.fd, linux.EPOLL.CTL_ADD, fd, &ev);
    }

    pub fn del(self: *Epoll, fd: posix.fd_t) void {
        posix.epoll_ctl(self.fd, linux.EPOLL.CTL_DEL, fd, null) catch {};
    }

    pub fn wait(self: *Epoll, events: []Event) usize {
        return posix.epoll_wait(self.fd, events, -1);
    }
};
