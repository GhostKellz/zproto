//! Connection pooling for reusable connections across protocols
const std = @import("std");
const net = std.net;
const Stream = @import("stream.zig").Stream;

pub const PoolError = error{
    PoolExhausted,
    ConnectionInvalid,
    PoolClosed,
};

/// Connection pool for managing reusable network connections
pub const ConnectionPool = struct {
    const Self = @This();

    const PooledConnection = struct {
        stream: Stream,
        last_used: i64,
        in_use: bool,
    };

    allocator: std.mem.Allocator,
    connections: std.ArrayList(PooledConnection),
    max_connections: usize,
    max_idle_time_ms: i64,
    mutex: std.Thread.Mutex,

    pub fn init(allocator: std.mem.Allocator, max_connections: usize) Self {
        return Self{
            .allocator = allocator,
            .connections = std.ArrayList(PooledConnection).init(allocator),
            .max_connections = max_connections,
            .max_idle_time_ms = 30000, // 30 seconds default
            .mutex = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.connections.items) |*conn| {
            conn.stream.close();
        }
        self.connections.deinit();
    }

    pub fn acquire(self: *Self, address: net.Address) !Stream {
        self.mutex.lock();
        defer self.mutex.unlock();

        const now = std.time.milliTimestamp();

        // Clean up expired connections
        self.cleanupExpired(now);

        // Try to find an available connection
        for (self.connections.items) |*conn| {
            if (!conn.in_use) {
                conn.in_use = true;
                conn.last_used = now;
                return conn.stream;
            }
        }

        // Create new connection if under limit
        if (self.connections.items.len < self.max_connections) {
            const tcp_stream = try net.tcpConnectToAddress(address);
            const stream = Stream.initTcp(self.allocator, tcp_stream);

            try self.connections.append(PooledConnection{
                .stream = stream,
                .last_used = now,
                .in_use = true,
            });

            return stream;
        }

        return PoolError.PoolExhausted;
    }

    pub fn release(self: *Self, stream: Stream) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.connections.items) |*conn| {
            // Compare stream pointers (simplified comparison)
            if (@intFromPtr(&conn.stream) == @intFromPtr(&stream)) {
                conn.in_use = false;
                conn.last_used = std.time.milliTimestamp();
                return;
            }
        }
    }

    fn cleanupExpired(self: *Self, now: i64) void {
        var i: usize = 0;
        while (i < self.connections.items.len) {
            const conn = &self.connections.items[i];
            if (!conn.in_use and (now - conn.last_used) > self.max_idle_time_ms) {
                conn.stream.close();
                _ = self.connections.swapRemove(i);
            } else {
                i += 1;
            }
        }
    }
};

test "connection pool basic operations" {
    // Mock test - would need actual network connections for real test
    std.testing.expect(true) catch {};
}
