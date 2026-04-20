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
//   - headers must be complete (\r\n\r\n present)
//   - body must match Content-Length
//
// non-goals:
//   - no ambiguity resolution
//   - no chunked encoding

const std = @import("std");
const request = @import("request.zig");

pub const Request = request.Request;
pub const Method = request.Method;
pub const Protocol = request.Protocol;
pub const Header = request.Header;

pub const Error = error{
    Incomplete,
    InvalidMethod,
    InvalidPath,
    InvalidProtocol,
    InvalidRequestLine,
    InvalidHeader,
    InvalidContentLength,
    MissingHost,
};

/// Parse HTTP/1.1 request. Pure function.
pub fn parse(buf: []const u8) Error!Request {
    // Find header end
    const header_end = std.mem.indexOf(u8, buf, "\r\n\r\n") orelse
        return error.Incomplete;

    const body_start = header_end + 4;

    // Parse request line
    const line_end = std.mem.indexOf(u8, buf[0..header_end], "\r\n") orelse
        return error.InvalidRequestLine;

    const method = parseMethod(buf[0..line_end]) orelse
        return error.InvalidMethod;

    const path = parsePath(buf[0..line_end]) orelse
        return error.InvalidPath;

    const protocol = parseProtocol(buf[0..line_end]) orelse
        return error.InvalidProtocol;

    // Parse headers
    const headers_buf = buf[line_end + 2 .. header_end];
    const host = findHeader(headers_buf, "Host") orelse
        return error.MissingHost;

    const content_length = parseContentLength(headers_buf) catch
        return error.InvalidContentLength;

    // Check body completeness
    const body_len = content_length orelse 0;
    if (buf.len < body_start + body_len)
        return error.Incomplete;

    const body = buf[body_start .. body_start + body_len];

    return .{
        .method = method,
        .path = path,
        .protocol = protocol,
        .host = host,
        .content_length = content_length,
        .body = body,
    };
}

fn parseMethod(line: []const u8) ?Method {
    if (std.mem.startsWith(u8, line, "GET ")) return .GET;
    if (std.mem.startsWith(u8, line, "POST ")) return .POST;
    return null;
}

fn parsePath(line: []const u8) ?[]const u8 {
    const start = std.mem.indexOf(u8, line, " ") orelse return null;
    const rest = line[start + 1 ..];
    const end = std.mem.indexOf(u8, rest, " ") orelse return null;

    const path = rest[0..end];
    if (path.len == 0 or path[0] != '/') return null;

    return path;
}

fn parseProtocol(line: []const u8) ?Protocol {
    if (std.mem.endsWith(u8, line, " HTTP/1.1")) return .http11;
    return null;
}

fn findHeader(headers: []const u8, name: []const u8) ?[]const u8 {
    var iter = std.mem.splitSequence(u8, headers, "\r\n");

    while (iter.next()) |line| {
        if (line.len == 0) continue;

        const colon = std.mem.indexOf(u8, line, ":") orelse continue;
        if (colon == 0) continue;

        const hdr_name = line[0..colon];
        if (!std.ascii.eqlIgnoreCase(hdr_name, name)) continue;

        if (colon + 2 > line.len) continue;
        if (line[colon + 1] != ' ') continue;

        return line[colon + 2 ..];
    }

    return null;
}

fn parseContentLength(headers: []const u8) !?usize {
    const value = findHeader(headers, "Content-Length") orelse
        return null;

    return std.fmt.parseInt(usize, value, 10) catch
        return error.InvalidContentLength;
}

/// Parse single header line (exported for gate use)
pub fn parseHeaderLine(line: []const u8) Error!Header {
    const colon = std.mem.indexOf(u8, line, ":") orelse
        return error.InvalidHeader;

    if (colon == 0)
        return error.InvalidHeader;

    if (colon + 2 > line.len)
        return error.InvalidHeader;

    if (line[colon + 1] != ' ')
        return error.InvalidHeader;

    return .{
        .name = line[0..colon],
        .value = line[colon + 2 ..],
    };
}
