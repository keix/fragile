const std = @import("std");
const Request = @import("request.zig").Request;
const Method = @import("request.zig").Method;

pub const ParseError = error{
    InvalidMethod,
    InvalidRequestLine,
    InvalidVersion,
    MissingHost,
    Incomplete,
};

/// Parse HTTP/1.1 request from raw bytes.
/// Pure function. No IO. No state.
pub fn parse(buf: []const u8) ParseError!Request {
    // Must have complete headers
    const header_end = std.mem.indexOf(u8, buf, "\r\n\r\n") orelse
        return error.Incomplete;

    const headers = buf[0..header_end];

    // Parse request line
    const line_end = std.mem.indexOf(u8, headers, "\r\n") orelse
        return error.InvalidRequestLine;

    const request_line = headers[0..line_end];

    // Method
    if (!std.mem.startsWith(u8, request_line, "GET "))
        return error.InvalidMethod;

    const after_method = request_line[4..];

    // Path
    const path_end = std.mem.indexOf(u8, after_method, " ") orelse
        return error.InvalidRequestLine;

    const path = after_method[0..path_end];
    const after_path = after_method[path_end + 1 ..];

    // Version
    if (!std.mem.eql(u8, after_path, "HTTP/1.1"))
        return error.InvalidVersion;

    // Host header
    const host = findHeader(headers, "Host") orelse
        return error.MissingHost;

    return Request{
        .method = .GET,
        .path = path,
        .host = host,
    };
}

fn findHeader(headers: []const u8, name: []const u8) ?[]const u8 {
    var iter = std.mem.splitSequence(u8, headers, "\r\n");
    _ = iter.next(); // skip request line

    while (iter.next()) |line| {
        if (line.len == 0) continue;

        const colon = std.mem.indexOf(u8, line, ":") orelse continue;
        const key = line[0..colon];

        if (std.ascii.eqlIgnoreCase(key, name)) {
            var value = line[colon + 1 ..];
            // trim leading space
            while (value.len > 0 and value[0] == ' ') {
                value = value[1..];
            }
            return value;
        }
    }
    return null;
}
