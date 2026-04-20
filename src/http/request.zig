// responsibility:
//   defines HTTP request structures
//
// guarantees:
//   - pure data, no behavior
//   - slices only, no allocation
//
// non-goals:
//   - no parsing
//   - no validation

pub const Method = enum {
    GET,
};

pub const Protocol = enum {
    http11,
};

pub const RequestLine = struct {
    method: Method,
    path: []const u8,
    protocol: Protocol,
};

pub const Request = struct {
    method: Method,
    path: []const u8,
    protocol: Protocol,
    host: []const u8,
};
