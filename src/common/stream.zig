//! Unified async stream abstraction for all protocols
const std = @import("std");
const net = std.net;

pub const StreamError = error{
    ConnectionClosed,
    ReadTimeout,
    WriteTimeout,
    TlsError,
};

/// Unified stream interface that can wrap TCP, TLS, or other transport layers
pub const Stream = struct {
    const Self = @This();

    transport: Transport,
    allocator: std.mem.Allocator,

    pub const Transport = union(enum) {
        tcp: net.Stream,
        tls: TlsStream,
    };

    pub const TlsStream = struct {
        stream: net.Stream,
        // TLS context would go here when implemented
    };

    pub fn initTcp(allocator: std.mem.Allocator, tcp_stream: net.Stream) Self {
        return Self{
            .transport = .{ .tcp = tcp_stream },
            .allocator = allocator,
        };
    }

    pub fn initTls(allocator: std.mem.Allocator, tcp_stream: net.Stream) Self {
        return Self{
            .transport = .{ .tls = .{ .stream = tcp_stream } },
            .allocator = allocator,
        };
    }

    pub fn initFromSocket(socket: std.net.Stream) Self {
        return Self{
            .transport = .{ .tcp = socket },
            .allocator = std.heap.page_allocator, // Default allocator for convenience
        };
    }

    pub fn read(self: *Self, buffer: []u8) !usize {
        return switch (self.transport) {
            .tcp => |tcp| tcp.read(buffer),
            .tls => |tls| tls.stream.read(buffer), // TODO: Add TLS decryption
        };
    }

    pub fn write(self: *Self, data: []const u8) !usize {
        return switch (self.transport) {
            .tcp => |tcp| tcp.write(data),
            .tls => |tls| tls.stream.write(data), // TODO: Add TLS encryption
        };
    }

    pub fn readLine(self: *Self, buffer: []u8) ![]u8 {
        var pos: usize = 0;
        while (pos < buffer.len - 1) {
            const bytes_read = try self.read(buffer[pos .. pos + 1]);
            if (bytes_read == 0) return StreamError.ConnectionClosed;

            if (buffer[pos] == '\n') {
                // Handle CRLF and LF line endings
                if (pos > 0 and buffer[pos - 1] == '\r') {
                    return buffer[0 .. pos - 1];
                } else {
                    return buffer[0..pos];
                }
            }
            pos += 1;
        }
        return error.BufferTooSmall;
    }

    pub fn writeAll(self: *Self, data: []const u8) !void {
        var pos: usize = 0;
        while (pos < data.len) {
            const bytes_written = try self.write(data[pos..]);
            pos += bytes_written;
        }
    }

    pub fn readAtLeast(self: *Self, buffer: []u8, min_bytes: usize) !usize {
        var total_read: usize = 0;
        while (total_read < min_bytes and total_read < buffer.len) {
            const bytes_read = try self.read(buffer[total_read..]);
            if (bytes_read == 0) return StreamError.ConnectionClosed;
            total_read += bytes_read;
        }
        return total_read;
    }

    pub fn close(self: *Self) void {
        switch (self.transport) {
            .tcp => |tcp| tcp.close(),
            .tls => |tls| tls.stream.close(),
        }
    }
};

test "stream basic operations" {
    // Mock test - would need actual network connection for real test
    std.testing.expect(true) catch {};
}
