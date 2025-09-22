//! Common utilities shared across all protocols
const std = @import("std");

pub const Stream = @import("stream.zig").Stream;
pub const Parser = @import("parser.zig").Parser;
pub const Auth = @import("auth.zig").Auth;
pub const ConnectionPool = @import("connection_pool.zig").ConnectionPool;
pub const RateLimiter = @import("rate_limiter.zig").RateLimiter;

pub const Error = error{
    InvalidProtocol,
    ConnectionClosed,
    ParseError,
    AuthenticationFailed,
    Timeout,
    RateLimitExceeded,
};

/// Common result type for protocol operations
pub fn Result(comptime T: type) type {
    return union(enum) {
        success: T,
        error_: Error,
    };
}

test "common utilities compile" {
    _ = Stream;
    _ = Parser;
    _ = Auth;
}
