const std = @import("std");
const zproto = @import("zproto");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== POP3 Client Example ===\n", .{});

    // Create POP3 client
    var pop3_client = zproto.pop3.Pop3Client.init(allocator);
    defer pop3_client.deinit();

    // Example 1: Plain POP3 connection
    std.debug.print("\n1. Plain POP3 Connection Example:\n", .{});

    const plain_config = zproto.pop3.Pop3Config{
        .host = "pop.example.com",
        .port = 110,
        .security = .none,
        .auth_method = .user_pass,
        .username = "your-username",
        .password = "your-password",
    };

    pop3_client.connect(plain_config) catch |err| {
        std.debug.print("Failed to connect to POP3 server: {}\n", .{err});
        std.debug.print("(Configure with real server credentials to test)\n", .{});
    };

    // Example 2: POP3S (implicit TLS) connection
    std.debug.print("\n2. POP3S (Implicit TLS) Example:\n", .{});

    const pop3s_config = zproto.pop3.Pop3Config{
        .host = "pop.gmail.com",
        .port = 995,
        .security = .implicit,
        .auth_method = .user_pass,
        .username = "your-email@gmail.com",
        .password = "your-app-password",
    };

    pop3_client.connect(pop3s_config) catch |err| {
        std.debug.print("Failed to connect to POP3S server: {}\n", .{err});
        std.debug.print("(Configure with real Gmail credentials to test)\n", .{});
    };

    // Example 3: STARTTLS connection
    std.debug.print("\n3. STARTTLS Example:\n", .{});

    const starttls_config = zproto.pop3.Pop3Config{
        .host = "pop.gmail.com",
        .port = 110,
        .security = .starttls,
        .auth_method = .sasl_plain,
        .username = "your-email@gmail.com",
        .password = "your-app-password",
    };

    pop3_client.connect(starttls_config) catch |err| {
        std.debug.print("Failed to connect with STARTTLS: {}\n", .{err});
        std.debug.print("(Configure with real credentials to test)\n", .{});
    };

    // Simulate POP3 operations (these would work with a real connection)
    std.debug.print("\n4. POP3 Operations Example:\n", .{});

    // Example: Get message count
    std.debug.print("Getting message count...\n", .{});
    const message_count = pop3_client.getMessageCount() catch |err| {
        std.debug.print("Failed to get message count: {}\n", .{err});
        std.debug.print("(Would work with real connection)\n", .{});
        std.debug.print("Example: 5 messages in mailbox\n", .{});

        // Example: List messages
        std.debug.print("\nListing messages...\n", .{});
        const messages = pop3_client.listMessages() catch |err2| {
            std.debug.print("Failed to list messages: {}\n", .{err2});
            std.debug.print("Example message list that would be returned:\n", .{});
            std.debug.print("  Message 1: 2048 bytes\n", .{});
            std.debug.print("  Message 2: 3172 bytes\n", .{});
            std.debug.print("  Message 3: 1024 bytes\n", .{});
            std.debug.print("  Message 4: 4096 bytes\n", .{});
            std.debug.print("  Message 5: 1536 bytes\n", .{});

            // Example: Get unique IDs
            std.debug.print("\nGetting unique IDs...\n", .{});
            const uid_messages = pop3_client.getUniqueIds() catch |err3| {
                std.debug.print("Failed to get unique IDs: {}\n", .{err3});
                std.debug.print("Example unique IDs that would be returned:\n", .{});
                std.debug.print("  Message 1: uid=msg001@example.com\n", .{});
                std.debug.print("  Message 2: uid=msg002@example.com\n", .{});
                std.debug.print("  Message 3: uid=msg003@example.com\n", .{});
                std.debug.print("  Message 4: uid=msg004@example.com\n", .{});
                std.debug.print("  Message 5: uid=msg005@example.com\n", .{});

                // Example: Retrieve message headers
                std.debug.print("\nRetrieving message 1 headers (TOP command)...\n", .{});
                const headers = pop3_client.retrieveMessageTop(1, 0) catch |err4| {
                    std.debug.print("Failed to retrieve message headers: {}\n", .{err4});
                    std.debug.print("Example headers that would be returned:\n", .{});
                    std.debug.print("From: sender@example.com\n", .{});
                    std.debug.print("To: recipient@example.com\n", .{});
                    std.debug.print("Subject: Important message\n", .{});
                    std.debug.print("Date: Mon, 21 Sep 2025 10:30:00 +0000\n", .{});
                    std.debug.print("Content-Type: text/plain; charset=utf-8\n", .{});

                    // Example: Retrieve full message
                    std.debug.print("\nRetrieving full message 1...\n", .{});
                    const full_message = pop3_client.retrieveMessage(1) catch |err5| {
                        std.debug.print("Failed to retrieve full message: {}\n", .{err5});
                        std.debug.print("Example full message that would be returned:\n", .{});
                        std.debug.print("Headers + Body content (truncated for display)\n", .{});

                        // Example: Delete message
                        std.debug.print("\nMarking message 1 for deletion...\n", .{});
                        pop3_client.deleteMessage(1) catch |err6| {
                            std.debug.print("Failed to mark message for deletion: {}\n", .{err6});
                            std.debug.print("(Message would be marked for deletion on QUIT)\n", .{});
                        };

                        // Example: Reset session
                        std.debug.print("\nResetting session (unmark deletions)...\n", .{});
                        pop3_client.resetSession() catch |err7| {
                            std.debug.print("Failed to reset session: {}\n", .{err7});
                            std.debug.print("(All deletion marks would be cleared)\n", .{});
                        };

                        return;
                    };
                    defer full_message.deinit();

                    std.debug.print("Successfully retrieved message:\n", .{});
                    std.debug.print("  Headers length: {} bytes\n", .{full_message.headers.len});
                    std.debug.print("  Body length: {} bytes\n", .{full_message.body.len});
                    std.debug.print("  Total length: {} bytes\n", .{full_message.full_message.len});

                    return;
                };
                defer headers.deinit();

                std.debug.print("Successfully retrieved headers:\n", .{});
                std.debug.print("  Headers length: {} bytes\n", .{headers.headers.len});
                if (headers.body.len > 0) {
                    std.debug.print("  Body preview length: {} bytes\n", .{headers.body.len});
                }

                return;
            };
            defer {
                for (uid_messages.items) |*msg| {
                    msg.deinit();
                }
                uid_messages.deinit();
            }

            std.debug.print("Successfully retrieved {} unique IDs\n", .{uid_messages.items.len});
            for (uid_messages.items) |message| {
                if (message.uid) |uid| {
                    std.debug.print("  Message {}: uid={s}\n", .{ message.message_number, uid });
                }
            }

            return;
        };
        defer {
            for (messages.items) |*msg| {
                msg.deinit();
            }
            messages.deinit();
        }

        std.debug.print("Successfully listed {} messages\n", .{messages.items.len});
        for (messages.items) |message| {
            std.debug.print("  Message {}: {} bytes\n", .{ message.message_number, message.size });
        }

        return;
    };

    std.debug.print("Mailbox contains {} messages\n", .{message_count});

    // Example: Quit and apply changes
    std.debug.print("\nQuitting (applying any deletions)...\n", .{});
    pop3_client.quit() catch |err| {
        std.debug.print("Failed to quit cleanly: {}\n", .{err});
    };

    std.debug.print("\n=== Example completed ===\n", .{});
    std.debug.print("Note: To actually download emails, configure with real POP3 server credentials.\n", .{});
}
