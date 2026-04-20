// responsibility:
//   transforms bytes into Request
//
// guarantees:
//   - pure function
//   - no allocation
//   - no I/O
//   - rejects invalid input
//
// constraints:
//   - input must be complete (\r\n\r\n present)
//
// non-goals:
//   - no ambiguity resolution
//   - no partial parsing

const std = @import("std");
const request = @import("request.zig");

pub const Request = request.Request;
pub const RequestLine = request.RequestLine;
pub const Method = request.Method;
pub const Protocol = request.Protocol;

pub const Error = error{
    Incomplete,
    InvalidMethod,
    InvalidPath,
    InvalidProtocol,
    InvalidRequestLine,
    InvalidHeader,
    MissingHost,
};

/// Parse HTTP/1.1 request. Pure function.
pub fn parse(buf: []const u8) Error!Request {
    const header_end = std.mem.indexOf(u8, buf, "\r\n\r\n") orelse
        return error.Incomplete;

    const line_end = std.mem.indexOf(u8, buf[0..header_end], "\r\n") orelse
        return error.InvalidRequestLine;

    const rl = try parseRequestLine(buf[0..line_end]);

    const headers_start = line_end + 2;
    const host = try findHost(buf[headers_start..header_end]);

    return .{
        .method = rl.method,
        .path = rl.path,
        .protocol = rl.protocol,
        .host = host,
    };
}

/// Parse request line: "METHOD SP PATH SP VERSION"
/// Strict. One SP. Exact match.
pub fn parseRequestLine(line: []const u8) Error!RequestLine {
    // Method
    const method_end = std.mem.indexOf(u8, line, " ") orelse
        return error.InvalidMethod;

    const method = parseMethod(line[0..method_end]) orelse
        return error.InvalidMethod;

    // Must be exactly one SP
    if (method_end + 1 >= line.len)
        return error.InvalidPath;

    const after_method = line[method_end + 1 ..];

    // Path
    const path_end = std.mem.indexOf(u8, after_method, " ") orelse
        return error.InvalidPath;

    if (path_end == 0)
        return error.InvalidPath;

    const path = after_method[0..path_end];

    // Path must start with /
    if (path[0] != '/')
        return error.InvalidPath;

    // Must be exactly one SP
    if (path_end + 1 >= after_method.len)
        return error.InvalidProtocol;

    const protocol_str = after_method[path_end + 1 ..];

    // Protocol must be exactly "HTTP/1.1"
    const protocol = parseProtocol(protocol_str) orelse
        return error.InvalidProtocol;

    return .{
        .method = method,
        .path = path,
        .protocol = protocol,
    };
}

fn parseMethod(s: []const u8) ?Method {
    if (std.mem.eql(u8, s, "GET")) return .GET;
    return null;
}

fn parseProtocol(s: []const u8) ?Protocol {
    if (std.mem.eql(u8, s, "HTTP/1.1")) return .http11;
    return null;
}

pub const Header = struct {
    name: []const u8,
    value: []const u8,
};

/// Parse header line: "Name: value"
/// Strict. Colon required. Exactly one SP after colon.
pub fn parseHeaderLine(line: []const u8) Error!Header {
    // Find colon
    const colon = std.mem.indexOf(u8, line, ":") orelse
        return error.InvalidHeader;

    // Name must not be empty
    if (colon == 0)
        return error.InvalidHeader;

    const name = line[0..colon];

    // Must have SP after colon
    if (colon + 1 >= line.len)
        return error.InvalidHeader;

    if (line[colon + 1] != ' ')
        return error.InvalidHeader;

    // Value starts after ": "
    const value = line[colon + 2 ..];

    return .{
        .name = name,
        .value = value,
    };
}

fn findHost(headers: []const u8) Error![]const u8 {
    var iter = std.mem.splitSequence(u8, headers, "\r\n");

    while (iter.next()) |line| {
        if (line.len == 0) continue;

        const header = try parseHeaderLine(line);

        if (std.ascii.eqlIgnoreCase(header.name, "Host")) {
            if (header.value.len == 0)
                return error.MissingHost;

            return header.value;
        }
    }

    return error.MissingHost;
}
