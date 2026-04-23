// responsibility:
//   wires all layers and starts the server
//
// guarantees:
//   - single entry point
//
// non-goals:
//   - no logic beyond wiring

const Listener = @import("net/listener.zig").Listener;
const Loop = @import("server/loop.zig").Loop;
const handler = @import("http/handler.zig");
const Response = @import("http/response.zig").Response;

pub fn main() !void {
    var listener = try Listener.init(8080);
    defer listener.deinit();

    var loop = try Loop.init(&listener, &.{}, handleRequest);
    defer loop.deinit();

    loop.run();
}

fn handleRequest(_: *handler.Context, _: handler.Request) !Response {
    return .{
        .status = .ok,
        .body = "Hello, World!!",
    };
}

test {
    _ = @import("http/http1/parser.zig");
    _ = @import("http/response.zig");
    _ = @import("server/connection.zig");
}
