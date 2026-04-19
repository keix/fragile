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

    pub fn serialize(self: Response, buf: []u8) []const u8 {
        var pos: usize = 0;

        // Status line
        const status_line = "HTTP/1.1 ";
        @memcpy(buf[pos..][0..status_line.len], status_line);
        pos += status_line.len;

        // Status code
        const code = @intFromEnum(self.status);
        buf[pos] = '0' + @as(u8, @intCast(code / 100));
        buf[pos + 1] = '0' + @as(u8, @intCast((code / 10) % 10));
        buf[pos + 2] = '0' + @as(u8, @intCast(code % 10));
        pos += 3;

        buf[pos] = ' ';
        pos += 1;

        const phrase = self.status.phrase();
        @memcpy(buf[pos..][0..phrase.len], phrase);
        pos += phrase.len;

        @memcpy(buf[pos..][0..2], "\r\n");
        pos += 2;

        // Content-Length
        const cl = "Content-Length: ";
        @memcpy(buf[pos..][0..cl.len], cl);
        pos += cl.len;

        pos += writeInt(buf[pos..], self.body.len);

        @memcpy(buf[pos..][0..2], "\r\n");
        pos += 2;

        // Connection close
        const conn = "Connection: close\r\n";
        @memcpy(buf[pos..][0..conn.len], conn);
        pos += conn.len;

        // End headers
        @memcpy(buf[pos..][0..2], "\r\n");
        pos += 2;

        // Body
        @memcpy(buf[pos..][0..self.body.len], self.body);
        pos += self.body.len;

        return buf[0..pos];
    }
};

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
