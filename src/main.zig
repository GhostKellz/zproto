const std = @import("std");
const zproto = @import("zproto");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("🌐 zproto - Zig Protocol Suite v0.1.0\n", .{});
    std.debug.print("=====================================\n\n", .{});

    std.debug.print("Available protocols:\n", .{});
    std.debug.print("✓ HTTP/HTTPS - Web client implementation\n", .{});
    std.debug.print("✓ DNS - Domain name resolution client\n", .{});
    std.debug.print("✓ FTP - File transfer protocol client\n", .{});
    std.debug.print("✓ SMTP/SMTPS - Email sending client with TLS support\n", .{});
    std.debug.print("✓ IMAP - Internet Message Access Protocol client\n", .{});
    std.debug.print("✓ POP3/POP3S - Post Office Protocol client\n", .{});
    std.debug.print("✓ Email Parser - MIME message parsing utilities\n", .{});
    std.debug.print("\nShared utilities:\n", .{});
    std.debug.print("✓ Stream abstraction (TCP/TLS)\n", .{});
    std.debug.print("✓ Protocol parsers (line-based, binary)\n", .{});
    std.debug.print("✓ Authentication helpers\n", .{});
    std.debug.print("✓ Connection pooling\n", .{});
    std.debug.print("✓ Rate limiting\n", .{});

    std.debug.print("\n📁 Examples available in examples/ directory:\n", .{});
    std.debug.print("   - http_client_example.zig\n", .{});
    std.debug.print("   - dns_client_example.zig\n", .{});
    std.debug.print("   - smtp_client_example.zig\n", .{});
    std.debug.print("   - smtp_enhanced_example.zig (TLS/STARTTLS support)\n", .{});
    std.debug.print("   - imap_client_example.zig\n", .{});
    std.debug.print("   - pop3_client_example.zig\n", .{});
    std.debug.print("   - email_parser_example.zig\n", .{});

    std.debug.print("\n🧪 Run tests with: zig build test\n", .{});
    std.debug.print("📖 See TODO.md for implementation roadmap\n", .{});

    // Quick demo of the library
    std.debug.print("\n--- Quick Demo ---\n", .{});

    // Demo HTTP client creation
    std.debug.print("Creating HTTP client... ", .{});
    var http_client = zproto.http.HttpClient.init(allocator);
    defer http_client.deinit();
    std.debug.print("✓\n", .{});

    // Demo DNS client creation
    std.debug.print("Creating DNS client... ", .{});
    var dns_client = zproto.dns.DnsClient.initWithDefaultServers(allocator) catch {
        std.debug.print("✗ (failed)\n", .{});
        return;
    };
    defer dns_client.deinit();
    std.debug.print("✓\n", .{});

    // Demo SMTP client creation
    std.debug.print("Creating SMTP client... ", .{});
    var smtp_client = zproto.smtp.SmtpClient.init(allocator);
    defer smtp_client.deinit();
    std.debug.print("✓\n", .{});

    // Demo FTP client creation
    std.debug.print("Creating FTP client... ", .{});
    var ftp_client = zproto.ftp.FtpClient.init(allocator);
    defer ftp_client.deinit();
    std.debug.print("✓\n", .{});

    // Demo IMAP client creation
    std.debug.print("Creating IMAP client... ", .{});
    var imap_client = zproto.imap.ImapClient.init(allocator);
    defer imap_client.deinit();
    std.debug.print("✓\n", .{});

    // Demo POP3 client creation
    std.debug.print("Creating POP3 client... ", .{});
    var pop3_client = zproto.pop3.Pop3Client.init(allocator);
    defer pop3_client.deinit();
    std.debug.print("✓\n", .{});

    std.debug.print("\nAll protocol clients initialized successfully!\n", .{});
    std.debug.print("Ready to communicate with the world. 🚀\n", .{});

    // Call legacy function for backwards compatibility
    try zproto.bufferedPrint();
}

test "simple test" {
    const gpa = std.testing.allocator;
    var list: std.ArrayList(i32) = .empty;
    defer list.deinit(gpa); // Try commenting this out and see if zig detects the memory leak!
    try list.append(gpa, 42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

test "fuzz example" {
    const Context = struct {
        fn testOne(context: @This(), input: []const u8) anyerror!void {
            _ = context;
            // Try passing `--fuzz` to `zig build test` and see if it manages to fail this test case!
            try std.testing.expect(!std.mem.eql(u8, "canyoufindme", input));
        }
    };
    try std.testing.fuzz(Context{}, Context.testOne, .{});
}
