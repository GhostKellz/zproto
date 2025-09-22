//! zproto - A unified Zig-native library for application-layer protocols
//!
//! This library provides client and server implementations for common network protocols,
//! built from the ground up in Zig with no external dependencies.
const std = @import("std");
const build_options = @import("build_options");

// Common utilities (always available)
pub const common = @import("common/common.zig");
pub const Stream = common.Stream;
pub const Parser = common.Parser;
pub const Auth = common.Auth;

// Protocol implementations - conditionally compiled based on build options
pub const http = if (build_options.enable_http) @import("protocols/http.zig") else struct {};
pub const dns = if (build_options.enable_dns) @import("protocols/dns.zig") else struct {};
pub const ftp = if (build_options.enable_ftp) @import("protocols/ftp.zig") else struct {};
pub const smtp = if (build_options.enable_smtp) @import("protocols/smtp.zig") else struct {};
pub const imap = if (build_options.enable_imap) @import("protocols/imap.zig") else struct {};
pub const pop3 = if (build_options.enable_pop3) @import("protocols/pop3.zig") else struct {};
pub const email_parser = if (build_options.enable_email_parser) @import("protocols/email_parser.zig") else struct {};
pub const websocket = if (build_options.enable_websocket) @import("protocols/websocket.zig") else struct {};

// Legacy function for backwards compatibility
pub fn bufferedPrint() !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    try stdout.print("zproto - Protocol Suite Library\n", .{});

    // Show enabled protocols
    try stdout.print("Enabled protocols: ", .{});
    var first = true;

    if (build_options.enable_http) {
        if (!first) try stdout.print(", ", .{});
        try stdout.print("HTTP", .{});
        first = false;
    }
    if (build_options.enable_dns) {
        if (!first) try stdout.print(", ", .{});
        try stdout.print("DNS", .{});
        first = false;
    }
    if (build_options.enable_ftp) {
        if (!first) try stdout.print(", ", .{});
        try stdout.print("FTP", .{});
        first = false;
    }
    if (build_options.enable_smtp) {
        if (!first) try stdout.print(", ", .{});
        try stdout.print("SMTP", .{});
        first = false;
    }
    if (build_options.enable_imap) {
        if (!first) try stdout.print(", ", .{});
        try stdout.print("IMAP", .{});
        first = false;
    }
    if (build_options.enable_pop3) {
        if (!first) try stdout.print(", ", .{});
        try stdout.print("POP3", .{});
        first = false;
    }
    if (build_options.enable_websocket) {
        if (!first) try stdout.print(", ", .{});
        try stdout.print("WebSocket", .{});
        first = false;
    }
    if (build_options.enable_email_parser) {
        if (!first) try stdout.print(", ", .{});
        try stdout.print("Email-Parser", .{});
        first = false;
    }

    if (first) {
        try stdout.print("None", .{});
    }
    try stdout.print("\n", .{});

    try stdout.flush();
}

test "zproto module structure" {
    // Basic smoke test to ensure enabled modules compile
    if (build_options.enable_http) _ = http;
    if (build_options.enable_dns) _ = dns;
    if (build_options.enable_ftp) _ = ftp;
    if (build_options.enable_smtp) _ = smtp;
    if (build_options.enable_imap) _ = imap;
    if (build_options.enable_pop3) _ = pop3;
    if (build_options.enable_email_parser) _ = email_parser;
    if (build_options.enable_websocket) _ = websocket;
    _ = common;
}
