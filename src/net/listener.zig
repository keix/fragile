// responsibility:
//   composes syscalls into a listening socket
//
// guarantees:
//   - non-blocking accept
//   - returns raw fd
//
// non-goals:
//   - does not manage connection lifecycle

const std = @import("std");
const sys = @import("sys/socket.zig");
const fd = @import("sys/fd.zig");

pub const Listener = struct {
    fd: std.posix.fd_t,

    pub fn init(port: u16) !Listener {
        const sock = try sys.socket(
            sys.AF.INET,
            sys.SOCK.STREAM | sys.SOCK.NONBLOCK,
            0,
        );

        try sys.setsockopt(
            sock,
            sys.SOL.SOCKET,
            sys.SO.REUSEADDR,
            &std.mem.toBytes(@as(c_int, 1)),
        );

        const addr = sys.sockaddr.in{
            .family = sys.AF.INET,
            .port = std.mem.nativeToBig(u16, port),
            .addr = 0,
        };

        try sys.bind(sock, @ptrCast(&addr), @sizeOf(@TypeOf(addr)));
        try sys.listen(sock, 128);

        return .{ .fd = sock };
    }

    pub fn deinit(self: *Listener) void {
        fd.close(self.fd);
    }

    pub fn accept(self: *Listener) !?std.posix.fd_t {
        return sys.accept(self.fd, sys.SOCK.NONBLOCK) catch |err| switch (err) {
            error.WouldBlock => return null,
            else => return err,
        };
    }
};
