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
};

pub const Connection = struct {
    fd: i32,
    state: State,
    read_buf: [2048]u8,
    read_pos: usize,
    write_buf: [1024]u8,
    write_len: usize,
    write_pos: usize,

    pub fn init(fd: i32) Connection {
        return .{
            .fd = fd,
            .state = .reading,
            .read_buf = undefined,
            .read_pos = 0,
            .write_buf = undefined,
            .write_len = 0,
            .write_pos = 0,
        };
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
        const n = try sys_fd.write(self.fd, remaining);
        self.write_pos += n;
        return self.write_pos >= self.write_len;
    }

    pub fn close(self: *Connection) void {
        sys_fd.close(self.fd);
    }

    pub fn buffer(self: *Connection) []const u8 {
        return self.read_buf[0..self.read_pos];
    }
};
