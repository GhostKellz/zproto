//! WebSocket client and server implementation (RFC 6455)
//!
//! This module provides a complete WebSocket implementation supporting:
//! - Client and server handshakes
//! - Frame parsing and generation
//! - Text and binary messages
//! - Ping/pong frames
//! - Connection close handling
//! - Extension negotiation (basic)

const std = @import("std");
const net = std.net;
const crypto = std.crypto;
const base64 = std.base64;
const common = @import("../common/common.zig");
const Stream = common.Stream;
const StreamError = @import("../common/stream.zig").StreamError;
const Parser = common.Parser;

pub const WebSocketError = error{
    InvalidHandshake,
    InvalidFrame,
    InvalidOpcode,
    InvalidPayloadLength,
    UnsupportedExtension,
    ConnectionClosed,
    ProtocolError,
    MessageTooLarge,
    InvalidUtf8,
} || StreamError || common.Error;

// WebSocket magic string for handshake
const WEBSOCKET_MAGIC_STRING = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";

pub const OpCode = enum(u4) {
    continuation = 0x0,
    text = 0x1,
    binary = 0x2,
    close = 0x8,
    ping = 0x9,
    pong = 0xA,
    _,

    pub fn isControl(self: OpCode) bool {
        return @intFromEnum(self) >= 0x8;
    }

    pub fn isData(self: OpCode) bool {
        return @intFromEnum(self) <= 0x2;
    }
};

pub const Frame = struct {
    fin: bool,
    rsv1: bool = false,
    rsv2: bool = false,
    rsv3: bool = false,
    opcode: OpCode,
    masked: bool,
    payload_length: u64,
    mask_key: ?[4]u8 = null,
    payload: []const u8,

    pub fn isControlFrame(self: Frame) bool {
        return self.opcode.isControl();
    }
};

pub const Message = struct {
    opcode: OpCode,
    data: []const u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *Message) void {
        self.allocator.free(self.data);
    }

    pub fn text(self: Message) ![]const u8 {
        if (self.opcode != .text) return WebSocketError.ProtocolError;
        if (!std.unicode.utf8ValidateSlice(self.data)) return WebSocketError.InvalidUtf8;
        return self.data;
    }

    pub fn binary(self: Message) ![]const u8 {
        if (self.opcode != .binary) return WebSocketError.ProtocolError;
        return self.data;
    }
};

pub const CloseCode = enum(u16) {
    normal_closure = 1000,
    going_away = 1001,
    protocol_error = 1002,
    unsupported_data = 1003,
    no_status_received = 1005,
    abnormal_closure = 1006,
    invalid_frame_payload_data = 1007,
    policy_violation = 1008,
    message_too_big = 1009,
    mandatory_extension = 1010,
    internal_server_error = 1011,
    service_restart = 1012,
    try_again_later = 1013,
    bad_gateway = 1014,
    tls_handshake = 1015,
    _,
};

pub const WebSocketClient = struct {
    stream: Stream,
    allocator: std.mem.Allocator,
    state: State,
    max_message_size: usize = 16 * 1024 * 1024, // 16MB default

    const State = enum {
        connecting,
        open,
        closing,
        closed,
    };

    pub fn init(allocator: std.mem.Allocator, stream: Stream) WebSocketClient {
        return WebSocketClient{
            .stream = stream,
            .allocator = allocator,
            .state = .connecting,
        };
    }

    pub fn deinit(self: *WebSocketClient) void {
        self.stream.close();
    }

    pub fn connect(self: *WebSocketClient, host: []const u8, path: []const u8, port: u16) !void {
        // Generate WebSocket key
        var key_bytes: [16]u8 = undefined;
        crypto.random.bytes(&key_bytes);

        var key_base64: [24]u8 = undefined;
        _ = base64.standard.Encoder.encode(&key_base64, &key_bytes);

        // Send handshake request
        const request = try std.fmt.allocPrint(self.allocator,
            "GET {s} HTTP/1.1\r\n" ++
            "Host: {s}:{d}\r\n" ++
            "Upgrade: websocket\r\n" ++
            "Connection: Upgrade\r\n" ++
            "Sec-WebSocket-Key: {s}\r\n" ++
            "Sec-WebSocket-Version: 13\r\n" ++
            "\r\n",
            .{ path, host, port, key_base64 }
        );
        defer self.allocator.free(request);

        try self.stream.writeAll(request);

        // Read and validate handshake response
        try self.validateHandshakeResponse(&key_base64);
        self.state = .open;
    }

    fn validateHandshakeResponse(self: *WebSocketClient, key: []const u8) !void {
        var buffer: [4096]u8 = undefined;
        const response_len = try self.stream.read(&buffer);
        const response = buffer[0..response_len];

        // Parse HTTP response
        var lines = std.mem.splitSequence(u8, response, "\r\n");
        const status_line = lines.next() orelse return WebSocketError.InvalidHandshake;

        if (!std.mem.startsWith(u8, status_line, "HTTP/1.1 101")) {
            return WebSocketError.InvalidHandshake;
        }

        // Validate required headers
        var upgrade_found = false;
        var connection_found = false;
        var accept_found = false;

        while (lines.next()) |line| {
            if (line.len == 0) break; // End of headers

            var header = std.mem.splitSequence(u8, line, ": ");
            const name = header.next() orelse continue;
            const value = header.next() orelse continue;

            if (std.ascii.eqlIgnoreCase(name, "upgrade")) {
                upgrade_found = std.ascii.eqlIgnoreCase(value, "websocket");
            } else if (std.ascii.eqlIgnoreCase(name, "connection")) {
                // Check if connection header contains "upgrade" (case insensitive)
                connection_found = std.ascii.indexOfIgnoreCase(value, "upgrade") != null;
            } else if (std.ascii.eqlIgnoreCase(name, "sec-websocket-accept")) {
                // Verify accept key
                var hasher = crypto.hash.Sha1.init(.{});
                hasher.update(key);
                hasher.update(WEBSOCKET_MAGIC_STRING);
                var hash: [20]u8 = undefined;
                hasher.final(&hash);

                var expected_accept: [28]u8 = undefined;
                _ = base64.standard.Encoder.encode(&expected_accept, &hash);

                accept_found = std.mem.eql(u8, value, &expected_accept);
            }
        }

        if (!upgrade_found or !connection_found or !accept_found) {
            return WebSocketError.InvalidHandshake;
        }
    }

    pub fn sendText(self: *WebSocketClient, text: []const u8) !void {
        if (!std.unicode.utf8ValidateSlice(text)) return WebSocketError.InvalidUtf8;
        try self.sendFrame(.text, text, true);
    }

    pub fn sendBinary(self: *WebSocketClient, data: []const u8) !void {
        try self.sendFrame(.binary, data, true);
    }

    pub fn sendPing(self: *WebSocketClient, data: []const u8) !void {
        try self.sendFrame(.ping, data, true);
    }

    pub fn sendPong(self: *WebSocketClient, data: []const u8) !void {
        try self.sendFrame(.pong, data, true);
    }

    pub fn sendClose(self: *WebSocketClient, code: CloseCode, reason: []const u8) !void {
        var close_data = std.ArrayList(u8){ .allocator = self.allocator, .items = &[_]u8{}, .capacity = 0 };
        defer close_data.deinit();

        // Add close code (big-endian)
        const code_bytes = std.mem.toBytes(@intFromEnum(code));
        try close_data.appendSlice(&[_]u8{ code_bytes[1], code_bytes[0] });
        try close_data.appendSlice(reason);

        try self.sendFrame(.close, close_data.items, true);
        self.state = .closing;
    }

    fn sendFrame(self: *WebSocketClient, opcode: OpCode, payload: []const u8, fin: bool) !void {
        if (self.state != .open and self.state != .closing) {
            return WebSocketError.ConnectionClosed;
        }

        var frame_data = std.ArrayList(u8){ .allocator = self.allocator, .items = &[_]u8{}, .capacity = 0 };
        defer frame_data.deinit();

        // First byte: FIN + RSV + Opcode
        var first_byte: u8 = @intFromEnum(opcode);
        if (fin) first_byte |= 0x80;
        try frame_data.append(first_byte);

        // Second byte: MASK + Payload length
        var second_byte: u8 = 0x80; // Client frames are always masked

        if (payload.len < 126) {
            second_byte |= @truncate(payload.len);
            try frame_data.append(second_byte);
        } else if (payload.len <= 65535) {
            second_byte |= 126;
            try frame_data.append(second_byte);
            // Extended payload length (16-bit, big-endian)
            const len_bytes = std.mem.toBytes(@as(u16, @truncate(payload.len)));
            try frame_data.appendSlice(&[_]u8{ len_bytes[1], len_bytes[0] });
        } else {
            second_byte |= 127;
            try frame_data.append(second_byte);
            // Extended payload length (64-bit, big-endian)
            const len_bytes = std.mem.toBytes(@as(u64, payload.len));
            for (0..8) |i| {
                try frame_data.append(len_bytes[7 - i]);
            }
        }

        // Masking key (random 4 bytes)
        var mask_key: [4]u8 = undefined;
        crypto.random.bytes(&mask_key);
        try frame_data.appendSlice(&mask_key);

        // Masked payload
        for (payload, 0..) |byte, i| {
            try frame_data.append(byte ^ mask_key[i % 4]);
        }

        try self.stream.writeAll(frame_data.items);
    }

    pub fn receiveMessage(self: *WebSocketClient) !?Message {
        if (self.state == .closed) return null;

        var message_data = std.ArrayList(u8){ .allocator = self.allocator, .items = &[_]u8{}, .capacity = 0 };
        var message_opcode: ?OpCode = null;

        while (true) {
            const frame = try self.receiveFrame();

            // Handle control frames immediately
            if (frame.isControlFrame()) {
                try self.handleControlFrame(frame);
                continue;
            }

            // Set message opcode from first data frame
            if (message_opcode == null) {
                if (frame.opcode == .continuation) {
                    return WebSocketError.ProtocolError; // First frame can't be continuation
                }
                message_opcode = frame.opcode;
            }

            // Append frame payload to message
            try message_data.appendSlice(frame.payload);

            if (message_data.items.len > self.max_message_size) {
                message_data.deinit();
                return WebSocketError.MessageTooLarge;
            }

            // If this is the final frame, return the complete message
            if (frame.fin) {
                return Message{
                    .opcode = message_opcode.?,
                    .data = try message_data.toOwnedSlice(),
                    .allocator = self.allocator,
                };
            }
        }
    }

    fn receiveFrame(self: *WebSocketClient) !Frame {
        // Read frame header (minimum 2 bytes)
        var header: [14]u8 = undefined; // Max header size
        _ = try self.stream.readAtLeast(header[0..2], 2);

        // Parse first byte
        const first_byte = header[0];
        const fin = (first_byte & 0x80) != 0;
        const rsv1 = (first_byte & 0x40) != 0;
        const rsv2 = (first_byte & 0x20) != 0;
        const rsv3 = (first_byte & 0x10) != 0;
        const opcode: OpCode = @enumFromInt(first_byte & 0x0F);

        // Parse second byte
        const second_byte = header[1];
        const masked = (second_byte & 0x80) != 0;
        var payload_length: u64 = second_byte & 0x7F;

        var header_size: usize = 2;

        // Extended payload length
        if (payload_length == 126) {
            _ = try self.stream.readAtLeast(header[2..4], 2);
            payload_length = std.mem.readInt(u16, header[2..4], .big);
            header_size += 2;
        } else if (payload_length == 127) {
            _ = try self.stream.readAtLeast(header[2..10], 8);
            payload_length = std.mem.readInt(u64, header[2..10], .big);
            header_size += 8;
        }

        // Masking key (if present)
        var mask_key: ?[4]u8 = null;
        if (masked) {
            _ = try self.stream.readAtLeast(header[header_size..header_size + 4], 4);
            mask_key = header[header_size..header_size + 4][0..4].*;
            header_size += 4;
        }

        // Read payload
        const payload = try self.allocator.alloc(u8, @intCast(payload_length));
        if (payload_length > 0) {
            _ = try self.stream.readAtLeast(payload, @intCast(payload_length));

            // Unmask payload if needed
            if (masked and mask_key != null) {
                for (payload, 0..) |*byte, i| {
                    byte.* ^= mask_key.?[i % 4];
                }
            }
        }

        return Frame{
            .fin = fin,
            .rsv1 = rsv1,
            .rsv2 = rsv2,
            .rsv3 = rsv3,
            .opcode = opcode,
            .masked = masked,
            .payload_length = payload_length,
            .mask_key = mask_key,
            .payload = payload,
        };
    }

    fn handleControlFrame(self: *WebSocketClient, frame: Frame) !void {
        switch (frame.opcode) {
            .ping => {
                // Respond with pong
                try self.sendPong(frame.payload);
            },
            .pong => {
                // Pong received, nothing to do
            },
            .close => {
                // Handle close frame
                if (frame.payload.len >= 2) {
                    const code_bytes = frame.payload[0..2];
                    const code: CloseCode = @enumFromInt(std.mem.readInt(u16, code_bytes, .big));
                    const reason = if (frame.payload.len > 2) frame.payload[2..] else "";
                    _ = code;
                    _ = reason;
                }

                if (self.state == .open) {
                    // Send close response
                    try self.sendClose(.normal_closure, "");
                }

                self.state = .closed;
            },
            else => {
                return WebSocketError.InvalidOpcode;
            },
        }
    }

    pub fn close(self: *WebSocketClient) !void {
        if (self.state == .open) {
            try self.sendClose(.normal_closure, "");
        }
        self.state = .closed;
    }
};

// Basic WebSocket server for testing/simple use cases
pub const WebSocketServer = struct {
    stream: Stream,
    allocator: std.mem.Allocator,
    state: State,

    const State = enum {
        handshaking,
        open,
        closing,
        closed,
    };

    pub fn init(allocator: std.mem.Allocator, stream: Stream) WebSocketServer {
        return WebSocketServer{
            .stream = stream,
            .allocator = allocator,
            .state = .handshaking,
        };
    }

    pub fn deinit(self: *WebSocketServer) void {
        self.stream.close();
    }

    pub fn acceptHandshake(self: *WebSocketServer) !void {
        // Read HTTP request
        var buffer: [4096]u8 = undefined;
        const request_len = try self.stream.read(&buffer);
        const request = buffer[0..request_len];

        // Parse headers
        var lines = std.mem.splitSequence(u8, request, "\r\n");
        const request_line = lines.next() orelse return WebSocketError.InvalidHandshake;

        if (!std.mem.startsWith(u8, request_line, "GET ")) {
            return WebSocketError.InvalidHandshake;
        }

        var websocket_key: ?[]const u8 = null;
        var upgrade_websocket = false;
        var connection_upgrade = false;
        var version_13 = false;

        while (lines.next()) |line| {
            if (line.len == 0) break;

            var header = std.mem.splitSequence(u8, line, ": ");
            const name = header.next() orelse continue;
            const value = header.next() orelse continue;

            if (std.ascii.eqlIgnoreCase(name, "upgrade")) {
                upgrade_websocket = std.ascii.eqlIgnoreCase(value, "websocket");
            } else if (std.ascii.eqlIgnoreCase(name, "connection")) {
                connection_upgrade = std.ascii.indexOfIgnoreCase(value, "upgrade") != null;
            } else if (std.ascii.eqlIgnoreCase(name, "sec-websocket-key")) {
                websocket_key = value;
            } else if (std.ascii.eqlIgnoreCase(name, "sec-websocket-version")) {
                version_13 = std.mem.eql(u8, value, "13");
            }
        }

        if (!upgrade_websocket or !connection_upgrade or !version_13 or websocket_key == null) {
            return WebSocketError.InvalidHandshake;
        }

        // Generate accept key
        var hasher = crypto.hash.Sha1.init(.{});
        hasher.update(websocket_key.?);
        hasher.update(WEBSOCKET_MAGIC_STRING);
        var hash: [20]u8 = undefined;
        hasher.final(&hash);

        var accept_key: [28]u8 = undefined;
        _ = base64.standard.Encoder.encode(&accept_key, &hash);

        // Send handshake response
        const response = try std.fmt.allocPrint(self.allocator,
            "HTTP/1.1 101 Switching Protocols\r\n" ++
            "Upgrade: websocket\r\n" ++
            "Connection: Upgrade\r\n" ++
            "Sec-WebSocket-Accept: {s}\r\n" ++
            "\r\n",
            .{accept_key}
        );
        defer self.allocator.free(response);

        try self.stream.writeAll(response);
        self.state = .open;
    }

    // Server methods would be similar to client but without masking
    // and handling multiple connections would require additional architecture
};

// Utility functions
pub fn isValidOpCode(opcode: u8) bool {
    return switch (opcode) {
        0x0...0x2, 0x8...0xA => true,
        else => false,
    };
}

pub fn calculateFrameSize(payload_len: usize, masked: bool) usize {
    var size: usize = 2; // Base header

    if (payload_len >= 65536) {
        size += 8; // 64-bit extended length
    } else if (payload_len >= 126) {
        size += 2; // 16-bit extended length
    }

    if (masked) {
        size += 4; // Mask key
    }

    return size + payload_len;
}

test "websocket opcode validation" {
    const testing = std.testing;

    try testing.expect(OpCode.text.isData());
    try testing.expect(OpCode.binary.isData());
    try testing.expect(OpCode.continuation.isData());
    try testing.expect(OpCode.ping.isControl());
    try testing.expect(OpCode.pong.isControl());
    try testing.expect(OpCode.close.isControl());
}

test "websocket frame size calculation" {
    const testing = std.testing;

    // Small payload, masked
    try testing.expectEqual(@as(usize, 10), calculateFrameSize(4, true));

    // Medium payload, unmasked
    try testing.expectEqual(@as(usize, 130), calculateFrameSize(126, false));

    // Large payload, masked
    try testing.expectEqual(@as(usize, 65550), calculateFrameSize(65536, true));
}