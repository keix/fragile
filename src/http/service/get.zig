// responsibility:
//   handles GET requests
//
// guarantees:
//   - returns Response
//
// non-goals:
//   - no routing logic

const Request = @import("../request.zig").Request;
const Response = @import("../response.zig").Response;

pub fn handle(_: Request) Response {
    return .{
        .status = .ok,
        .body = "Hello, World!!",
    };
}
