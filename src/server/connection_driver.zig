// responsibility:
//   advance connection state for writable events
//
// guarantees:
//   - reads connection state, advances it
//   - returns intent: keep driving, rearm for next request, or close
//   - does not touch epoll
//   - does not enforce policy (keep-alive limits live in the loop)
//
// non-goals:
//   - no I/O scheduling
//   - no protocol logic

const Connection = @import("connection.zig").Connection;

pub const Step = enum {
    again,
    rearm_read,
    close,
};

/// Advance the writing state by one writev.
/// On header+body completion, transitions to sending_file when a file body
/// remains, otherwise finishes the response.
pub fn driveWrite(conn: *Connection) !Step {
    const before_header = conn.out.header_pos;
    const before_body = conn.out.body_pos;

    if (try conn.writev()) {
        if (conn.hasFileBody()) {
            conn.state = .sending_file;
            return .again;
        }
        return finishResponse(conn);
    }

    if (conn.out.header_pos == before_header and conn.out.body_pos == before_body) {
        return error.NoProgress;
    }
    return .again;
}

/// Advance the sending_file state by one sendfile.
pub fn driveSendFile(conn: *Connection) !Step {
    if (try conn.sendFile()) {
        conn.file.close();
        return finishResponse(conn);
    }
    return .again;
}

/// Response complete. Reset for keep-alive or signal close.
fn finishResponse(conn: *Connection) Step {
    if (conn.keep_alive) {
        conn.reset();
        return .rearm_read;
    }
    return .close;
}
