const std = @import("std");
const posix = std.posix;
const linux = std.os.linux;

const Connection = @import("connection.zig").Connection;
const parser = @import("../http/parser.zig");
const Response = @import("../http/response.zig").Response;

const MAX_EVENTS = 128;
const MAX_CONNECTIONS = 64;

pub const Loop = struct {
    epfd: posix.fd_t,
    listen_fd: posix.fd_t,
    connections: [MAX_CONNECTIONS]?Connection,

    pub fn init(listen_fd: posix.fd_t) !Loop {
        const epfd = try posix.epoll_create1(0);

        var ev = linux.epoll_event{
            .events = linux.EPOLL.IN,
            .data = .{ .fd = listen_fd },
        };
        try posix.epoll_ctl(epfd, linux.EPOLL.CTL_ADD, listen_fd, &ev);

        return .{
            .epfd = epfd,
            .listen_fd = listen_fd,
            .connections = [_]?Connection{null} ** MAX_CONNECTIONS,
        };
    }

    pub fn deinit(self: *Loop) void {
        posix.close(self.epfd);
    }

    pub fn run(self: *Loop) !void {
        var events: [MAX_EVENTS]linux.epoll_event = undefined;

        while (true) {
            const n = posix.epoll_wait(self.epfd, &events, -1);

            for (events[0..n]) |ev| {
                if (ev.data.fd == self.listen_fd) {
                    self.accept();
                } else {
                    self.handle(ev.data.fd);
                }
            }
        }
    }

    fn accept(self: *Loop) void {
        while (true) {
            const fd = posix.accept(
                self.listen_fd,
                null,
                null,
                posix.SOCK.NONBLOCK,
            ) catch |err| switch (err) {
                error.WouldBlock => return,
                else => return,
            };

            if (self.findSlot()) |slot| {
                slot.* = Connection.init(fd);

                var ev = linux.epoll_event{
                    .events = linux.EPOLL.IN,
                    .data = .{ .fd = fd },
                };
                posix.epoll_ctl(self.epfd, linux.EPOLL.CTL_ADD, fd, &ev) catch {
                    posix.close(fd);
                    slot.* = null;
                };
            } else {
                posix.close(fd);
            }
        }
    }

    fn handle(self: *Loop, fd: posix.fd_t) void {
        const conn = self.findConnection(fd) orelse return;

        switch (conn.state) {
            .reading => self.handleRead(conn),
            .writing => self.handleWrite(conn),
            .closing => self.closeConnection(conn),
        }
    }

    fn handleRead(self: *Loop, conn: *Connection) void {
        const n = conn.read() catch {
            self.closeConnection(conn);
            return;
        };

        if (n == 0) {
            self.closeConnection(conn);
            return;
        }

        const request = parser.parse(conn.readData()) catch |err| switch (err) {
            error.Incomplete => return,
            else => {
                self.closeConnection(conn);
                return;
            },
        };

        _ = request;

        var buf: [1024]u8 = undefined;
        const response = Response{
            .status = .ok,
            .body = "hello",
        };
        const data = response.serialize(&buf);
        conn.setResponse(data);

        self.handleWrite(conn);
    }

    fn handleWrite(self: *Loop, conn: *Connection) void {
        const done = conn.write() catch {
            self.closeConnection(conn);
            return;
        };

        if (done) {
            self.closeConnection(conn);
        }
    }

    fn closeConnection(self: *Loop, conn: *Connection) void {
        const fd = conn.fd;
        conn.close(self.epfd);

        for (&self.connections) |*slot| {
            if (slot.*) |*c| {
                if (c.fd == fd) {
                    slot.* = null;
                    return;
                }
            }
        }
    }

    fn findSlot(self: *Loop) ?*?Connection {
        for (&self.connections) |*slot| {
            if (slot.* == null) return slot;
        }
        return null;
    }

    fn findConnection(self: *Loop, fd: posix.fd_t) ?*Connection {
        for (&self.connections) |*slot| {
            if (slot.*) |*conn| {
                if (conn.fd == fd) return conn;
            }
        }
        return null;
    }
};
