//! Example demonstrating SMTP client usage
const std = @import("std");
const zproto = @import("zproto");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Note: This is a demonstration only.
    // You'll need to provide real SMTP server credentials to actually send emails.
    const smtp_server = "smtp.gmail.com";
    const smtp_port = 587;
    const username = "your_email@gmail.com";
    const password = "your_app_password"; // Use app password for Gmail

    // Prevent unused variable warnings
    _ = smtp_server;
    _ = smtp_port;
    _ = password;

    std.debug.print("SMTP Client Example\n", .{});
    std.debug.print("Note: Update credentials in source to actually send emails\n\n", .{});

    // Create SMTP client
    var client = zproto.smtp.SmtpClient.init(allocator);
    defer client.deinit();

    // Create email message
    const from = zproto.smtp.EmailAddress{
        .name = "zproto Test",
        .email = username,
    };

    const to = [_]zproto.smtp.EmailAddress{
        .{ .name = "Test Recipient", .email = "recipient@example.com" },
    };

    var message = zproto.smtp.EmailMessage.init(allocator, from, &to, "Test Email from zproto", "This is a test email sent using the zproto SMTP client!\n\nBest regards,\nzproto") catch |err| {
        std.debug.print("Error creating email message: {}\n", .{err});
        return;
    };
    defer message.deinit();

    // Add custom headers
    message.addHeader("X-Mailer", "zproto/0.1.0") catch {};

    std.debug.print("Email message created:\n", .{});
    std.debug.print("From: {s}\n", .{from.email});
    std.debug.print("To: {s}\n", .{to[0].email});
    std.debug.print("Subject: {s}\n", .{message.subject});

    // Simulate sending (don't actually connect without real credentials)
    std.debug.print("\nTo actually send this email:\n", .{});
    std.debug.print("1. Update smtp_server, username, and password\n", .{});
    std.debug.print("2. Uncomment the connection and send code below\n", .{});

    // Uncomment this block to actually send emails:
    //
    // // Connect to SMTP server
    // client.connect(smtp_server, smtp_port) catch |err| {
    //     std.debug.print("Error connecting to SMTP server: {}\n", .{err});
    //     return;
    // };
    //
    // // Perform EHLO handshake
    // client.ehlo("localhost") catch |err| {
    //     std.debug.print("Error during EHLO: {}\n", .{err});
    //     return;
    // };
    //
    // // Authenticate
    // client.authenticate(username, password, .plain) catch |err| {
    //     std.debug.print("Error authenticating: {}\n", .{err});
    //     return;
    // };
    //
    // // Send the email
    // client.sendMail(message) catch |err| {
    //     std.debug.print("Error sending email: {}\n", .{err});
    //     return;
    // };
    //
    // std.debug.print("Email sent successfully!\n");
    //
    // // Quit
    // client.quit() catch {};

    std.debug.print("\nSMTP client example completed.\n", .{});
}
