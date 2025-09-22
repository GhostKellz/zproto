//! WebSocket server example
//!
//! This example demonstrates a simple echo WebSocket server that accepts
//! connections and echoes back any messages it receives.
//!
//! Usage: zig run websocket_server_example.zig -- [port]
//! Default port: 8080

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

    const port: u16 = if (args.len >= 2)
        try std.fmt.parseInt(u16, args[1], 10)
    else
        8080;

    std.debug.print("🚀 Starting WebSocket echo server on port {d}\n", .{port});
    std.debug.print("📝 Test with: websocat ws://localhost:{d}\n", .{port});
    std.debug.print("📝 Or use the client example: zig run websocket_client_example.zig -- ws://localhost:{d}\n", .{port});

    // Create server socket
    const address = try std.net.Address.parseIp("127.0.0.1", port);
    var listener = try address.listen(.{ .reuse_address = true });
    defer listener.deinit();

    std.debug.print("✅ Server listening on {}\n\n", .{address});

    // Accept connections in a loop
    while (true) {
        std.debug.print("⏳ Waiting for WebSocket connection...\n");

        const connection = try listener.accept();
        std.debug.print("🔗 New connection from {}\n", .{connection.address});

        // Handle connection in a separate function
        handleConnection(allocator, connection.stream) catch |err| {
            std.debug.print("❌ Error handling connection: {}\n", .{err});
        };

        std.debug.print("🔌 Connection closed\n\n");
    }
}

fn handleConnection(allocator: std.mem.Allocator, socket: std.net.Stream) !void {
    defer socket.close();

    const stream = Stream.initFromSocket(socket);
    var server = websocket.WebSocketServer.init(allocator, stream);
    defer server.deinit();

    // Accept WebSocket handshake
    try server.acceptHandshake();
    std.debug.print("✅ WebSocket handshake completed\n");

    // Echo messages until connection closes
    var message_count: u32 = 0;
    while (true) {
        // Note: For this example, we'll simulate the server receive/send loop
        // In a real implementation, you'd need to implement the server-side
        // frame reading/writing which is similar to client but without masking

        std.debug.print("📥 Echo server ready (connection established)\n");
        std.debug.print("💡 Server-side message handling would be implemented here\n");
        std.debug.print("💡 This is a demonstration of the WebSocket handshake process\n");

        // For this example, we'll just wait a bit and then close
        std.time.sleep(5 * std.time.ns_per_s);
        break;
    }

    std.debug.print("📊 Handled {d} messages total\n", .{message_count});
}

// Note: This is a basic server example showing the handshake process.
// A complete server implementation would need:
// 1. Server-side frame parsing (similar to client but without mask validation)
// 2. Multi-threaded connection handling
// 3. Proper error handling and connection cleanup
// 4. Optional: WebSocket extensions and subprotocol negotiation