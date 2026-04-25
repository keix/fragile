// responsibility:
//   defines Handler boundary (Request → Response)
//
// guarantees:
//   - pure interface
//   - Context carries capabilities only
//
// non-goals:
//   - no I/O in interface
//   - no behavior in Context

pub const Request = @import("request.zig").Request;
pub const Response = @import("response.zig").Response;

/// Capabilities passed to handler. No IO. No behavior.
pub const Context = struct {
    // Start empty. Add as needed:
    // allocator: ?Allocator,
    // config: *const Config,
};

/// Handler boundary. Pure function.
/// All extensions (proxy, app, thread pool) go through here.
pub const Handler = *const fn (*Context, Request) anyerror!Response;

const get = @import("service/get.zig");

/// Dispatch requests to services.
/// Routing only. No logic.
pub fn dispatch(_: *Context, req: Request) anyerror!Response {
    return switch (req.method) {
        .GET => blk: {
            var buf: [4096]u8 = undefined;
            break :blk get.handle(req, &buf);
        },
        .HEAD => blk: {
            var buf: [4096]u8 = undefined;
            const res = get.handle(req, &buf);
            break :blk .{ .status = res.status, .body = "" };
        },
        else => method_not_allowed,
    };
}

const method_not_allowed: Response = .{
    .status = .method_not_allowed,
    .body = "",
};
