// responsibility:
//   drives epoll loop and dispatches events
//
// guarantees:
//   - manages connection lifecycle
//   - dispatches parsed requests to gates and handler
//   - defines event policy (IN | HUP | ERR)
//   - defines timeout policy (blocking)
//
// non-goals:
//   - no parsing logic
//   - no response generation

const std = @import("std");

const epoll = @import("../net/sys/epoll.zig");
const Epoll = epoll.Epoll;
const Event = epoll.Event;
const EPOLL = epoll.EPOLL;

const Listener = @import("../net/listener.zig").Listener;
const sys_fd = @import("../net/sys/fd.zig");

const Connection = @import("connection.zig").Connection;
const parser = @import("../http/parser.zig");
const response = @import("../http/response.zig");
const handler = @import("../http/handler.zig");
const gate = @import("../http/gate.zig");

const Handler = handler.Handler;
const Context = handler.Context;
const Response = response.Response;
const Gate = gate.Gate;

const MAX_EVENTS = 2048;
const MAX_CONNECTIONS = 2048;
const MAX_REQUESTS_PER_CONN = 800;

pub const Loop = struct {
    epoll: Epoll,
    listener: *Listener,
    handler: Handler,
    gates: []const Gate,
    ctx: Context,
    connections: [MAX_CONNECTIONS]?Connection,

    const READ_EVENTS = EPOLL.IN | EPOLL.HUP | EPOLL.ERR;
    const WRITE_EVENTS = EPOLL.OUT | EPOLL.HUP | EPOLL.ERR;

    pub fn init(listener: *Listener, gates: []const Gate, h: Handler, ctx: Context) !Loop {
        var ep = try Epoll.init();
        try ep.add(listener.fd, READ_EVENTS);

        return .{
            .epoll = ep,
            .listener = listener,
            .handler = h,
            .gates = gates,
            .ctx = ctx,
            .connections = [_]?Connection{null} ** MAX_CONNECTIONS,
        };
    }

    pub fn deinit(self: *Loop) void {
        self.epoll.deinit();
    }

    pub fn run(self: *Loop) void {
        var events: [MAX_EVENTS]Event = undefined;

        while (true) {
            const n = self.waitEvents(&events);

            for (events[0..n]) |ev| {
                if (ev.data.fd == self.listener.fd) {
                    self.accept();
                } else {
                    self.handle(ev.data.fd);
                }
            }
        }
    }

    fn waitEvents(self: *Loop, events: []Event) usize {
        return self.epoll.wait(events, -1);
    }

    fn accept(self: *Loop) void {
        while (true) {
            const fd = self.listener.accept() catch return;
            if (fd == null) return;

            if (self.findSlot()) |slot| {
                slot.* = Connection.init(fd.?);
                self.epoll.add(fd.?, READ_EVENTS) catch {
                    sys_fd.close(fd.?);
                    slot.* = null;
                };
            } else {
                sys_fd.close(fd.?);
            }
        }
    }

    fn handle(self: *Loop, fd: i32) void {
        const conn = self.findConnection(fd) orelse return;

        switch (conn.state) {
            .reading => self.handleRead(conn),
            .writing => self.handleWrite(conn),
            .sending_file => self.handleSendFile(conn),
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

        const req = parser.parse(conn.buffer()) catch |err| switch (err) {
            error.Incomplete => return,
            else => {
                self.sendError(conn);
                return;
            },
        };

        // gates: pass or reject
        gate.apply(self.gates, req) catch {
            self.sendError(conn);
            return;
        };

        // Update keep-alive state (HTTP/1.1 defaults to keep-alive)
        // Note: minimal parsing - "close, upgrade" won't be detected
        conn.keep_alive = if (parser.findHeader(req.headers, "Connection")) |val|
            !std.ascii.eqlIgnoreCase(val, "close")
        else
            true;
        conn.requests_served += 1;

        const res = self.handler(&self.ctx, req) catch {
            self.closeConnection(conn);
            return;
        };

        self.sendResponse(conn, res);
    }

    fn handleWrite(self: *Loop, conn: *Connection) void {
        while (true) {
            const before = conn.write_pos;
            const done = conn.write() catch |err| switch (err) {
                error.WouldBlock => {
                    self.armWrite(conn);
                    return;
                },
                else => {
                    self.closeConnection(conn);
                    return;
                },
            };

            if (!done and conn.write_pos == before) {
                self.closeConnection(conn);
                return;
            }

            if (!done) continue;

            if (conn.hasFileBody()) {
                conn.state = .sending_file;
                self.handleSendFile(conn);
            } else {
                self.finishResponse(conn);
            }
            return;
        }
    }

    fn handleSendFile(self: *Loop, conn: *Connection) void {
        while (true) {
            const done = conn.sendFile() catch |err| switch (err) {
                error.WouldBlock => {
                    self.armWrite(conn);
                    return;
                },
                else => {
                    self.closeConnection(conn);
                    return;
                },
            };

            if (done) {
                conn.closeFile();
                self.finishResponse(conn);
                return;
            }
        }
    }

    fn finishResponse(self: *Loop, conn: *Connection) void {
        if (conn.keep_alive and conn.requests_served < MAX_REQUESTS_PER_CONN) {
            self.armRead(conn) catch {
                self.closeConnection(conn);
                return;
            };
            conn.reset();
        } else {
            self.closeConnection(conn);
        }
    }

    fn sendResponse(self: *Loop, conn: *Connection, res: Response) void {
        const close = !conn.keep_alive or conn.requests_served >= MAX_REQUESTS_PER_CONN;
        conn.prepareResponse(res, close);
        self.handleWrite(conn);
    }

    fn armWrite(self: *Loop, conn: *Connection) void {
        if (conn.write_armed) return;
        self.epoll.mod(conn.fd, WRITE_EVENTS) catch {
            self.closeConnection(conn);
            return;
        };
        conn.write_armed = true;
    }

    fn armRead(self: *Loop, conn: *Connection) !void {
        if (!conn.write_armed) return;
        try self.epoll.mod(conn.fd, READ_EVENTS);
        conn.write_armed = false;
    }

    fn sendError(self: *Loop, conn: *Connection) void {
        conn.keep_alive = false; // Always close on error
        self.sendResponse(conn, response.bad_request);
    }

    fn closeConnection(self: *Loop, conn: *Connection) void {
        const fd = conn.fd;
        self.epoll.del(fd) catch {};
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
