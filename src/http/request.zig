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
    POST,
};

pub const Protocol = enum {
    http11,
};

pub const Header = struct {
    name: []const u8,
    value: []const u8,
};

pub const Request = struct {
    method: Method,
    path: []const u8,
    protocol: Protocol,
    host: []const u8,
    content_length: ?usize,
    body: []const u8,
};
