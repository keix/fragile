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
