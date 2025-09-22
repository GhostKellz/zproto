//! WebSocket client example
//!
//! This example demonstrates how to use the WebSocket client to connect to a server,
//! send messages, and receive responses.
//!
//! Usage: zig run websocket_client_example.zig -- ws://echo.websocket.org

const std = @import("std");
const zproto = @import("zproto");
const websocket = zproto.websocket;
const Stream = zproto.Stream;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse command line arguments
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print("Usage: {s} <websocket-url>\n", .{args[0]});
        std.debug.print("Example: {s} ws://echo.websocket.org\n", .{args[0]});
        return;
    }

    const url = args[1];

    // Parse WebSocket URL (basic parsing for example)
    if (!std.mem.startsWith(u8, url, "ws://")) {
        std.debug.print("Error: Only ws:// URLs supported in this example\n", .{});
        return;
    }

    const url_without_prefix = url[5..]; // Remove "ws://"
    var parts = std.mem.splitScalar(u8, url_without_prefix, '/');
    const host_port = parts.next() orelse return error.InvalidUrl;

    var host_port_split = std.mem.splitScalar(u8, host_port, ':');
    const host = host_port_split.next() orelse return error.InvalidUrl;
    const port_str = host_port_split.next() orelse "80";
    const port = try std.fmt.parseInt(u16, port_str, 10);

    // Build path
    var path_buffer: [256]u8 = undefined;
    var path_len: usize = 1; // Start with "/"
    path_buffer[0] = '/';

    while (parts.next()) |segment| {
        if (path_len + segment.len + 1 < path_buffer.len) {
            @memcpy(path_buffer[path_len..path_len + segment.len], segment);
            path_len += segment.len;
            const remaining = parts.rest();
            if (remaining.len > 0) {
                path_buffer[path_len] = '/';
                path_len += 1;
            }
        }
    }
    const path = path_buffer[0..path_len];

    std.debug.print("Connecting to WebSocket server...\n", .{});
    std.debug.print("Host: {s}, Port: {d}, Path: {s}\n", .{ host, port, path });

    // Connect to server
    const address = try std.net.Address.resolveIp(host, port);
    const socket = try std.net.tcpConnectToAddress(address);
    defer socket.close();

    const stream = Stream.initFromSocket(socket);
    var client = websocket.WebSocketClient.init(allocator, stream);
    defer client.deinit();

    // Perform WebSocket handshake
    try client.connect(host, path, port);
    std.debug.print("✅ WebSocket connection established!\n", .{});

    // Send some test messages
    try client.sendText("Hello from Zig WebSocket client!");
    std.debug.print("📤 Sent text message: 'Hello from Zig WebSocket client!'\n", .{});

    try client.sendBinary(&[_]u8{ 0x01, 0x02, 0x03, 0x04 });
    std.debug.print("📤 Sent binary message: [0x01, 0x02, 0x03, 0x04]\n", .{});

    try client.sendPing("ping-data");
    std.debug.print("📤 Sent ping: 'ping-data'\n", .{});

    // Receive and display messages for a few seconds
    std.debug.print("\n📥 Listening for messages (5 seconds)...\n", .{});

    const start_time = std.time.timestamp();
    while (std.time.timestamp() - start_time < 5) {
        if (client.receiveMessage()) |maybe_message| {
            if (maybe_message) |message| {
                defer {
                    var mut_message = message;
                    mut_message.deinit();
                }

                switch (message.opcode) {
                    .text => {
                        const text = try message.text();
                        std.debug.print("📥 Received text: '{s}'\n", .{text});
                    },
                    .binary => {
                        const data = try message.binary();
                        std.debug.print("📥 Received binary ({d} bytes): ", .{data.len});
                        for (data) |byte| {
                            std.debug.print("{:02X} ", .{byte});
                        }
                        std.debug.print("\n", .{});
                    },
                    else => {
                        std.debug.print("📥 Received message with opcode: {}\n", .{message.opcode});
                    },
                }
            }
        } else |err| switch (err) {
            error.WouldBlock => {
                // No message available, continue
                std.time.sleep(100 * std.time.ns_per_ms);
                continue;
            },
            else => return err,
        }
    }

    // Close connection gracefully
    std.debug.print("\n🔌 Closing WebSocket connection...\n", .{});
    try client.close();
    std.debug.print("✅ WebSocket connection closed.\n", .{});
}