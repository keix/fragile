// responsibility:
//   holds connection state and buffers
//
// guarantees:
//   - explicit state transitions
//   - exposes state, does not decide
//
// non-goals:
//   - no protocol logic
//   - no parsing
//   - no HTTP knowledge

const std = @import("std");
const posix = std.posix;
const sys_fd = @import("../net/sys/fd.zig");

pub const State = enum {
    reading,
    writing,
    sending_file,
};

// =============================================================================
// FileSend: file body send state
// =============================================================================

pub const FileSend = struct {
    fd: i32 = -1,
    size: usize = 0,
    sent: usize = 0,
    owned: bool = false,

    pub fn active(self: FileSend) bool {
        return self.fd >= 0;
    }

    pub fn remaining(self: FileSend) usize {
        return self.size - self.sent;
    }

    pub fn done(self: FileSend) bool {
        return self.sent >= self.size;
    }

    pub fn close(self: *FileSend) void {
        if (self.fd >= 0 and self.owned) {
            sys_fd.close(self.fd);
        }
        self.* = .{};
    }
};

// =============================================================================
// Outgoing: response write state
// =============================================================================

pub const Outgoing = struct {
    header_buf: [1024]u8 = undefined,
    header_len: usize = 0,
    header_pos: usize = 0,

    body_slice: []const u8 = &.{},
    body_pos: usize = 0,

    scratch: [SCRATCH_SIZE]u8 = undefined,

    pub const SCRATCH_SIZE = 8192;

    pub fn reset(self: *Outgoing) void {
        self.header_len = 0;
        self.header_pos = 0;
        self.body_slice = &.{};
        self.body_pos = 0;
    }

    pub fn headerRemaining(self: *const Outgoing) []const u8 {
        return self.header_buf[self.header_pos..self.header_len];
    }

    pub fn bodyRemaining(self: *const Outgoing) []const u8 {
        return self.body_slice[self.body_pos..];
    }

    pub fn done(self: *const Outgoing) bool {
        return self.header_pos >= self.header_len and self.body_pos >= self.body_slice.len;
    }
};

// =============================================================================
// Connection
// =============================================================================

pub const Connection = struct {
    fd: i32,
    state: State,

    read_buf: [4096]u8,
    read_pos: usize,

    keep_alive: bool,
    requests_served: usize,
    write_armed: bool,

    out: Outgoing,
    file: FileSend,

    pub fn init(fd: i32) Connection {
        return .{
            .fd = fd,
            .state = .reading,
            .read_buf = undefined,
            .read_pos = 0,
            .keep_alive = true,
            .requests_served = 0,
            .write_armed = false,
            .out = .{},
            .file = .{},
        };
    }

    /// Reset for next request (keep-alive)
    pub fn reset(self: *Connection) void {
        self.file.close();
        self.read_pos = 0;
        self.write_armed = false;
        self.out.reset();
        self.state = .reading;
    }

    pub fn read(self: *Connection) !usize {
        if (self.read_pos >= self.read_buf.len) {
            return error.BufferFull;
        }

        const n = try sys_fd.read(self.fd, self.read_buf[self.read_pos..]);
        self.read_pos += n;
        return n;
    }

    /// Write header + body via writev (slice body only)
    pub fn writev(self: *Connection) !bool {
        const header_remaining = self.out.headerRemaining();
        const body_remaining = self.out.bodyRemaining();

        if (header_remaining.len == 0 and body_remaining.len == 0) return true;

        var iovecs: [2]posix.iovec_const = .{ undefined, undefined };
        var iov_count: usize = 0;

        if (header_remaining.len > 0) {
            iovecs[iov_count] = .{ .base = header_remaining.ptr, .len = header_remaining.len };
            iov_count += 1;
        }
        if (body_remaining.len > 0) {
            iovecs[iov_count] = .{ .base = body_remaining.ptr, .len = body_remaining.len };
            iov_count += 1;
        }

        const n = try sys_fd.writev(self.fd, iovecs[0..iov_count]);
        if (n == 0) return false; // no progress, wait for EPOLLOUT

        if (n <= header_remaining.len) {
            self.out.header_pos += n;
        } else {
            self.out.header_pos = self.out.header_len;
            self.out.body_pos += n - header_remaining.len;
        }

        return self.out.done();
    }

    /// Send file body via sendfile (large files only)
    pub fn sendFile(self: *Connection) !bool {
        if (self.file.remaining() == 0) return true;

        _ = try sys_fd.sendfile(self.fd, self.file.fd, &self.file.sent, self.file.remaining());
        return self.file.done();
    }

    pub fn close(self: *Connection) void {
        self.file.close();
        sys_fd.close(self.fd);
    }

    pub fn buffer(self: *Connection) []const u8 {
        return self.read_buf[0..self.read_pos];
    }

    /// Scratch buffer for response body.
    /// Lifetime: valid until response write completes.
    pub fn scratch(self: *Connection) []u8 {
        return &self.out.scratch;
    }

    pub fn hasFileBody(self: *Connection) bool {
        return self.file.active();
    }
};

// =============================================================================
// Tests
// =============================================================================

const testing = @import("std").testing;

test "init: default state is reading" {
    const conn = Connection.init(42);
    try testing.expectEqual(State.reading, conn.state);
    try testing.expectEqual(@as(i32, 42), conn.fd);
    try testing.expectEqual(@as(usize, 0), conn.read_pos);
    try testing.expectEqual(@as(usize, 0), conn.out.header_len);
    try testing.expectEqual(@as(usize, 0), conn.out.header_pos);
}

test "buffer: returns read data" {
    var conn = Connection.init(0);
    conn.read_buf[0] = 'H';
    conn.read_buf[1] = 'I';
    conn.read_pos = 2;
    try testing.expectEqualStrings("HI", conn.buffer());
}

test "buffer: empty when no data" {
    var conn = Connection.init(0);
    try testing.expectEqualStrings("", conn.buffer());
}

test "FileSend: active when fd >= 0" {
    var fs = FileSend{};
    try testing.expect(!fs.active());
    fs.fd = 5;
    try testing.expect(fs.active());
}

test "Outgoing: done when all sent" {
    var out = Outgoing{};
    try testing.expect(out.done());

    out.header_len = 10;
    try testing.expect(!out.done());

    out.header_pos = 10;
    try testing.expect(out.done());

    out.body_slice = "hello";
    try testing.expect(!out.done());

    out.body_pos = 5;
    try testing.expect(out.done());
}
