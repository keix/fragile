// responsibility:
//   defines Handler boundary (Request → Response)
//   dispatch via table lookup only
//
// guarantees:
//   - pure interface
//   - Context carries capabilities only
//   - dispatch does not grow with features
//
// non-goals:
//   - no I/O in interface
//   - no behavior in Context
//   - no method-specific logic here

pub const Request = @import("request.zig").Request;
pub const Response = @import("response.zig").Response;
const Method = @import("request.zig").Method;

/// Capabilities passed to handler. No IO. No behavior.
pub const Context = struct {};

/// Handler boundary. Pure function.
/// All extensions (proxy, app, thread pool) go through here.
pub const Handler = *const fn (*Context, Request) anyerror!Response;

// =============================================================================
// Dispatch (table lookup only)
// =============================================================================

/// Dispatch requests to services.
/// Routing only. No logic. Does not grow with features.
pub fn dispatch(ctx: *Context, req: Request) anyerror!Response {
    const handler = table.get(req.method) orelse return method_not_allowed;
    return handler(ctx, req);
}

const method_not_allowed: Response = .{
    .status = .method_not_allowed,
    .body = .{ .slice = "" },
    .content_length = 0,
};

// =============================================================================
// Dispatch Table
// =============================================================================

const table = struct {
    pub fn get(method: Method) ?Handler {
        return switch (method) {
            .GET => handleGet,
            .HEAD => handleHead,
            else => null,
        };
    }
};

// =============================================================================
// Method Handlers (wrappers)
// =============================================================================

const get_service = @import("service/get.zig");

fn handleGet(ctx: *Context, req: Request) anyerror!Response {
    // Per-request stack buffer.
    // Safe because response is consumed synchronously.
    var buf: [get_service.SMALL_FILE_LIMIT]u8 = undefined;
    return get_service.handle(ctx, req, &buf);
}

fn handleHead(ctx: *Context, req: Request) anyerror!Response {
    return get_service.handleHead(ctx, req);
}
