// responsibility:
//   drives epoll loop and dispatches events
//
// guarantees:
//   - calls handler for each request
//   - manages connection lifecycle
//
// non-goals:
//   - no parsing logic
//   - no response generation

const Epoll = @import("../net/epoll.zig").Epoll;
const Event = @import("../net/epoll.zig").Event;
const Listener = @import("../net/listener.zig").Listener;
const socket = @import("../net/socket.zig");

const Connection = @import("connection.zig").Connection;
const parser = @import("../http/parser.zig");
const response = @import("../http/response.zig");
const handler = @import("../http/handler.zig");
const gate = @import("../http/gate.zig");

const Handler = handler.Handler;
const Context = handler.Context;
const Response = response.Response;
const Gate = gate.Gate;

const MAX_EVENTS = 128;
const MAX_CONNECTIONS = 64;

pub const Loop = struct {
    epoll: Epoll,
    listener: *Listener,
    handler: Handler,
    gates: []const Gate,
    connections: [MAX_CONNECTIONS]?Connection,

    pub fn init(listener: *Listener, gates: []const Gate, h: Handler) !Loop {
        var epoll = try Epoll.init();
        try epoll.add(listener.fd);

        return .{
            .epoll = epoll,
            .listener = listener,
            .handler = h,
            .gates = gates,
            .connections = [_]?Connection{null} ** MAX_CONNECTIONS,
        };
    }

    pub fn deinit(self: *Loop) void {
        self.epoll.deinit();
    }

    pub fn run(self: *Loop) void {
        var events: [MAX_EVENTS]Event = undefined;

        while (true) {
            const n = self.epoll.wait(&events);

            for (events[0..n]) |ev| {
                if (ev.data.fd == self.listener.fd) {
                    self.accept();
                } else {
                    self.handle(ev.data.fd);
                }
            }
        }
    }

    fn accept(self: *Loop) void {
        while (true) {
            const fd = self.listener.accept() catch return;
            if (fd == null) return;

            if (self.findSlot()) |slot| {
                slot.* = Connection.init(fd.?);
                self.epoll.add(fd.?) catch {
                    socket.close(fd.?);
                    slot.* = null;
                };
            } else {
                socket.close(fd.?);
            }
        }
    }

    fn handle(self: *Loop, fd: i32) void {
        const conn = self.findConnection(fd) orelse return;

        switch (conn.state) {
            .reading => self.handleRead(conn),
            .writing => self.handleWrite(conn),
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

        const req = parser.parse(conn.readSlice()) catch |err| switch (err) {
            error.Incomplete => return,
            else => {
                self.closeConnection(conn);
                return;
            },
        };

        // gates: pass or reject
        gate.apply(self.gates, req) catch {
            self.closeConnection(conn);
            return;
        };

        var ctx = Context{};
        const res = self.handler(&ctx, req) catch {
            self.closeConnection(conn);
            return;
        };

        const len = response.serialize(res, &conn.write_buf);

        conn.write_len = len;
        conn.write_pos = 0;
        conn.state = .writing;

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
        self.epoll.del(fd);
        conn.close();

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

    fn findConnection(self: *Loop, fd: i32) ?*Connection {
        for (&self.connections) |*slot| {
            if (slot.*) |*conn| {
                if (conn.fd == fd) return conn;
            }
        }
        return null;
    }
};
