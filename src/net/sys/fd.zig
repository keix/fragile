// responsibility:
//   syscall remap for fd operations
//
// guarantees:
//   - 1:1 syscall mapping
//   - no policy
//
// non-goals:
//   - no buffering
//   - no interpretation

const std = @import("std");
const posix = std.posix;

pub fn open(path: []const u8) !posix.fd_t {
    return posix.open(path, .{ .ACCMODE = .RDONLY }, 0);
}

pub fn close(fd: posix.fd_t) void {
    posix.close(fd);
}

pub fn read(fd: posix.fd_t, buf: []u8) !usize {
    return posix.read(fd, buf);
}

pub fn write(fd: posix.fd_t, buf: []const u8) !usize {
    return posix.write(fd, buf);
}

pub fn writev(fd: posix.fd_t, iovecs: []const posix.iovec_const) !usize {
    return posix.writev(fd, iovecs);
}
