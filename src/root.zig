//! zproto - A unified Zig-native library for application-layer protocols
//!
//! This library provides client and server implementations for common network protocols,
//! built from the ground up in Zig with no external dependencies.
const std = @import("std");

// Common utilities
pub const common = @import("common/common.zig");
pub const Stream = common.Stream;
pub const Parser = common.Parser;
pub const Auth = common.Auth;

// Protocol implementations
pub const http = @import("protocols/http.zig");
pub const dns = @import("protocols/dns.zig");
pub const ftp = @import("protocols/ftp.zig");
pub const smtp = @import("protocols/smtp.zig");
pub const imap = @import("protocols/imap.zig");
pub const pop3 = @import("protocols/pop3.zig");
pub const email_parser = @import("protocols/email_parser.zig");

// Legacy function for backwards compatibility
pub fn bufferedPrint() !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    try stdout.print("zproto - Protocol Suite Library\n", .{});
    try stdout.print("Available protocols: HTTP, DNS, FTP, SMTP\n", .{});

    try stdout.flush();
}

test "zproto module structure" {
    // Basic smoke test to ensure modules compile
    _ = http;
    _ = dns;
    _ = ftp;
    _ = smtp;
    _ = common;
}
