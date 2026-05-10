// responsibility:
//   transforms Response into connection write state
//
// guarantees:
//   - knows HTTP response format
//   - prepares header and body for Connection
//   - does not perform I/O
//   - does not advance the connection state machine
//
// non-goals:
//   - no socket operations
//   - no state machine transitions

const std = @import("std");
const Connection = @import("connection.zig").Connection;
const response = @import("../http/response.zig");
const Response = response.Response;

/// Prepare connection output buffers for writing a response.
/// Does not change connection state. Caller advances state machine.
///
/// - slice body: header + body sent via writev
/// - file body: header sent via writev, body sent via sendfile
pub fn prepare(conn: *Connection, res: Response, conn_close: bool) void {
    std.debug.assert(!conn.file.active());

    conn.out.header_len = response.serializeHeader(
        res.status,
        res.content_length,
        &conn.out.header_buf,
        conn_close,
    );
    conn.out.header_pos = 0;

    switch (res.body) {
        .slice => |s| {
            conn.out.body_slice = s;
            conn.out.body_pos = 0;
        },
        .file => |f| {
            conn.out.body_slice = &.{};
            conn.out.body_pos = 0;
            conn.file = .{
                .fd = f.fd,
                .size = f.size,
                .sent = 0,
                .owned = f.owned,
            };
        },
    }
}
