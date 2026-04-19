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
