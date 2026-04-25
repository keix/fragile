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

const sys_fd = @import("../net/sys/fd.zig");

pub const State = enum {
    reading,
    writing,
    sending_file,
};

pub const Connection = struct {
    fd: i32,
    state: State,
    read_buf: [4096]u8,
    read_pos: usize,
    write_buf: [1024]u8,
    write_len: usize,
    write_pos: usize,
    keep_alive: bool,
    requests_served: usize,
    file_fd: i32,
    file_size: usize,
    file_sent: usize,
    file_owned: bool,
    write_armed: bool,

    pub fn init(fd: i32) Connection {
        return .{
            .fd = fd,
            .state = .reading,
            .read_buf = undefined,
            .read_pos = 0,
            .write_buf = undefined,
            .write_len = 0,
            .write_pos = 0,
            .keep_alive = true,
            .requests_served = 0,
            .file_fd = -1,
            .file_size = 0,
            .file_sent = 0,
            .file_owned = false,
            .write_armed = false,
        };
    }

    /// Reset for next request (keep-alive)
    pub fn reset(self: *Connection) void {
        self.closeFile();
        self.read_pos = 0;
        self.write_len = 0;
        self.write_pos = 0;
        self.file_size = 0;
        self.file_sent = 0;
        self.file_owned = false;
        self.write_armed = false;
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

    pub fn write(self: *Connection) !bool {
        const remaining = self.write_buf[self.write_pos..self.write_len];
        if (remaining.len == 0) return true;
        const n = try sys_fd.write(self.fd, remaining);
        self.write_pos += n;
        return self.write_pos >= self.write_len;
    }

    pub fn sendFile(self: *Connection) !bool {
        const remaining = self.file_size - self.file_sent;
        if (remaining == 0) return true;

        _ = try sys_fd.sendfile(self.fd, self.file_fd, &self.file_sent, remaining);
        return self.file_sent >= self.file_size;
    }

    pub fn closeFile(self: *Connection) void {
        if (self.file_fd >= 0 and self.file_owned) {
            sys_fd.close(self.file_fd);
        }
        self.file_fd = -1;
    }

    pub fn close(self: *Connection) void {
        self.closeFile();
        sys_fd.close(self.fd);
    }

    pub fn buffer(self: *Connection) []const u8 {
        return self.read_buf[0..self.read_pos];
    }

    /// Prepare response for writing (serialize into write buffer)
    pub fn prepareResponse(self: *Connection, res: response.Response, conn_close: bool) void {
        switch (res.body) {
            .slice => {
                self.write_len = response.serialize(res, &self.write_buf, conn_close);
                self.write_pos = 0;
                self.state = .writing;
            },
            .file => |f| {
                self.write_len = response.serializeHeader(res.status, res.content_length, &self.write_buf, conn_close);
                self.write_pos = 0;
                self.file_fd = f.fd;
                self.file_size = f.size;
                self.file_sent = 0;
                self.file_owned = f.owned;
                self.state = .writing;
            },
        }
    }

    pub fn hasFileBody(self: *Connection) bool {
        return self.file_fd >= 0;
    }
};

const response = @import("../http/response.zig");

// =============================================================================
// Tests
// =============================================================================

const testing = @import("std").testing;

test "init: default state is reading" {
    const conn = Connection.init(42);
    try testing.expectEqual(State.reading, conn.state);
    try testing.expectEqual(@as(i32, 42), conn.fd);
    try testing.expectEqual(@as(usize, 0), conn.read_pos);
    try testing.expectEqual(@as(usize, 0), conn.write_len);
    try testing.expectEqual(@as(usize, 0), conn.write_pos);
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
