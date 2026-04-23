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

const std = @import("std");
const posix = std.posix;

pub const Status = @import("status.zig").Status;

pub const Response = struct {
    status: Status,
    body: []const u8,
};

pub const bad_request: Response = .{
    .status = .bad_request,
    .body = "Bad Request",
};

// Static templates for writev (compile-time)
pub const Template = struct {
    prefix: []const u8,
    suffix: []const u8,
};

pub const templates = struct {
    pub const @"200" = Template{
        .prefix = "HTTP/1.1 200 OK\r\nContent-Length: ",
        .suffix = "\r\nConnection: close\r\n\r\n",
    };
    pub const @"400" = Template{
        .prefix = "HTTP/1.1 400 Bad Request\r\nContent-Length: ",
        .suffix = "\r\nConnection: close\r\n\r\n",
    };
    pub const @"404" = Template{
        .prefix = "HTTP/1.1 404 Not Found\r\nContent-Length: ",
        .suffix = "\r\nConnection: close\r\n\r\n",
    };

    pub fn get(status: Status) Template {
        return switch (status) {
            .ok => @"200",
            .bad_request => @"400",
            .not_found => @"404",
        };
    }
};

/// Prepare iovecs for writev. Returns number of iovecs used.
pub fn prepareIovecs(
    res: Response,
    iovecs: *[4]posix.iovec_const,
    len_buf: *[20]u8,
) usize {
    const tmpl = templates.get(res.status);
    const len_size = writeInt(len_buf, res.body.len);

    iovecs[0] = .{ .base = tmpl.prefix.ptr, .len = tmpl.prefix.len };
    iovecs[1] = .{ .base = len_buf, .len = len_size };
    iovecs[2] = .{ .base = tmpl.suffix.ptr, .len = tmpl.suffix.len };
    iovecs[3] = .{ .base = res.body.ptr, .len = res.body.len };

    return 4;
}

/// Serialize Response into bytes. Pure function.
/// Uses precomputed templates for efficiency.
pub fn serialize(res: Response, out: []u8) usize {
    const tmpl = templates.get(res.status);
    var pos: usize = 0;

    // Prefix: "HTTP/1.1 XXX Phrase\r\nContent-Length: "
    @memcpy(out[pos..][0..tmpl.prefix.len], tmpl.prefix);
    pos += tmpl.prefix.len;

    // Content-Length value
    pos += writeInt(out[pos..], res.body.len);

    // Suffix: "\r\nConnection: close\r\n\r\n"
    @memcpy(out[pos..][0..tmpl.suffix.len], tmpl.suffix);
    pos += tmpl.suffix.len;

    // Body
    @memcpy(out[pos..][0..res.body.len], res.body);
    pos += res.body.len;

    return pos;
}

fn writeInt(buf: []u8, value: usize) usize {
    if (value == 0) {
        buf[0] = '0';
        return 1;
    }

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

test "serialize: 200 OK with body" {
    var buf: [256]u8 = undefined;
    const res = Response{ .status = .ok, .body = "Hello" };
    const len = serialize(res, &buf);

    try testing.expectEqualStrings(
        "HTTP/1.1 200 OK\r\nContent-Length: 5\r\nConnection: close\r\n\r\nHello",
        buf[0..len],
    );
}

test "serialize: 400 Bad Request" {
    var buf: [256]u8 = undefined;
    const len = serialize(bad_request, &buf);

    try testing.expectEqualStrings(
        "HTTP/1.1 400 Bad Request\r\nContent-Length: 11\r\nConnection: close\r\n\r\nBad Request",
        buf[0..len],
    );
}

test "serialize: 404 Not Found" {
    var buf: [256]u8 = undefined;
    const res = Response{ .status = .not_found, .body = "Not Found" };
    const len = serialize(res, &buf);

    try testing.expectEqualStrings(
        "HTTP/1.1 404 Not Found\r\nContent-Length: 9\r\nConnection: close\r\n\r\nNot Found",
        buf[0..len],
    );
}

test "serialize: empty body" {
    var buf: [256]u8 = undefined;
    const res = Response{ .status = .ok, .body = "" };
    const len = serialize(res, &buf);

    try testing.expectEqualStrings(
        "HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n",
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
