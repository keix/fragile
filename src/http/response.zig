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

pub const Status = enum(u16) {
    ok = 200,
    bad_request = 400,
    not_found = 404,

    pub fn phrase(self: Status) []const u8 {
        return switch (self) {
            .ok => "OK",
            .bad_request => "Bad Request",
            .not_found => "Not Found",
        };
    }
};

pub const Response = struct {
    status: Status,
    body: []const u8,
};

pub const bad_request: Response = .{
    .status = .bad_request,
    .body = "Bad Request",
};

/// Serialize Response into bytes. Pure function.
pub fn serialize(res: Response, out: []u8) usize {
    var pos: usize = 0;

    // Status line
    const status_line = "HTTP/1.1 ";
    @memcpy(out[pos..][0..status_line.len], status_line);
    pos += status_line.len;

    // Status code
    const code = @intFromEnum(res.status);
    out[pos] = '0' + @as(u8, @intCast(code / 100));
    out[pos + 1] = '0' + @as(u8, @intCast((code / 10) % 10));
    out[pos + 2] = '0' + @as(u8, @intCast(code % 10));
    pos += 3;

    out[pos] = ' ';
    pos += 1;

    const phrase = res.status.phrase();
    @memcpy(out[pos..][0..phrase.len], phrase);
    pos += phrase.len;

    @memcpy(out[pos..][0..2], "\r\n");
    pos += 2;

    // Content-Length
    const cl = "Content-Length: ";
    @memcpy(out[pos..][0..cl.len], cl);
    pos += cl.len;

    pos += writeInt(out[pos..], res.body.len);

    @memcpy(out[pos..][0..2], "\r\n");
    pos += 2;

    // Connection close
    const conn_hdr = "Connection: close\r\n";
    @memcpy(out[pos..][0..conn_hdr.len], conn_hdr);
    pos += conn_hdr.len;

    // End headers
    @memcpy(out[pos..][0..2], "\r\n");
    pos += 2;

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
