// responsibility:
//   handles GET requests (file serving)
//
// guarantees:
//   - returns Response
//   - no shared state (stack buffer only)
//   - path traversal safe
//
// non-goals:
//   - no routing logic
//   - no caching

const std = @import("std");
const Request = @import("../request.zig").Request;
const Response = @import("../response.zig").Response;
const fd = @import("../../net/sys/fd.zig");

// Environment-provided or default. Lifetime is static.
fn getRoot() []const u8 {
    return std.posix.getenv("FRAGILE_ROOT") orelse "./public";
}

pub fn handle(req: Request, buf: *[4096]u8) Response {
    // Per-request stack buffer.
    // Safe under current synchronous execution model.
    var path_buf: [256]u8 = undefined;

    const file_path = mapPath(req.path, &path_buf) orelse return not_found;

    const file = fd.open(file_path) catch return not_found;
    defer fd.close(file);

    // Files larger than buffer are truncated (temporary).
    const n = fd.read(file, buf) catch return not_found;

    return .{
        .status = .ok,
        .body = buf[0..n],
    };
}

fn mapPath(path: []const u8, path_buf: *[256]u8) ?[]const u8 {
    // must start with "/"
    if (path.len == 0 or path[0] != '/') return null;

    // reject path traversal
    if (std.mem.indexOf(u8, path, "..")) |_| return null;

    // "/" → "/index.html"
    const file = if (path.len == 1) "/index.html" else path;

    // root + path
    const result = std.fmt.bufPrint(path_buf, "{s}{s}", .{ getRoot(), file }) catch return null;
    return result;
}

const not_found: Response = .{
    .status = .not_found,
    .body = "",
};
