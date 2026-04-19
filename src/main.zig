const std = @import("std");
const posix = std.posix;
const Loop = @import("server/loop.zig").Loop;

pub fn main() !void {
    const listen_fd = try createListener(8080);
    defer posix.close(listen_fd);

    var loop = try Loop.init(listen_fd);
    defer loop.deinit();

    try loop.run();
}

fn createListener(port: u16) !posix.fd_t {
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

    return fd;
}
