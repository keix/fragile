// responsibility:
//   wires all layers and starts the server
//
// guarantees:
//   - single entry point
//
// non-goals:
//   - no logic beyond wiring

const Listener = @import("net/listener.zig").Listener;
const Worker = @import("server/worker.zig").Worker;
const handler = @import("http/handler.zig");
const Response = @import("http/response.zig").Response;

const NUM_WORKERS = 4;

pub fn main() !void {
    var listener = try Listener.init(8080);
    defer listener.deinit();

    var worker = Worker.init(&listener, &.{}, handleRequest, NUM_WORKERS);
    try worker.run();
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
