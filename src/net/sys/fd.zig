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

pub fn sendfile(out_fd: posix.fd_t, in_fd: posix.fd_t, offset: *usize, count: usize) !usize {
    var off: i64 = @intCast(offset.*);
    const rc = std.os.linux.sendfile(out_fd, in_fd, &off, count);
    return switch (std.posix.errno(rc)) {
        .SUCCESS => blk: {
            if (rc == 0 and count != 0) return error.UnexpectedEof;
            offset.* = @intCast(off);
            break :blk rc;
        },
        .AGAIN => error.WouldBlock,
        .BADF => error.BadFd,
        .FAULT => unreachable,
        .INVAL => error.Invalid,
        .IO => error.IoError,
        .NOMEM => error.OutOfMemory,
        .OVERFLOW => error.Overflow,
        .SPIPE => error.Invalid,
        else => error.Unexpected,
    };
}

pub fn size(fd_: posix.fd_t) !usize {
    const stat = try posix.fstat(fd_);
    return @intCast(stat.size);
}
