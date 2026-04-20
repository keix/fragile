// responsibility:
//   JSON payload parsing (stub)
//
// guarantees:
//   - interface only
//
// non-goals:
//   - no implementation

const Payload = @import("payload.zig").Payload;

pub fn parse(_: Payload) !void {
    return error.NotImplemented;
}
