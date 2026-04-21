// responsibility:
//   syscall remap for socket operations
//
// guarantees:
//   - 1:1 syscall mapping
//   - no policy
//
// non-goals:
//   - no address interpretation
//   - no default flags

const std = @import("std");
const posix = std.posix;

pub const AF = posix.AF;
pub const SOCK = posix.SOCK;
pub const SOL = posix.SOL;
pub const SO = posix.SO;
pub const sockaddr = posix.sockaddr;

pub fn socket(domain: u32, sock_type: u32, protocol: u32) !posix.fd_t {
    return posix.socket(domain, sock_type, protocol);
}

pub fn bind(fd: posix.fd_t, addr: *const posix.sockaddr, len: posix.socklen_t) !void {
    return posix.bind(fd, addr, len);
}

pub fn listen(fd: posix.fd_t, backlog: u31) !void {
    return posix.listen(fd, backlog);
}

pub fn accept(fd: posix.fd_t, flags: u32) !posix.fd_t {
    return posix.accept(fd, null, null, flags);
}

pub fn setsockopt(fd: posix.fd_t, level: i32, optname: u32, optval: []const u8) !void {
    return posix.setsockopt(fd, level, optname, optval);
}
