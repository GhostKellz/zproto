const std = @import("std");
const zproto = @import("zproto");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create SMTP client
    var smtp_client = zproto.smtp.SmtpClient.init(allocator);
    defer smtp_client.deinit();

    std.debug.print("=== Enhanced SMTP/SMTPS Client Example ===\n", .{});

    // Example 1: Plain SMTP connection
    std.debug.print("\n1. Plain SMTP Connection Example:\n", .{});

    const plain_config = zproto.smtp.SmtpConfig{
        .host = "localhost",
        .port = 25,
        .security = .none,
        .auth_method = .none,
        .username = null,
        .password = null,
    };

    smtp_client.connect(plain_config) catch |err| {
        std.debug.print("Failed to connect to plain SMTP server: {}\n", .{err});
        std.debug.print("(This is expected if no local SMTP server is running)\n", .{});
    };

    // Example 2: SMTPS (implicit TLS) connection
    std.debug.print("\n2. SMTPS (Implicit TLS) Example:\n", .{});

    const smtps_config = zproto.smtp.SmtpConfig{
        .host = "smtp.gmail.com",
        .port = 465,
        .security = .implicit,
        .auth_method = .plain,
        .username = "your-email@gmail.com",
        .password = "your-app-password",
    };

    smtp_client.connect(smtps_config) catch |err| {
        std.debug.print("Failed to connect to SMTPS server: {}\n", .{err});
        std.debug.print("(Configure with real credentials to test)\n", .{});
    };

    // Example 3: STARTTLS connection
    std.debug.print("\n3. STARTTLS Example:\n", .{});

    const starttls_config = zproto.smtp.SmtpConfig{
        .host = "smtp.gmail.com",
        .port = 587,
        .security = .starttls,
        .auth_method = .login,
        .username = "your-email@gmail.com",
        .password = "your-app-password",
    };

    smtp_client.connect(starttls_config) catch |err| {
        std.debug.print("Failed to connect with STARTTLS: {}\n", .{err});
        std.debug.print("(Configure with real credentials to test)\n", .{});
    };

    // Example 4: Create and send email
    std.debug.print("\n4. Email Creation Example:\n", .{});

    // Create email addresses
    const from_addr = zproto.smtp.EmailAddress{
        .name = "Sender Name",
        .email = "sender@example.com",
    };

    const to_addrs = [_]zproto.smtp.EmailAddress{
        .{ .name = "Recipient One", .email = "recipient1@example.com" },
        .{ .name = "Recipient Two", .email = "recipient2@example.com" },
    };

    // Create email message
    var email = try zproto.smtp.EmailMessage.init(allocator, from_addr, &to_addrs, "Test Email from zproto SMTP Client", "Hello from the enhanced zproto SMTP client!\n\nThis email was sent using:\n- SMTPS/STARTTLS support\n- Enhanced authentication\n- Improved error handling\n\nBest regards,\nzproto Team");
    defer email.deinit();

    // Add custom headers
    try email.addHeader("X-Mailer", "zproto SMTP Client v0.1.0");
    try email.addHeader("X-Priority", "3");

    // Add CC recipients
    const cc_addrs = [_]zproto.smtp.EmailAddress{
        .{ .name = "CC Recipient", .email = "cc@example.com" },
    };
    try email.setCc(&cc_addrs);

    std.debug.print("Email created successfully!\n", .{});
    std.debug.print("From: {s}\n", .{email.from.email});
    std.debug.print("To: {} recipients\n", .{email.to.len});
    std.debug.print("Subject: {s}\n", .{email.subject});

    if (email.cc) |cc| {
        std.debug.print("CC: {} recipients\n", .{cc.len});
    }

    // Format and display the message
    const formatted_message = try email.formatMessage(allocator);
    defer allocator.free(formatted_message);

    std.debug.print("\nFormatted message preview (first 300 chars):\n", .{});
    const preview_len = @min(formatted_message.len, 300);
    std.debug.print("{s}...\n", .{formatted_message[0..preview_len]});

    std.debug.print("\n=== Example completed ===\n", .{});
    std.debug.print("Note: To actually send emails, configure the examples with real SMTP server credentials.\n", .{});
}
