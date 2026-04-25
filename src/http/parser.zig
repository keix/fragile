// responsibility:
//   protocol dispatch facade
//
// guarantees:
//   - single import point for parsing
//   - delegates to protocol-specific parser
//
// non-goals:
//   - no parsing logic here

pub const http1 = @import("http1/parser.zig");

pub const parse = http1.parse;
pub const parseHeaderLine = http1.parseHeaderLine;
pub const findHeader = http1.findHeader;

pub const Request = http1.Request;
pub const Method = http1.Method;
pub const Protocol = http1.Protocol;
pub const Header = http1.Header;
pub const Error = http1.Error;
