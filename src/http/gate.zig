// responsibility:
//   decides pass or reject
//
// guarantees:
//   - pure function
//   - no modification
//   - no allocation
//   - no I/O
//
// non-goals:
//   - does not transform request
//   - does not generate response

const Request = @import("request.zig").Request;

pub const Gate = *const fn (Request) anyerror!void;

pub fn apply(gates: []const Gate, req: Request) !void {
    for (gates) |gate| {
        try gate(req);
    }
}
