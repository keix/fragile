const std = @import("std");

pub const Method = enum {
    GET,
};

pub const Request = struct {
    method: Method,
    path: []const u8,
    host: []const u8,

    pub fn format(
        self: Request,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        try writer.print("Request{{ {s} {s} Host: {s} }}", .{
            @tagName(self.method),
            self.path,
            self.host,
        });
    }
};
