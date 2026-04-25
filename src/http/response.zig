// responsibility:
//   defines Response and serializes to bytes
//
// guarantees:
//   - pure function (serialize)
//   - writes to provided buffer
//   - no allocation
//
// non-goals:
//   - no I/O

pub const Status = @import("status.zig").Status;

pub const Body = union(enum) {
    slice: []const u8,
    file: struct {
        fd: i32,
        size: usize,
        owned: bool,
    },
};

pub const Response = struct {
    status: Status,
    body: Body,
    content_length: usize,
};

pub const bad_request: Response = .{
    .status = .bad_request,
    .body = .{ .slice = "Bad Request" },
    .content_length = "Bad Request".len,
};

// Status line templates (compile-time)
// Connection is a separate dimension, not encoded here.
const status_lines = struct {
    const @"200" = "HTTP/1.1 200 OK\r\nContent-Length: ";
    const @"400" = "HTTP/1.1 400 Bad Request\r\nContent-Length: ";
    const @"404" = "HTTP/1.1 404 Not Found\r\nContent-Length: ";
    const @"405" = "HTTP/1.1 405 Method Not Allowed\r\nContent-Length: ";

    inline fn get(status: Status) []const u8 {
        return switch (status) {
            .ok => @"200",
            .bad_request => @"400",
            .not_found => @"404",
            .method_not_allowed => @"405",
        };
    }
};

// Suffixes (keep-alive is hot path, close is cold)
const suffix_keepalive = "\r\n\r\n";
const suffix_close = "\r\nConnection: close\r\n\r\n";

/// Get status line for writev
pub inline fn getStatusLine(status: Status) []const u8 {
    return status_lines.get(status);
}

/// Get suffix for writev
pub inline fn getSuffix(close: bool) []const u8 {
    return if (close) suffix_close else suffix_keepalive;
}

/// Write integer to buffer (public for writev)
pub inline fn writeIntPublic(buf: *[20]u8, value: usize) usize {
    return writeInt(buf, value);
}

/// Serialize Response into bytes. Pure function.
/// close: if true, includes "Connection: close" header
/// NOTE: Only for slice body. File body uses serializeHeader + sendfile.
pub inline fn serialize(res: Response, out: []u8, close: bool) usize {
    // Hot path: keep-alive (99% of requests)
    // Cold path: close (only on error or max requests)
    if (close) {
        return serializeClose(res, out);
    } else {
        return serializeKeepAlive(res, out);
    }
}

/// Serialize header only (for file body, followed by sendfile).
pub inline fn serializeHeader(status: Status, content_length: usize, out: []u8, close: bool) usize {
    var pos: usize = 0;

    const status_line = status_lines.get(status);
    @memcpy(out[pos..][0..status_line.len], status_line);
    pos += status_line.len;

    pos += writeInt(out[pos..], content_length);

    const suffix = if (close) suffix_close else suffix_keepalive;
    @memcpy(out[pos..][0..suffix.len], suffix);
    pos += suffix.len;

    return pos;
}

/// Hot path: keep-alive (branch-free)
inline fn serializeKeepAlive(res: Response, out: []u8) usize {
    const body_slice = switch (res.body) {
        .slice => |s| s,
        .file => unreachable,
    };

    var pos: usize = 0;

    const status_line = status_lines.get(res.status);
    @memcpy(out[pos..][0..status_line.len], status_line);
    pos += status_line.len;

    pos += writeInt(out[pos..], res.content_length);

    @memcpy(out[pos..][0..suffix_keepalive.len], suffix_keepalive);
    pos += suffix_keepalive.len;

    @memcpy(out[pos..][0..body_slice.len], body_slice);
    pos += body_slice.len;

    return pos;
}

/// Cold path: close
inline fn serializeClose(res: Response, out: []u8) usize {
    const body_slice = switch (res.body) {
        .slice => |s| s,
        .file => unreachable,
    };

    var pos: usize = 0;

    const status_line = status_lines.get(res.status);
    @memcpy(out[pos..][0..status_line.len], status_line);
    pos += status_line.len;

    pos += writeInt(out[pos..], res.content_length);

    @memcpy(out[pos..][0..suffix_close.len], suffix_close);
    pos += suffix_close.len;

    @memcpy(out[pos..][0..body_slice.len], body_slice);
    pos += body_slice.len;

    return pos;
}

// Pre-computed strings for small Content-Length values (0-99)
const small_ints = blk: {
    var table: [100][2]u8 = undefined;
    for (0..100) |i| {
        if (i < 10) {
            table[i] = .{ '0' + @as(u8, @intCast(i)), 0 };
        } else {
            table[i] = .{
                '0' + @as(u8, @intCast(i / 10)),
                '0' + @as(u8, @intCast(i % 10)),
            };
        }
    }
    break :blk table;
};

inline fn writeInt(buf: []u8, value: usize) usize {
    // Fast path: small values (common for small responses)
    if (value < 100) {
        if (value < 10) {
            buf[0] = small_ints[value][0];
            return 1;
        } else {
            buf[0] = small_ints[value][0];
            buf[1] = small_ints[value][1];
            return 2;
        }
    }

    // General case
    var v = value;
    var len: usize = 0;
    var tmp: [20]u8 = undefined;

    while (v > 0) {
        tmp[len] = '0' + @as(u8, @intCast(v % 10));
        v /= 10;
        len += 1;
    }

    var i: usize = 0;
    while (i < len) : (i += 1) {
        buf[i] = tmp[len - 1 - i];
    }

    return len;
}

// =============================================================================
// Tests
// =============================================================================

const testing = @import("std").testing;

test "serialize: 200 OK with close" {
    var buf: [256]u8 = undefined;
    const res = Response{ .status = .ok, .body = .{ .slice = "Hello" }, .content_length = 5 };
    const len = serialize(res, &buf, true);

    try testing.expectEqualStrings(
        "HTTP/1.1 200 OK\r\nContent-Length: 5\r\nConnection: close\r\n\r\nHello",
        buf[0..len],
    );
}

test "serialize: 200 OK keep-alive" {
    var buf: [256]u8 = undefined;
    const res = Response{ .status = .ok, .body = .{ .slice = "Hello" }, .content_length = 5 };
    const len = serialize(res, &buf, false);

    try testing.expectEqualStrings(
        "HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\nHello",
        buf[0..len],
    );
}

test "serialize: 400 Bad Request" {
    var buf: [256]u8 = undefined;
    const len = serialize(bad_request, &buf, true);

    try testing.expectEqualStrings(
        "HTTP/1.1 400 Bad Request\r\nContent-Length: 11\r\nConnection: close\r\n\r\nBad Request",
        buf[0..len],
    );
}

test "serialize: 404 Not Found" {
    var buf: [256]u8 = undefined;
    const res = Response{ .status = .not_found, .body = .{ .slice = "Not Found" }, .content_length = 9 };
    const len = serialize(res, &buf, true);

    try testing.expectEqualStrings(
        "HTTP/1.1 404 Not Found\r\nContent-Length: 9\r\nConnection: close\r\n\r\nNot Found",
        buf[0..len],
    );
}

test "serialize: empty body" {
    var buf: [256]u8 = undefined;
    const res = Response{ .status = .ok, .body = .{ .slice = "" }, .content_length = 0 };
    const len = serialize(res, &buf, true);

    try testing.expectEqualStrings(
        "HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n",
        buf[0..len],
    );
}

test "serializeHeader: file response with keep-alive" {
    var buf: [256]u8 = undefined;
    const len = serializeHeader(.ok, 1234, &buf, false);

    try testing.expectEqualStrings(
        "HTTP/1.1 200 OK\r\nContent-Length: 1234\r\n\r\n",
        buf[0..len],
    );
}

test "serialize: head-style empty body preserves content-length" {
    var buf: [256]u8 = undefined;
    const res = Response{ .status = .ok, .body = .{ .slice = "" }, .content_length = 42 };
    const len = serialize(res, &buf, true);

    try testing.expectEqualStrings(
        "HTTP/1.1 200 OK\r\nContent-Length: 42\r\nConnection: close\r\n\r\n",
        buf[0..len],
    );
}

test "writeInt: zero" {
    var buf: [20]u8 = undefined;
    const len = writeInt(&buf, 0);
    try testing.expectEqualStrings("0", buf[0..len]);
}

test "writeInt: single digit" {
    var buf: [20]u8 = undefined;
    const len = writeInt(&buf, 5);
    try testing.expectEqualStrings("5", buf[0..len]);
}

test "writeInt: multiple digits" {
    var buf: [20]u8 = undefined;
    const len = writeInt(&buf, 12345);
    try testing.expectEqualStrings("12345", buf[0..len]);
}
