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
const Context = @import("../handler.zig").Context;
const fd = @import("../../net/sys/fd.zig");
pub const SMALL_FILE_LIMIT = 8192;

// Environment-provided or default. Lifetime is static.
fn getRoot() []const u8 {
    return std.posix.getenv("FRAGILE_ROOT") orelse "./public";
}

pub fn handle(ctx: *const Context, req: Request, buf: *[SMALL_FILE_LIMIT]u8) Response {
    _ = ctx;

    var path_buf: [256]u8 = undefined;

    const file_path = mapRequestPath(req.path, &path_buf) orelse return not_found;

    const file = fd.open(file_path) catch return not_found;
    const file_size = fd.size(file) catch {
        fd.close(file);
        return not_found;
    };

    if (file_size <= SMALL_FILE_LIMIT) {
        const body = buf[0..file_size];
        const n = fd.read(file, body) catch {
            fd.close(file);
            return not_found;
        };
        fd.close(file);

        if (n != file_size) return not_found;

        return .{
            .status = .ok,
            .body = .{ .slice = body },
            .content_length = file_size,
        };
    }

    return .{
        .status = .ok,
        .body = .{ .file = .{ .fd = file, .size = file_size, .owned = true } },
        .content_length = file_size,
    };
}

pub fn handleHead(ctx: *const Context, req: Request) Response {
    _ = ctx;

    var path_buf: [256]u8 = undefined;

    const file_path = mapRequestPath(req.path, &path_buf) orelse return not_found;

    const file = fd.open(file_path) catch return not_found;
    defer fd.close(file);

    const file_size = fd.size(file) catch return not_found;

    return .{
        .status = .ok,
        .body = .{ .slice = "" },
        .content_length = file_size,
    };
}

fn mapRequestPath(path: []const u8, path_buf: *[256]u8) ?[]const u8 {
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
    .body = .{ .slice = "" },
    .content_length = 0,
};
