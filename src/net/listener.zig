// responsibility:
//   binds port and accepts connections
//
// guarantees:
//   - non-blocking accept
//   - returns raw fd
//
// non-goals:
//   - does not manage connection lifecycle

const std = @import("std");
const posix = std.posix;

pub const Listener = struct {
    fd: posix.fd_t,

    pub fn init(port: u16) !Listener {
        const fd = try posix.socket(
            posix.AF.INET,
            posix.SOCK.STREAM | posix.SOCK.NONBLOCK,
            0,
        );

        try posix.setsockopt(
            fd,
            posix.SOL.SOCKET,
            posix.SO.REUSEADDR,
            &std.mem.toBytes(@as(c_int, 1)),
        );

        const addr = posix.sockaddr.in{
            .family = posix.AF.INET,
            .port = std.mem.nativeToBig(u16, port),
            .addr = 0,
        };

        try posix.bind(fd, @ptrCast(&addr), @sizeOf(@TypeOf(addr)));
        try posix.listen(fd, 128);

        return .{ .fd = fd };
    }

    pub fn deinit(self: *Listener) void {
        posix.close(self.fd);
    }

    pub fn accept(self: *Listener) !?posix.fd_t {
        return posix.accept(self.fd, null, null, posix.SOCK.NONBLOCK) catch |err| switch (err) {
            error.WouldBlock => return null,
            else => return err,
        };
    }
};
