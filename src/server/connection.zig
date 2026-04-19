const posix = @import("std").posix;
const linux = @import("std").os.linux;

pub const State = enum {
    reading,
    writing,
    closing,
};

pub const Connection = struct {
    fd: posix.fd_t,
    state: State,
    read_buf: [2048]u8,
    read_pos: usize,
    write_buf: [1024]u8,
    write_len: usize,
    write_pos: usize,

    pub fn init(fd: posix.fd_t) Connection {
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
        const n = try posix.read(
            self.fd,
            self.read_buf[self.read_pos..],
        );
        self.read_pos += n;
        return n;
    }

    pub fn write(self: *Connection) !bool {
        const remaining = self.write_buf[self.write_pos..self.write_len];
        const n = try posix.write(self.fd, remaining);
        self.write_pos += n;
        return self.write_pos >= self.write_len;
    }

    pub fn readData(self: *Connection) []const u8 {
        return self.read_buf[0..self.read_pos];
    }

    pub fn setResponse(self: *Connection, data: []const u8) void {
        @memcpy(self.write_buf[0..data.len], data);
        self.write_len = data.len;
        self.write_pos = 0;
        self.state = .writing;
    }

    pub fn close(self: *Connection, epfd: posix.fd_t) void {
        posix.epoll_ctl(epfd, linux.EPOLL.CTL_DEL, self.fd, null) catch {};
        posix.close(self.fd);
    }
};
