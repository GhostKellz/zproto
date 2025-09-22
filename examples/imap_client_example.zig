const std = @import("std");
const zproto = @import("zproto");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== IMAP Client Example ===\n", .{});

    // Create IMAP client
    var imap_client = zproto.imap.ImapClient.init(allocator);
    defer imap_client.deinit();

    // Example 1: Plain IMAP connection
    std.debug.print("\n1. Plain IMAP Connection Example:\n", .{});

    const plain_config = zproto.imap.ImapConfig{
        .host = "imap.example.com",
        .port = 143,
        .security = .none,
        .auth_method = .login,
        .username = "your-username",
        .password = "your-password",
    };

    imap_client.connect(plain_config) catch |err| {
        std.debug.print("Failed to connect to IMAP server: {}\n", .{err});
        std.debug.print("(Configure with real server credentials to test)\n", .{});
    };

    // Example 2: IMAPS (implicit TLS) connection
    std.debug.print("\n2. IMAPS (Implicit TLS) Example:\n", .{});

    const imaps_config = zproto.imap.ImapConfig{
        .host = "imap.gmail.com",
        .port = 993,
        .security = .implicit,
        .auth_method = .plain,
        .username = "your-email@gmail.com",
        .password = "your-app-password",
    };

    imap_client.connect(imaps_config) catch |err| {
        std.debug.print("Failed to connect to IMAPS server: {}\n", .{err});
        std.debug.print("(Configure with real Gmail credentials to test)\n", .{});
    };

    // Example 3: STARTTLS connection
    std.debug.print("\n3. STARTTLS Example:\n", .{});

    const starttls_config = zproto.imap.ImapConfig{
        .host = "imap.gmail.com",
        .port = 143,
        .security = .starttls,
        .auth_method = .login,
        .username = "your-email@gmail.com",
        .password = "your-app-password",
    };

    imap_client.connect(starttls_config) catch |err| {
        std.debug.print("Failed to connect with STARTTLS: {}\n", .{err});
        std.debug.print("(Configure with real credentials to test)\n", .{});
    };

    // Simulate IMAP operations (these would work with a real connection)
    std.debug.print("\n4. IMAP Operations Example:\n", .{});

    // Example: List mailboxes
    std.debug.print("Listing mailboxes...\n", .{});
    const mailboxes = imap_client.listMailboxes("", "*") catch |err| {
        std.debug.print("Failed to list mailboxes: {}\n", .{err});
        std.debug.print("(Would work with real connection)\n", .{});
        std.debug.print("Example mailboxes that might be returned:\n", .{});
        std.debug.print("  - INBOX\n", .{});
        std.debug.print("  - Sent\n", .{});
        std.debug.print("  - Drafts\n", .{});
        std.debug.print("  - Trash\n", .{});

        // Example of selecting a mailbox
        std.debug.print("\nSelecting INBOX...\n", .{});
        const mailbox_info = imap_client.selectMailbox("INBOX") catch |err2| {
            std.debug.print("Failed to select INBOX: {}\n", .{err2});
            std.debug.print("Example mailbox info that would be returned:\n", .{});
            std.debug.print("  - Name: INBOX\n", .{});
            std.debug.print("  - Messages: 42\n", .{});
            std.debug.print("  - Recent: 2\n", .{});
            std.debug.print("  - Unseen: 5\n", .{});

            // Example of fetching messages
            std.debug.print("\nFetching messages 1:10...\n", .{});
            const messages = imap_client.fetchMessages("1:10", "(FLAGS ENVELOPE RFC822.SIZE)") catch |err3| {
                std.debug.print("Failed to fetch messages: {}\n", .{err3});
                std.debug.print("Example message info that would be returned:\n", .{});
                std.debug.print("  Message 1:\n", .{});
                std.debug.print("    - UID: 1001\n", .{});
                std.debug.print("    - Flags: [\\Seen]\n", .{});
                std.debug.print("    - Subject: Welcome to your new email account\n", .{});
                std.debug.print("    - From: admin@example.com\n", .{});
                std.debug.print("    - Size: 2048 bytes\n", .{});

                std.debug.print("  Message 2:\n", .{});
                std.debug.print("    - UID: 1002\n", .{});
                std.debug.print("    - Flags: [\\Seen, \\Flagged]\n", .{});
                std.debug.print("    - Subject: Important update\n", .{});
                std.debug.print("    - From: notifications@example.com\n", .{});
                std.debug.print("    - Size: 3072 bytes\n", .{});

                // Clean up would happen here
                return;
            };
            defer messages.deinit();

            std.debug.print("Successfully fetched {} messages\n", .{messages.items.len});
            for (messages.items, 0..) |message, i| {
                std.debug.print("  Message {}: sequence={}, uid={?}\n", .{ i + 1, message.sequence_number, message.uid });
            }

            return;
        };
        defer mailbox_info.deinit();

        std.debug.print("Successfully selected mailbox: {s}\n", .{mailbox_info.name});
        std.debug.print("  Messages: {}\n", .{mailbox_info.exists});
        std.debug.print("  Recent: {}\n", .{mailbox_info.recent});

        return;
    };
    defer {
        for (mailboxes.items) |mailbox| {
            allocator.free(mailbox);
        }
        mailboxes.deinit();
    }

    std.debug.print("Successfully listed {} mailboxes\n", .{mailboxes.items.len});
    for (mailboxes.items) |mailbox| {
        std.debug.print("  - {s}\n", .{mailbox});
    }

    // Example: Logout
    std.debug.print("\nLogging out...\n", .{});
    imap_client.logout() catch |err| {
        std.debug.print("Failed to logout: {}\n", .{err});
    };

    std.debug.print("\n=== Example completed ===\n", .{});
    std.debug.print("Note: To actually access mailboxes, configure with real IMAP server credentials.\n", .{});
}
