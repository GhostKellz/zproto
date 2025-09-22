//! Basic test framework for zproto protocols
const std = @import("std");
const zproto = @import("zproto");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("zproto Test Suite\n", .{});
    std.debug.print("================\n\n", .{});

    var passed: u32 = 0;
    var total: u32 = 0;

    // Test HTTP client
    std.debug.print("Testing HTTP Client...\n", .{});
    if (testHttpClient(allocator)) {
        std.debug.print("✓ HTTP Client basic test passed\n", .{});
        passed += 1;
    } else |err| {
        std.debug.print("✗ HTTP Client basic test failed: {}\n", .{err});
    }
    total += 1;

    // Test DNS client
    std.debug.print("\nTesting DNS Client...\n", .{});
    if (testDnsClient(allocator)) {
        std.debug.print("✓ DNS Client basic test passed\n", .{});
        passed += 1;
    } else |err| {
        std.debug.print("✗ DNS Client basic test failed: {}\n", .{err});
    }
    total += 1;

    // Test FTP client
    std.debug.print("\nTesting FTP Client...\n", .{});
    if (testFtpClient(allocator)) {
        std.debug.print("✓ FTP Client basic test passed\n", .{});
        passed += 1;
    } else |err| {
        std.debug.print("✗ FTP Client basic test failed: {}\n", .{err});
    }
    total += 1;

    // Test SMTP client
    std.debug.print("\nTesting SMTP Client...\n", .{});
    if (testSmtpClient(allocator)) {
        std.debug.print("✓ SMTP Client basic test passed\n", .{});
        passed += 1;
    } else |err| {
        std.debug.print("✗ SMTP Client basic test failed: {}\n", .{err});
    }
    total += 1;

    // Test common utilities
    std.debug.print("\nTesting Common Utilities...\n", .{});
    if (testCommonUtilities(allocator)) {
        std.debug.print("✓ Common utilities test passed\n", .{});
        passed += 1;
    } else |err| {
        std.debug.print("✗ Common utilities test failed: {}\n", .{err});
    }
    total += 1;

    std.debug.print("\n================\n", .{});
    std.debug.print("Test Results: {}/{} passed\n", .{ passed, total });
    if (passed == total) {
        std.debug.print("All tests passed! 🎉\n", .{});
    } else {
        std.debug.print("Some tests failed. 😞\n", .{});
    }
}

fn testHttpClient(allocator: std.mem.Allocator) !void {
    var client = zproto.http.HttpClient.init(allocator);
    defer client.deinit();

    // Test URL parsing by creating a request
    var request = try zproto.http.HttpRequest.init(allocator, .GET, "/test");
    defer request.deinit();

    try request.headers.set("User-Agent", "zproto-test");

    // Basic validation
    if (!std.mem.eql(u8, request.uri, "/test")) {
        return error.InvalidUri;
    }

    if (!std.mem.eql(u8, request.headers.get("User-Agent").?, "zproto-test")) {
        return error.InvalidHeader;
    }

    // Test response creation
    var response = zproto.http.HttpResponse.init(allocator);
    defer response.deinit();

    try response.headers.set("Content-Type", "text/plain");
    if (!std.mem.eql(u8, response.headers.get("Content-Type").?, "text/plain")) {
        return error.InvalidResponseHeader;
    }
}

fn testDnsClient(allocator: std.mem.Allocator) !void {
    // Test DNS header encoding/decoding
    const header = zproto.dns.DnsHeader{
        .id = 0x1234,
        .qr = false,
        .opcode = .QUERY,
        .aa = false,
        .tc = false,
        .rd = true,
        .ra = false,
        .z = 0,
        .rcode = .NOERROR,
        .qdcount = 1,
        .ancount = 0,
        .nscount = 0,
        .arcount = 0,
    };

    var buffer: [12]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);

    try header.encode(stream.writer());

    stream.pos = 0;
    const decoded = try zproto.dns.DnsHeader.decode(stream.reader());

    if (decoded.id != 0x1234) return error.InvalidId;
    if (decoded.rd != true) return error.InvalidRd;
    if (decoded.qdcount != 1) return error.InvalidQdcount;

    // Test client creation (without actually connecting)
    var client = try zproto.dns.DnsClient.initWithDefaultServers(allocator);
    defer client.deinit();

    if (client.servers.len != 2) return error.InvalidServerCount;
}

fn testFtpClient(allocator: std.mem.Allocator) !void {
    // Test FTP response parsing
    const response_data = "200 OK\r\n";
    var response = try zproto.ftp.FtpResponse.parse(allocator, response_data);
    defer response.deinit(allocator);

    if (response.code != 200) return error.InvalidCode;
    if (!std.mem.eql(u8, response.message, "OK")) return error.InvalidMessage;
    if (!response.isSuccess()) return error.InvalidStatus;

    // Test client creation
    var client = zproto.ftp.FtpClient.init(allocator);
    defer client.deinit();

    if (client.transfer_mode != .passive) return error.InvalidTransferMode;
    if (client.transfer_type != .binary) return error.InvalidTransferType;
}

fn testSmtpClient(allocator: std.mem.Allocator) !void {
    // Test SMTP response parsing
    var response = try zproto.smtp.SmtpResponse.parse(allocator, "250 OK\r\n");
    defer response.deinit(allocator);

    if (response.code != 250) return error.InvalidCode;
    if (!std.mem.eql(u8, response.message, "OK")) return error.InvalidMessage;
    if (!response.isSuccess()) return error.InvalidStatus;

    // Test email address formatting
    const addr = zproto.smtp.EmailAddress{ .name = "Test User", .email = "test@example.com" };
    const formatted = try addr.format(allocator);
    defer allocator.free(formatted);

    const expected = "\"Test User\" <test@example.com>";
    if (!std.mem.eql(u8, formatted, expected)) return error.InvalidFormatting;

    // Test client creation
    var client = zproto.smtp.SmtpClient.init(allocator);
    defer client.deinit();
}

fn testCommonUtilities(allocator: std.mem.Allocator) !void {
    // Test parser
    const data = "Hello\r\nWorld\r\n\r\nData";
    var parser = zproto.common.Parser.init(data);

    const line1 = try parser.readLine();
    if (!std.mem.eql(u8, line1, "Hello")) return error.InvalidLine1;

    const line2 = try parser.readLine();
    if (!std.mem.eql(u8, line2, "World")) return error.InvalidLine2;

    const empty_line = try parser.readLine();
    if (empty_line.len != 0) return error.InvalidEmptyLine;

    // Test line parser
    var line_parser = try zproto.common.LineParser.init(allocator, data);
    defer line_parser.deinit();

    if (!std.mem.eql(u8, line_parser.nextLine().?, "Hello")) return error.InvalidLineParsing;

    // Test auth utilities
    const encoded = try zproto.common.Auth.encodeBasicAuth(allocator, "user", "pass");
    defer allocator.free(encoded);

    // "user:pass" base64 encoded should be "dXNlcjpwYXNz"
    if (!std.mem.eql(u8, encoded, "dXNlcjpwYXNz")) return error.InvalidBasicAuth;

    // Test nonce generation
    const nonce1 = try zproto.common.Auth.generateNonce(allocator, 16);
    defer allocator.free(nonce1);

    const nonce2 = try zproto.common.Auth.generateNonce(allocator, 16);
    defer allocator.free(nonce2);

    if (std.mem.eql(u8, nonce1, nonce2)) return error.NonceCollision;
    if (nonce1.len != 32) return error.InvalidNonceLength; // 16 bytes -> 32 hex chars

    // Test rate limiter
    var limiter = zproto.common.RateLimiter.init(10.0, 1.0);

    try limiter.tryAcquire(5.0);
    try limiter.tryAcquire(5.0);

    // Should be out of tokens now
    if (limiter.tryAcquire(1.0)) {
        return error.RateLimiterShouldBeExhausted;
    } else |err| {
        if (err != error.RateLimitExceeded) return error.WrongRateLimiterError;
    }
}
