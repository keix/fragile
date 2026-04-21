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

const posix = @import("std").posix;

pub fn close(fd: posix.fd_t) void {
    posix.close(fd);
}

pub fn read(fd: posix.fd_t, buf: []u8) !usize {
    return posix.read(fd, buf);
}

pub fn write(fd: posix.fd_t, buf: []const u8) !usize {
    return posix.write(fd, buf);
}
