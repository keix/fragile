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
const request = @import("../request.zig");

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
    DuplicateHost,
    DuplicateContentLength,
    TransferEncodingNotSupported,
    ObsoleteLineFolding,
};

/// Parse HTTP/1.1 request. Pure function.
pub fn parse(buf: []const u8) Error!Request {
    // Find header end
    const header_end = std.mem.indexOf(u8, buf, "\r\n\r\n") orelse
        return error.Incomplete;

    const body_start = header_end + 4;

    // Parse request line (search up to header_end + 2 to include first \r\n)
    const line_end = std.mem.indexOf(u8, buf[0 .. header_end + 2], "\r\n") orelse
        return error.InvalidRequestLine;

    const method = parseMethod(buf[0..line_end]) orelse
        return error.InvalidMethod;

    const path = parsePath(buf[0..line_end]) orelse
        return error.InvalidPath;

    const protocol = parseProtocol(buf[0..line_end]) orelse
        return error.InvalidProtocol;

    // Parse headers (may be empty if line_end + 2 >= header_end)
    const headers_buf = if (line_end + 2 < header_end)
        buf[line_end + 2 .. header_end]
    else
        "";

    // Host: required, no duplicates
    if (countHeader(headers_buf, "Host") > 1)
        return error.DuplicateHost;
    const host = findHeader(headers_buf, "Host") orelse
        return error.MissingHost;

    // Content-Length: no duplicates
    if (countHeader(headers_buf, "Content-Length") > 1)
        return error.DuplicateContentLength;
    const content_length = parseContentLength(headers_buf) catch
        return error.InvalidContentLength;

    // Transfer-Encoding: not supported
    if (findHeader(headers_buf, "Transfer-Encoding") != null)
        return error.TransferEncodingNotSupported;

    // Reject obsolete line folding (lines starting with SP or HTAB)
    if (hasLineFolding(headers_buf))
        return error.ObsoleteLineFolding;

    // Reject body without Content-Length
    if (buf.len > body_start and content_length == null)
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
    const end = std.mem.indexOf(u8, line, " ") orelse return null;
    const m = line[0..end];

    if (std.mem.eql(u8, m, "GET")) return .GET;
    if (std.mem.eql(u8, m, "HEAD")) return .HEAD;
    if (std.mem.eql(u8, m, "POST")) return .POST;
    if (std.mem.eql(u8, m, "PUT")) return .PUT;
    if (std.mem.eql(u8, m, "DELETE")) return .DELETE;
    if (std.mem.eql(u8, m, "CONNECT")) return .CONNECT;
    if (std.mem.eql(u8, m, "OPTIONS")) return .OPTIONS;
    if (std.mem.eql(u8, m, "TRACE")) return .TRACE;

    return null;
}

fn parsePath(line: []const u8) ?[]const u8 {
    const start = std.mem.indexOf(u8, line, " ") orelse return null;
    const rest = line[start + 1 ..];

    // reject consecutive spaces (e.g. "GET  /")
    if (rest.len == 0 or rest[0] == ' ') return null;

    const end = std.mem.indexOf(u8, rest, " ") orelse return null;

    // reject consecutive spaces before protocol (e.g. "GET /  HTTP/1.1")
    if (end + 1 < rest.len and rest[end + 1] == ' ') return null;

    const path = rest[0..end];
    if (path[0] != '/') return null;

    // path must contain only visible ASCII (%x21-7E)
    if (!isVisibleAscii(path)) return null;

    return path;
}

fn parseProtocol(line: []const u8) ?Protocol {
    const last_space = std.mem.lastIndexOf(u8, line, " ") orelse return null;
    const proto = line[last_space + 1 ..];

    if (std.mem.eql(u8, proto, "HTTP/1.1")) return .http11;

    return null;
}

fn findHeader(headers: []const u8, name: []const u8) ?[]const u8 {
    var iter = std.mem.splitSequence(u8, headers, "\r\n");

    while (iter.next()) |line| {
        if (line.len == 0) continue;

        const colon = std.mem.indexOf(u8, line, ":") orelse continue;
        if (colon == 0) continue;

        const header_name = line[0..colon];

        // field-name must be visible ASCII (%x21-7E)
        if (!isVisibleAscii(header_name)) continue;

        if (!std.ascii.eqlIgnoreCase(header_name, name)) continue;

        if (colon + 2 > line.len) continue;
        if (line[colon + 1] != ' ') continue;

        const value = line[colon + 2 ..];

        // field-value must be printable ASCII (%x20-7E)
        if (!isPrintableAscii(value)) continue;

        return value;
    }

    return null;
}

fn countHeader(headers: []const u8, name: []const u8) usize {
    var iter = std.mem.splitSequence(u8, headers, "\r\n");
    var count: usize = 0;

    while (iter.next()) |line| {
        if (line.len == 0) continue;

        const colon = std.mem.indexOf(u8, line, ":") orelse continue;
        if (colon == 0) continue;

        const header_name = line[0..colon];
        if (std.ascii.eqlIgnoreCase(header_name, name)) count += 1;
    }

    return count;
}

fn parseContentLength(headers: []const u8) !?usize {
    const value = findHeader(headers, "Content-Length") orelse
        return null;

    return std.fmt.parseInt(usize, value, 10) catch
        return error.InvalidContentLength;
}

fn hasLineFolding(headers: []const u8) bool {
    var iter = std.mem.splitSequence(u8, headers, "\r\n");

    while (iter.next()) |line| {
        if (line.len == 0) continue;
        // Line folding: line starts with SP or HTAB
        if (line[0] == ' ' or line[0] == '\t') return true;
    }

    return false;
}

/// Visible ASCII: %x21-7E (! to ~)
fn isVisibleAscii(s: []const u8) bool {
    for (s) |c| {
        if (c < 0x21 or c > 0x7E) return false;
    }
    return true;
}

/// Printable ASCII: %x20-7E (space to ~)
fn isPrintableAscii(s: []const u8) bool {
    for (s) |c| {
        if (c < 0x20 or c > 0x7E) return false;
    }
    return true;
}

/// Parse single header line (exported for gate use)
pub fn parseHeaderLine(line: []const u8) Error!Header {
    const colon = std.mem.indexOf(u8, line, ":") orelse
        return error.InvalidHeader;

    if (colon == 0)
        return error.InvalidHeader;

    const header_name = line[0..colon];

    // field-name must be visible ASCII (%x21-7E)
    if (!isVisibleAscii(header_name))
        return error.InvalidHeader;

    if (colon + 2 > line.len)
        return error.InvalidHeader;

    if (line[colon + 1] != ' ')
        return error.InvalidHeader;

    const value = line[colon + 2 ..];

    // field-value must be printable ASCII (%x20-7E)
    if (!isPrintableAscii(value))
        return error.InvalidHeader;

    return .{
        .name = header_name,
        .value = value,
    };
}

// =============================================================================
// Tests
// =============================================================================

const testing = std.testing;

// -- Request Line --

test "request line: valid minimal" {
    const req = try parse("GET / HTTP/1.1\r\nHost: x\r\n\r\n");
    try testing.expectEqual(Method.GET, req.method);
    try testing.expectEqualStrings("/", req.path);
    try testing.expectEqual(Protocol.http11, req.protocol);
}

test "request line: reject consecutive SP after method" {
    try testing.expectError(error.InvalidPath, parse("GET  / HTTP/1.1\r\nHost: x\r\n\r\n"));
}

test "request line: reject consecutive SP before protocol" {
    try testing.expectError(error.InvalidPath, parse("GET /  HTTP/1.1\r\nHost: x\r\n\r\n"));
}

// -- Method --

test "method: all RFC 9110 methods" {
    const methods = [_]struct { []const u8, Method }{
        .{ "GET", .GET },
        .{ "HEAD", .HEAD },
        .{ "POST", .POST },
        .{ "PUT", .PUT },
        .{ "DELETE", .DELETE },
        .{ "CONNECT", .CONNECT },
        .{ "OPTIONS", .OPTIONS },
        .{ "TRACE", .TRACE },
    };

    for (methods) |m| {
        var buf: [64]u8 = undefined;
        const line = std.fmt.bufPrint(&buf, "{s} / HTTP/1.1\r\nHost: x\r\n\r\n", .{m[0]}) catch unreachable;
        const req = try parse(line);
        try testing.expectEqual(m[1], req.method);
    }
}

test "method: reject unknown" {
    try testing.expectError(error.InvalidMethod, parse("INVALID / HTTP/1.1\r\nHost: x\r\n\r\n"));
}

test "method: reject lowercase" {
    try testing.expectError(error.InvalidMethod, parse("get / HTTP/1.1\r\nHost: x\r\n\r\n"));
}

// -- Path --

test "path: root" {
    const req = try parse("GET / HTTP/1.1\r\nHost: x\r\n\r\n");
    try testing.expectEqualStrings("/", req.path);
}

test "path: with segments" {
    const req = try parse("GET /foo/bar HTTP/1.1\r\nHost: x\r\n\r\n");
    try testing.expectEqualStrings("/foo/bar", req.path);
}

test "path: with query" {
    const req = try parse("GET /search?q=test HTTP/1.1\r\nHost: x\r\n\r\n");
    try testing.expectEqualStrings("/search?q=test", req.path);
}

test "path: reject not starting with slash" {
    try testing.expectError(error.InvalidPath, parse("GET foo HTTP/1.1\r\nHost: x\r\n\r\n"));
}

// -- Protocol --

test "protocol: HTTP/1.1" {
    const req = try parse("GET / HTTP/1.1\r\nHost: x\r\n\r\n");
    try testing.expectEqual(Protocol.http11, req.protocol);
}

test "protocol: reject HTTP/1.0" {
    try testing.expectError(error.InvalidProtocol, parse("GET / HTTP/1.0\r\nHost: x\r\n\r\n"));
}

test "protocol: reject HTTP/2" {
    try testing.expectError(error.InvalidProtocol, parse("GET / HTTP/2\r\nHost: x\r\n\r\n"));
}

// -- Host Header --

test "host: required" {
    try testing.expectError(error.MissingHost, parse("GET / HTTP/1.1\r\n\r\n"));
}

test "host: valid" {
    const req = try parse("GET / HTTP/1.1\r\nHost: example.com\r\n\r\n");
    try testing.expectEqualStrings("example.com", req.host);
}

test "host: reject duplicate" {
    try testing.expectError(error.DuplicateHost, parse("GET / HTTP/1.1\r\nHost: a\r\nHost: b\r\n\r\n"));
}

// -- Content-Length --

test "content-length: absent is null" {
    const req = try parse("GET / HTTP/1.1\r\nHost: x\r\n\r\n");
    try testing.expectEqual(@as(?usize, null), req.content_length);
}

test "content-length: zero" {
    const req = try parse("POST / HTTP/1.1\r\nHost: x\r\nContent-Length: 0\r\n\r\n");
    try testing.expectEqual(@as(?usize, 0), req.content_length);
}

test "content-length: with body" {
    const req = try parse("POST / HTTP/1.1\r\nHost: x\r\nContent-Length: 4\r\n\r\ntest");
    try testing.expectEqual(@as(?usize, 4), req.content_length);
    try testing.expectEqualStrings("test", req.body);
}

test "content-length: reject duplicate" {
    try testing.expectError(error.DuplicateContentLength, parse(
        "POST / HTTP/1.1\r\nHost: x\r\nContent-Length: 0\r\nContent-Length: 0\r\n\r\n",
    ));
}

test "content-length: reject non-numeric" {
    try testing.expectError(error.InvalidContentLength, parse(
        "POST / HTTP/1.1\r\nHost: x\r\nContent-Length: abc\r\n\r\n",
    ));
}

test "content-length: reject body without header" {
    try testing.expectError(error.InvalidContentLength, parse(
        "POST / HTTP/1.1\r\nHost: x\r\n\r\nbody",
    ));
}

// -- Incomplete --

test "incomplete: no header terminator" {
    try testing.expectError(error.Incomplete, parse("GET / HTTP/1.1\r\nHost: x"));
}

test "incomplete: body shorter than content-length" {
    try testing.expectError(error.Incomplete, parse(
        "POST / HTTP/1.1\r\nHost: x\r\nContent-Length: 10\r\n\r\nshort",
    ));
}

// -- Transfer-Encoding --

test "transfer-encoding: reject chunked" {
    try testing.expectError(error.TransferEncodingNotSupported, parse(
        "POST / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\n\r\n",
    ));
}

test "transfer-encoding: reject any value" {
    try testing.expectError(error.TransferEncodingNotSupported, parse(
        "GET / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: gzip\r\n\r\n",
    ));
}

// -- Line Folding --

test "line folding: reject SP continuation" {
    try testing.expectError(error.ObsoleteLineFolding, parse(
        "GET / HTTP/1.1\r\nHost: x\r\nX-Custom: value\r\n continued\r\n\r\n",
    ));
}

test "line folding: reject HTAB continuation" {
    try testing.expectError(error.ObsoleteLineFolding, parse(
        "GET / HTTP/1.1\r\nHost: x\r\nX-Custom: value\r\n\tcontinued\r\n\r\n",
    ));
}

// -- Path Character Validation --

test "path: reject NUL character" {
    try testing.expectError(error.InvalidPath, parse("GET /foo\x00bar HTTP/1.1\r\nHost: x\r\n\r\n"));
}

test "path: reject control character" {
    try testing.expectError(error.InvalidPath, parse("GET /foo\x1Fbar HTTP/1.1\r\nHost: x\r\n\r\n"));
}

test "path: reject DEL character" {
    try testing.expectError(error.InvalidPath, parse("GET /foo\x7Fbar HTTP/1.1\r\nHost: x\r\n\r\n"));
}

test "path: reject high byte" {
    try testing.expectError(error.InvalidPath, parse("GET /foo\x80bar HTTP/1.1\r\nHost: x\r\n\r\n"));
}

test "path: accept all visible ASCII" {
    const req = try parse("GET /!\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~ HTTP/1.1\r\nHost: x\r\n\r\n");
    try testing.expect(req.path.len > 0);
}

// -- Header Field Validation --

test "header: field-name reject space" {
    // Space in field-name should cause Host to not be found
    try testing.expectError(error.MissingHost, parse("GET / HTTP/1.1\r\nHo st: x\r\n\r\n"));
}

test "header: field-name reject control char" {
    try testing.expectError(error.MissingHost, parse("GET / HTTP/1.1\r\nHos\x00t: x\r\n\r\n"));
}

test "header: field-value reject control char" {
    try testing.expectError(error.MissingHost, parse("GET / HTTP/1.1\r\nHost: x\x00y\r\n\r\n"));
}

test "header: field-value accept space" {
    const req = try parse("GET / HTTP/1.1\r\nHost: example.com\r\nX-Custom: hello world\r\n\r\n");
    try testing.expectEqualStrings("example.com", req.host);
}

test "parseHeaderLine: reject field-name with space" {
    try testing.expectError(error.InvalidHeader, parseHeaderLine("X Custom: value"));
}

test "parseHeaderLine: reject field-name with control char" {
    try testing.expectError(error.InvalidHeader, parseHeaderLine("X-\x00Custom: value"));
}

test "parseHeaderLine: reject field-value with control char" {
    try testing.expectError(error.InvalidHeader, parseHeaderLine("X-Custom: val\x00ue"));
}

test "parseHeaderLine: accept field-value with space" {
    const hdr = try parseHeaderLine("X-Custom: hello world");
    try testing.expectEqualStrings("X-Custom", hdr.name);
    try testing.expectEqualStrings("hello world", hdr.value);
}
