//! Authentication and credential management utilities
const std = @import("std");
const crypto = std.crypto;

pub const AuthError = error{
    InvalidCredentials,
    UnsupportedMethod,
    HashFailed,
};

/// Authentication methods supported across protocols
pub const AuthMethod = enum {
    none,
    plain,
    login,
    digest_md5,
    oauth2,
    basic_auth,
    ntlm,
};

/// Generic credential storage
pub const Credentials = struct {
    username: []const u8,
    password: []const u8,
    domain: ?[]const u8 = null,
    token: ?[]const u8 = null,
};

/// Authentication helper utilities
pub const Auth = struct {
    const Self = @This();

    /// Encode credentials for HTTP Basic Authentication
    pub fn encodeBasicAuth(allocator: std.mem.Allocator, username: []const u8, password: []const u8) ![]u8 {
        const credentials = try std.fmt.allocPrint(allocator, "{s}:{s}", .{ username, password });
        defer allocator.free(credentials);

        const encoder = std.base64.standard.Encoder;
        const encoded_len = encoder.calcSize(credentials.len);
        const encoded = try allocator.alloc(u8, encoded_len);

        _ = encoder.encode(encoded, credentials);
        return encoded;
    }

    /// Generate DIGEST-MD5 response (simplified version)
    pub fn generateDigestMd5Response(allocator: std.mem.Allocator, username: []const u8, password: []const u8, realm: []const u8, nonce: []const u8, uri: []const u8) ![]u8 {
        // HA1 = MD5(username:realm:password)
        const ha1_input = try std.fmt.allocPrint(allocator, "{s}:{s}:{s}", .{ username, realm, password });
        defer allocator.free(ha1_input);

        var ha1_hash: [16]u8 = undefined;
        crypto.hash.Md5.hash(ha1_input, &ha1_hash, .{});

        const ha1_hex = try allocator.alloc(u8, 32);
        _ = try std.fmt.bufPrint(ha1_hex, "{x}", .{std.fmt.fmtSliceHexLower(&ha1_hash)});
        defer allocator.free(ha1_hex);

        // HA2 = MD5(method:uri) - assuming GET method
        const ha2_input = try std.fmt.allocPrint(allocator, "GET:{s}", .{uri});
        defer allocator.free(ha2_input);

        var ha2_hash: [16]u8 = undefined;
        crypto.hash.Md5.hash(ha2_input, &ha2_hash, .{});

        const ha2_hex = try allocator.alloc(u8, 32);
        _ = try std.fmt.bufPrint(ha2_hex, "{x}", .{std.fmt.fmtSliceHexLower(&ha2_hash)});
        defer allocator.free(ha2_hex);

        // Response = MD5(HA1:nonce:HA2)
        const response_input = try std.fmt.allocPrint(allocator, "{s}:{s}:{s}", .{ ha1_hex, nonce, ha2_hex });
        defer allocator.free(response_input);

        var response_hash: [16]u8 = undefined;
        crypto.hash.Md5.hash(response_input, &response_hash, .{});

        const response_hex = try allocator.alloc(u8, 32);
        _ = try std.fmt.bufPrint(response_hex, "{x}", .{std.fmt.fmtSliceHexLower(&response_hash)});

        return response_hex;
    }

    /// Generate a random nonce for authentication
    pub fn generateNonce(allocator: std.mem.Allocator, length: usize) ![]u8 {
        const nonce = try allocator.alloc(u8, length);
        crypto.random.bytes(nonce);

        // Convert to hex string
        const hex_nonce = try allocator.alloc(u8, length * 2);
        _ = try std.fmt.bufPrint(hex_nonce, "{x}", .{std.fmt.fmtSliceHexLower(nonce)});

        allocator.free(nonce);
        return hex_nonce;
    }

    /// Validate authentication method support
    pub fn isMethodSupported(method: AuthMethod) bool {
        return switch (method) {
            .none, .plain, .login, .basic_auth => true,
            .digest_md5, .oauth2, .ntlm => true, // Basic support implemented/planned
        };
    }
};

test "basic auth encoding" {
    const allocator = std.testing.allocator;

    const encoded = try Auth.encodeBasicAuth(allocator, "user", "pass");
    defer allocator.free(encoded);

    // "user:pass" base64 encoded should be "dXNlcjpwYXNz"
    try std.testing.expectEqualStrings("dXNlcjpwYXNz", encoded);
}

test "nonce generation" {
    const allocator = std.testing.allocator;

    const nonce1 = try Auth.generateNonce(allocator, 16);
    defer allocator.free(nonce1);

    const nonce2 = try Auth.generateNonce(allocator, 16);
    defer allocator.free(nonce2);

    // Nonces should be different
    try std.testing.expect(!std.mem.eql(u8, nonce1, nonce2));
    try std.testing.expect(nonce1.len == 32); // 16 bytes -> 32 hex chars
}
