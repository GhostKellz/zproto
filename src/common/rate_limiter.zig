//! Rate limiting utilities for client implementations
const std = @import("std");

pub const RateLimitError = error{
    RateLimitExceeded,
};

/// Token bucket rate limiter
pub const RateLimiter = struct {
    const Self = @This();

    tokens: f64,
    max_tokens: f64,
    refill_rate: f64, // tokens per second
    last_refill: i64,
    mutex: std.Thread.Mutex,

    pub fn init(max_tokens: f64, refill_rate: f64) Self {
        return Self{
            .tokens = max_tokens,
            .max_tokens = max_tokens,
            .refill_rate = refill_rate,
            .last_refill = std.time.milliTimestamp(),
            .mutex = .{},
        };
    }

    pub fn tryAcquire(self: *Self, tokens_requested: f64) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.refillTokens();

        if (self.tokens >= tokens_requested) {
            self.tokens -= tokens_requested;
        } else {
            return RateLimitError.RateLimitExceeded;
        }
    }

    pub fn waitForTokens(self: *Self, tokens_requested: f64) !void {
        while (true) {
            self.tryAcquire(tokens_requested) catch {
                // Wait and retry
                std.time.sleep(100 * std.time.ns_per_ms); // 100ms
                continue;
            };
            break;
        }
    }

    fn refillTokens(self: *Self) void {
        const now = std.time.milliTimestamp();
        const time_passed = @as(f64, @floatFromInt(now - self.last_refill)) / 1000.0; // Convert to seconds

        const tokens_to_add = time_passed * self.refill_rate;
        self.tokens = @min(self.max_tokens, self.tokens + tokens_to_add);
        self.last_refill = now;
    }

    pub fn getAvailableTokens(self: *Self) f64 {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.refillTokens();
        return self.tokens;
    }
};

test "rate limiter basic operations" {
    var limiter = RateLimiter.init(10.0, 1.0); // 10 tokens max, 1 per second

    // Should be able to acquire initially
    try limiter.tryAcquire(5.0);

    // Should still have tokens
    try limiter.tryAcquire(5.0);

    // Should be out of tokens now
    try std.testing.expectError(RateLimitError.RateLimitExceeded, limiter.tryAcquire(1.0));
}
