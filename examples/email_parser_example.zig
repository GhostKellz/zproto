const std = @import("std");
const zproto = @import("zproto");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== Email Parser Example ===\n", .{});

    // Example 1: Simple email parsing
    std.debug.print("\n1. Simple Email Parsing:\n", .{});

    const simple_email =
        \\From: sender@example.com
        \\To: recipient@example.com
        \\Subject: Simple Test Email
        \\Date: Mon, 21 Sep 2025 10:30:00 +0000
        \\Content-Type: text/plain; charset=utf-8
        \\
        \\Hello, this is a simple test email!
        \\
        \\Best regards,
        \\Sender
    ;

    var parsed_email = try zproto.email_parser.EmailMessage.parse(allocator, simple_email);
    defer parsed_email.deinit();

    std.debug.print("Successfully parsed simple email:\n", .{});
    std.debug.print("  From: {s}\n", .{parsed_email.getFrom() orelse "Unknown"});
    std.debug.print("  To: {s}\n", .{parsed_email.getTo() orelse "Unknown"});
    std.debug.print("  Subject: {s}\n", .{parsed_email.getSubject() orelse "No subject"});

    if (try parsed_email.getTextContent()) |text| {
        defer allocator.free(text);
        std.debug.print("  Text content length: {} bytes\n", .{text.len});
        const preview_len = @min(text.len, 50);
        std.debug.print("  Preview: {s}...\n", .{text[0..preview_len]});
    }

    // Example 2: Multipart email parsing
    std.debug.print("\n2. Multipart Email Parsing:\n", .{});

    const multipart_email =
        \\From: sender@example.com
        \\To: recipient@example.com
        \\Subject: Multipart Test Email
        \\Date: Mon, 21 Sep 2025 11:00:00 +0000
        \\Content-Type: multipart/mixed; boundary="boundary123"
        \\MIME-Version: 1.0
        \\
        \\This is a MIME-encoded message.
        \\
        \\--boundary123
        \\Content-Type: text/plain; charset=utf-8
        \\
        \\This is the plain text part of the email.
        \\
        \\--boundary123
        \\Content-Type: text/html; charset=utf-8
        \\
        \\<html><body><h1>This is the HTML part</h1><p>With <b>formatting</b>!</p></body></html>
        \\
        \\--boundary123
        \\Content-Type: application/pdf; name="document.pdf"
        \\Content-Disposition: attachment; filename="document.pdf"
        \\Content-Transfer-Encoding: base64
        \\
        \\JVBERi0xLjQKJcfsj6IKNSAwIG9iago8PAovTGVuZ3RoIDYgMCBSCi9GaWx0ZXIgL0ZsYXRlRGVjb2Rl
        \\Cj4+CnN0cmVhbQp4nCvkMlAw5DIwULA1MjYyASDNCvfVPRRMDJWKc8gE/7Pz8wO7u2j/4HADxHpgFX4m
        \\h1gV1UKUAAPoFyU=
        \\endstream
        \\endobj
        \\
        \\--boundary123--
    ;

    var multipart_parsed = try zproto.email_parser.EmailMessage.parse(allocator, multipart_email);
    defer multipart_parsed.deinit();

    std.debug.print("Successfully parsed multipart email:\n", .{});
    std.debug.print("  From: {s}\n", .{multipart_parsed.getFrom() orelse "Unknown"});
    std.debug.print("  Subject: {s}\n", .{multipart_parsed.getSubject() orelse "No subject"});
    std.debug.print("  Parts: {}\n", .{multipart_parsed.parts.items.len});

    for (multipart_parsed.parts.items, 0..) |part, i| {
        std.debug.print("  Part {}:\n", .{i + 1});
        if (part.content_type) |ct| {
            std.debug.print("    Content-Type: {s}/{s}\n", .{ ct.media_type, ct.subtype });
            if (ct.getParameter("charset")) |charset| {
                std.debug.print("    Charset: {s}\n", .{charset});
            }
            if (ct.getParameter("name")) |name| {
                std.debug.print("    Name: {s}\n", .{name});
            }
        }

        if (part.getHeader("content-disposition")) |disposition| {
            std.debug.print("    Disposition: {s}\n", .{disposition});
        }

        std.debug.print("    Content length: {} bytes\n", .{part.content.len});

        if (part.isText()) {
            const decoded = part.getDecodedContent() catch |err| {
                std.debug.print("    Failed to decode content: {}\n", .{err});
                continue;
            };
            defer allocator.free(decoded);

            const preview_len = @min(decoded.len, 80);
            std.debug.print("    Preview: {s}...\n", .{decoded[0..preview_len]});
        }
    }

    // Example 3: Content-Type parsing
    std.debug.print("\n3. Content-Type Parsing:\n", .{});

    const content_type_examples = [_][]const u8{
        "text/plain",
        "text/html; charset=utf-8",
        "multipart/mixed; boundary=\"simple_boundary\"",
        "application/pdf; name=\"document.pdf\"",
        "image/jpeg; name=\"photo.jpg\"",
        "text/plain; charset=iso-8859-1; format=flowed",
    };

    for (content_type_examples) |ct_string| {
        var ct = zproto.email_parser.ContentType.parse(allocator, ct_string) catch |err| {
            std.debug.print("Failed to parse '{s}': {}\n", .{ ct_string, err });
            continue;
        };
        defer ct.deinit();

        std.debug.print("'{s}' parsed as:\n", .{ct_string});
        std.debug.print("  Media type: {s}\n", .{ct.media_type});
        std.debug.print("  Subtype: {s}\n", .{ct.subtype});
        std.debug.print("  Is text: {}\n", .{ct.isText()});
        std.debug.print("  Is multipart: {}\n", .{ct.isMultipart()});
        std.debug.print("  Charset: {s}\n", .{ct.getCharset()});

        if (ct.getBoundary()) |boundary| {
            std.debug.print("  Boundary: {s}\n", .{boundary});
        }

        if (ct.getParameter("name")) |name| {
            std.debug.print("  Name: {s}\n", .{name});
        }
    }

    // Example 4: Header parsing
    std.debug.print("\n4. Header Parsing:\n", .{});

    var headers = zproto.email_parser.HeaderMap.init(allocator);
    defer headers.deinit();

    try headers.set("From", "John Doe <john@example.com>");
    try headers.set("To", "Jane Smith <jane@example.com>");
    try headers.set("Subject", "Meeting Tomorrow");
    try headers.set("Content-Type", "text/plain; charset=utf-8");

    std.debug.print("Header map contains:\n", .{});
    std.debug.print("  from: {s}\n", .{headers.get("from") orelse "Not found"});
    std.debug.print("  FROM: {s}\n", .{headers.get("FROM") orelse "Not found"}); // Case insensitive
    std.debug.print("  subject: {s}\n", .{headers.get("subject") orelse "Not found"});
    std.debug.print("  content-type: {s}\n", .{headers.get("content-type") orelse "Not found"});

    // Example 5: Attachment extraction
    std.debug.print("\n5. Attachment Extraction:\n", .{});

    const attachments = try multipart_parsed.getAttachments();
    defer attachments.deinit();

    std.debug.print("Found {} attachments:\n", .{attachments.items.len});
    for (attachments.items, 0..) |attachment, i| {
        std.debug.print("  Attachment {}:\n", .{i + 1});
        if (attachment.content_type) |ct| {
            std.debug.print("    Type: {s}/{s}\n", .{ ct.media_type, ct.subtype });
            if (ct.getParameter("name")) |name| {
                std.debug.print("    Name: {s}\n", .{name});
            }
        }

        if (attachment.getHeader("content-disposition")) |disposition| {
            std.debug.print("    Disposition: {s}\n", .{disposition});
        }

        std.debug.print("    Size: {} bytes\n", .{attachment.content.len});

        // Attempt to decode the attachment
        const decoded = attachment.getDecodedContent() catch |err| {
            std.debug.print("    Failed to decode: {}\n", .{err});
            continue;
        };
        defer allocator.free(decoded);

        std.debug.print("    Decoded size: {} bytes\n", .{decoded.len});
    }

    std.debug.print("\n=== Example completed ===\n", .{});
    std.debug.print("The email parser can handle:\n", .{});
    std.debug.print("- Simple text emails\n", .{});
    std.debug.print("- Multipart MIME messages\n", .{});
    std.debug.print("- Content-Type parsing\n", .{});
    std.debug.print("- Header extraction (case-insensitive)\n", .{});
    std.debug.print("- Attachment detection\n", .{});
    std.debug.print("- Base64 and Quoted-Printable decoding\n", .{});
}
