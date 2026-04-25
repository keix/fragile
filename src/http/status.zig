// responsibility:
//   defines HTTP status codes
//
// guarantees:
//   - protocol data only
//   - no behavior beyond phrase lookup
//
// non-goals:
//   - no response logic

pub const Status = enum(u16) {
    ok = 200,
    bad_request = 400,
    not_found = 404,
    method_not_allowed = 405,

    pub fn phrase(self: Status) []const u8 {
        return switch (self) {
            .ok => "OK",
            .bad_request => "Bad Request",
            .not_found => "Not Found",
            .method_not_allowed => "Method Not Allowed",
        };
    }
};
