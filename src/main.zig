const Listener = @import("net/listener.zig").Listener;
const Loop = @import("server/loop.zig").Loop;

pub fn main() !void {
    var listener = try Listener.init(8080);
    defer listener.deinit();

    var loop = try Loop.init(&listener);
    defer loop.deinit();

    loop.run();
}
