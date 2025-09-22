//! POP3 client implementation for downloading email messages
const std = @import("std");
const net = std.net;
const common = @import("../common/common.zig");
const stream = @import("../common/stream.zig");
const Stream = common.Stream;
const Parser = common.Parser;
const Auth = common.Auth;

pub const Pop3Error = error{
    InvalidResponse,
    AuthenticationFailed,
    MessageNotFound,
    CommandFailed,
    ConnectionFailed,
    ConnectionClosed,
    TlsNotSupported,
    TlsStartFailed,
    MailboxLocked,
    DiskFull,
    MessageTooLarge,
} || common.Error || stream.StreamError;

pub const Pop3AuthMethod = enum {
    user_pass, // USER/PASS commands
    apop, // APOP command
    sasl_plain, // SASL PLAIN
};

pub const Pop3Security = enum {
    none, // Plain text connection
    starttls, // Upgrade to TLS after connection
    implicit, // Direct TLS connection (POP3S)
};

pub const Pop3Config = struct {
    host: []const u8,
    port: u16,
    security: Pop3Security,
    auth_method: Pop3AuthMethod,
    username: []const u8,
    password: []const u8,
    timeout_ms: u32 = 30000,
};

pub const Pop3State = enum {
    authorization,
    transaction,
    update,
    disconnected,
};

pub const Pop3Response = struct {
    is_ok: bool,
    message: []const u8,
    allocator: std.mem.Allocator,

    pub fn parse(allocator: std.mem.Allocator, line: []const u8) !Pop3Response {
        if (line.len < 3) return Pop3Error.InvalidResponse;

        const is_ok = std.mem.startsWith(u8, line, "+OK");
        const message_start = if (line.len > 3 and line[3] == ' ') 4 else 3;
        const message_end = if (std.mem.endsWith(u8, line, "\r\n")) line.len - 2 else line.len;

        const message = try allocator.dupe(u8, line[message_start..message_end]);

        return Pop3Response{
            .is_ok = is_ok,
            .message = message,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Pop3Response) void {
        self.allocator.free(self.message);
    }

    pub fn isSuccess(self: Pop3Response) bool {
        return self.is_ok;
    }

    pub fn isError(self: Pop3Response) bool {
        return !self.is_ok;
    }
};

pub const MessageInfo = struct {
    message_number: u32,
    size: u32,
    uid: ?[]const u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *MessageInfo) void {
        if (self.uid) |uid| {
            self.allocator.free(uid);
        }
    }
};

pub const MessageContent = struct {
    headers: []const u8,
    body: []const u8,
    full_message: []const u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *MessageContent) void {
        self.allocator.free(self.full_message);
        // headers and body are slices into full_message, so no need to free separately
    }

    pub fn parseMessage(allocator: std.mem.Allocator, full_message: []const u8) !MessageContent {
        const owned_message = try allocator.dupe(u8, full_message);

        // Find the empty line that separates headers from body
        const header_end = std.mem.indexOf(u8, owned_message, "\r\n\r\n") orelse
            std.mem.indexOf(u8, owned_message, "\n\n") orelse owned_message.len;

        const headers = owned_message[0..header_end];
        const body_start = if (header_end < owned_message.len) header_end + 4 else owned_message.len;
        const body = if (body_start < owned_message.len) owned_message[body_start..] else "";

        return MessageContent{
            .headers = headers,
            .body = body,
            .full_message = owned_message,
            .allocator = allocator,
        };
    }
};

pub const Pop3Client = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    stream: ?Stream,
    config: ?Pop3Config,
    state: Pop3State,
    is_secure: bool,
    capabilities: std.ArrayList([]const u8),

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .stream = null,
            .config = null,
            .state = .disconnected,
            .is_secure = false,
            .capabilities = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.stream) |*s| {
            s.close();
        }

        for (self.capabilities.items) |cap| {
            self.allocator.free(cap);
        }
        self.capabilities.deinit(self.allocator);
    }

    pub fn connect(self: *Self, config: Pop3Config) !void {
        self.config = config;

        const address = try net.Address.resolveIp(config.host, config.port);
        const tcp_stream = try net.tcpConnectToAddress(address);

        // For implicit TLS (POP3S), start with TLS immediately
        if (config.security == .implicit) {
            self.stream = Stream.initTls(self.allocator, tcp_stream);
            self.is_secure = true;
        } else {
            self.stream = Stream.initTcp(self.allocator, tcp_stream);
            self.is_secure = false;
        }

        // Read server greeting
        var greeting = try self.readResponse();
        defer greeting.deinit();

        if (!greeting.isSuccess()) {
            return Pop3Error.ConnectionFailed;
        }

        self.state = .authorization;

        // Get server capabilities if supported
        self.getCapabilities() catch |err| {
            // CAPA command is optional, ignore if not supported
            if (err != Pop3Error.CommandFailed) return err;
        };

        // Upgrade to TLS if using STARTTLS
        if (config.security == .starttls and !self.is_secure) {
            try self.startTls();
        }

        // Authenticate
        try self.authenticate(config.auth_method, config.username, config.password);
        self.state = .transaction;
    }

    fn startTls(self: *Self) !void {
        if (!self.hasCapability("STLS")) {
            return Pop3Error.TlsNotSupported;
        }

        try self.sendCommand("STLS", .{});
        var response = try self.readResponse();
        defer response.deinit();

        if (!response.isSuccess()) {
            return Pop3Error.TlsStartFailed;
        }

        // Upgrade the stream to TLS
        if (self.stream) |*s| {
            const tcp_stream = s.transport.tcp;
            s.close();
            self.stream = Stream.initTls(self.allocator, tcp_stream);
            self.is_secure = true;

            // Re-get capabilities after TLS upgrade
            self.getCapabilities() catch {}; // Ignore errors for optional command
        }
    }

    fn getCapabilities(self: *Self) !void {
        try self.sendCommand("CAPA", .{});
        var response = try self.readResponse();
        defer response.deinit();

        if (!response.isSuccess()) {
            return Pop3Error.CommandFailed;
        }

        // Clear previous capabilities
        for (self.capabilities.items) |cap| {
            self.allocator.free(cap);
        }
        self.capabilities.clearAndFree();

        // Read capability lines until we hit the termination line
        while (true) {
            var buffer: [1024]u8 = undefined;
            const line = try self.stream.?.readLine(buffer[0..]);

            if (std.mem.eql(u8, line, ".")) {
                break;
            }

            const capability = try self.allocator.dupe(u8, line);
            try self.capabilities.append(capability);
        }
    }

    fn hasCapability(self: Self, capability: []const u8) bool {
        for (self.capabilities.items) |cap| {
            if (std.mem.eql(u8, cap, capability)) return true;
        }
        return false;
    }

    pub fn authenticate(self: *Self, method: Pop3AuthMethod, username: []const u8, password: []const u8) !void {
        switch (method) {
            .user_pass => try self.authUserPass(username, password),
            .apop => try self.authApop(username, password),
            .sasl_plain => try self.authSaslPlain(username, password),
        }
    }

    fn authUserPass(self: *Self, username: []const u8, password: []const u8) !void {
        // Send USER command
        try self.sendCommand("USER {s}", .{username});
        var user_response = try self.readResponse();
        defer user_response.deinit();

        if (!user_response.isSuccess()) {
            return Pop3Error.AuthenticationFailed;
        }

        // Send PASS command
        try self.sendCommand("PASS {s}", .{password});
        var pass_response = try self.readResponse();
        defer pass_response.deinit();

        if (!pass_response.isSuccess()) {
            return Pop3Error.AuthenticationFailed;
        }
    }

    fn authApop(self: *Self, username: []const u8, password: []const u8) !void {
        // TODO: Implement APOP authentication with timestamp and MD5 hash
        _ = self;
        _ = username;
        _ = password;
        return Pop3Error.CommandFailed; // Not implemented yet
    }

    fn authSaslPlain(self: *Self, username: []const u8, password: []const u8) !void {
        if (!self.hasCapability("SASL PLAIN")) {
            return Pop3Error.CommandFailed;
        }

        // Create PLAIN authentication string: \0username\0password
        const auth_string = try std.fmt.allocPrint(self.allocator, "\x00{s}\x00{s}", .{ username, password });
        defer self.allocator.free(auth_string);

        // Base64 encode
        const encoder = std.base64.standard.Encoder;
        const encoded_len = encoder.calcSize(auth_string.len);
        const encoded = try self.allocator.alloc(u8, encoded_len);
        defer self.allocator.free(encoded);

        _ = encoder.encode(encoded, auth_string);

        try self.sendCommand("AUTH PLAIN {s}", .{encoded});
        var response = try self.readResponse();
        defer response.deinit();

        if (!response.isSuccess()) {
            return Pop3Error.AuthenticationFailed;
        }
    }

    pub fn getMessageCount(self: *Self) !u32 {
        if (self.state != .transaction) return Pop3Error.CommandFailed;

        try self.sendCommand("STAT", .{});
        var response = try self.readResponse();
        defer response.deinit();

        if (!response.isSuccess()) {
            return Pop3Error.CommandFailed;
        }

        // Parse response: "+OK 2 1230" (2 messages, 1230 octets total)
        var parts = std.mem.splitScalar(u8, response.message, ' ');
        if (parts.next()) |count_str| {
            return std.fmt.parseInt(u32, count_str, 10) catch 0;
        }

        return 0;
    }

    pub fn listMessages(self: *Self) !std.ArrayList(MessageInfo) {
        if (self.state != .transaction) return Pop3Error.CommandFailed;

        try self.sendCommand("LIST", .{});
        var response = try self.readResponse();
        defer response.deinit();

        if (!response.isSuccess()) {
            return Pop3Error.CommandFailed;
        }

        var messages = std.ArrayList(MessageInfo).init(self.allocator);

        // Read message list until we hit the termination line
        while (true) {
            var buffer: [1024]u8 = undefined;
            const line = try self.stream.?.readLine(buffer[0..]);

            if (std.mem.eql(u8, line, ".")) {
                break;
            }

            // Parse line: "1 2000" (message 1, 2000 octets)
            var parts = std.mem.splitScalar(u8, line, ' ');
            const msg_num_str = parts.next() orelse continue;
            const size_str = parts.next() orelse continue;

            const message_info = MessageInfo{
                .message_number = std.fmt.parseInt(u32, msg_num_str, 10) catch continue,
                .size = std.fmt.parseInt(u32, size_str, 10) catch 0,
                .uid = null,
                .allocator = self.allocator,
            };

            try messages.append(message_info);
        }

        return messages;
    }

    pub fn retrieveMessage(self: *Self, message_number: u32) !MessageContent {
        if (self.state != .transaction) return Pop3Error.CommandFailed;

        try self.sendCommand("RETR {}", .{message_number});
        var response = try self.readResponse();
        defer response.deinit();

        if (!response.isSuccess()) {
            return Pop3Error.MessageNotFound;
        }

        // Read message content until we hit the termination line
        var message_lines = std.ArrayList(u8).init(self.allocator);
        defer message_lines.deinit();

        while (true) {
            var buffer: [4096]u8 = undefined;
            const line = try self.stream.?.readLine(buffer[0..]);

            if (std.mem.eql(u8, line, ".")) {
                break;
            }

            // Handle byte-stuffing: lines starting with ".." should be reduced to "."
            const actual_line = if (std.mem.startsWith(u8, line, "..")) line[1..] else line;

            try message_lines.appendSlice(actual_line);
            try message_lines.appendSlice("\r\n");
        }

        return MessageContent.parseMessage(self.allocator, message_lines.items);
    }

    pub fn retrieveMessageTop(self: *Self, message_number: u32, lines: u32) !MessageContent {
        if (self.state != .transaction) return Pop3Error.CommandFailed;

        try self.sendCommand("TOP {} {}", .{ message_number, lines });
        var response = try self.readResponse();
        defer response.deinit();

        if (!response.isSuccess()) {
            return Pop3Error.MessageNotFound;
        }

        // Read message content until we hit the termination line
        var message_lines = std.ArrayList(u8).init(self.allocator);
        defer message_lines.deinit();

        while (true) {
            var buffer: [4096]u8 = undefined;
            const line = try self.stream.?.readLine(buffer[0..]);

            if (std.mem.eql(u8, line, ".")) {
                break;
            }

            // Handle byte-stuffing
            const actual_line = if (std.mem.startsWith(u8, line, "..")) line[1..] else line;

            try message_lines.appendSlice(actual_line);
            try message_lines.appendSlice("\r\n");
        }

        return MessageContent.parseMessage(self.allocator, message_lines.items);
    }

    pub fn deleteMessage(self: *Self, message_number: u32) !void {
        if (self.state != .transaction) return Pop3Error.CommandFailed;

        try self.sendCommand("DELE {}", .{message_number});
        var response = try self.readResponse();
        defer response.deinit();

        if (!response.isSuccess()) {
            return Pop3Error.MessageNotFound;
        }
    }

    pub fn resetSession(self: *Self) !void {
        if (self.state != .transaction) return Pop3Error.CommandFailed;

        try self.sendCommand("RSET", .{});
        var response = try self.readResponse();
        defer response.deinit();

        if (!response.isSuccess()) {
            return Pop3Error.CommandFailed;
        }
    }

    pub fn getUniqueIds(self: *Self) !std.ArrayList(MessageInfo) {
        if (self.state != .transaction) return Pop3Error.CommandFailed;

        if (!self.hasCapability("UIDL")) {
            return Pop3Error.CommandFailed;
        }

        try self.sendCommand("UIDL", .{});
        var response = try self.readResponse();
        defer response.deinit();

        if (!response.isSuccess()) {
            return Pop3Error.CommandFailed;
        }

        var messages = std.ArrayList(MessageInfo).init(self.allocator);

        // Read unique ID list until we hit the termination line
        while (true) {
            var buffer: [1024]u8 = undefined;
            const line = try self.stream.?.readLine(buffer[0..]);

            if (std.mem.eql(u8, line, ".")) {
                break;
            }

            // Parse line: "1 whqtswO00WBw418f9t5JxYwZ" (message 1, unique ID)
            var parts = std.mem.splitScalar(u8, line, ' ');
            const msg_num_str = parts.next() orelse continue;
            const uid_str = parts.next() orelse continue;

            const message_info = MessageInfo{
                .message_number = std.fmt.parseInt(u32, msg_num_str, 10) catch continue,
                .size = 0, // Size not provided in UIDL
                .uid = try self.allocator.dupe(u8, uid_str),
                .allocator = self.allocator,
            };

            try messages.append(message_info);
        }

        return messages;
    }

    pub fn quit(self: *Self) !void {
        if (self.state == .disconnected) return;

        try self.sendCommand("QUIT", .{});
        var response = try self.readResponse();
        defer response.deinit();

        self.state = .update;

        if (self.stream) |*s| {
            s.close();
            self.stream = null;
        }

        self.state = .disconnected;
    }

    fn sendCommand(self: *Self, comptime fmt: []const u8, args: anytype) !void {
        if (self.stream == null) return Pop3Error.ConnectionClosed;

        const command = try std.fmt.allocPrint(self.allocator, fmt ++ "\r\n", args);
        defer self.allocator.free(command);

        try self.stream.?.writeAll(command);
    }

    fn readResponse(self: *Self) !Pop3Response {
        if (self.stream == null) return Pop3Error.ConnectionClosed;

        var buffer: [1024]u8 = undefined;
        const line = try self.stream.?.readLine(buffer[0..]);

        return Pop3Response.parse(self.allocator, line);
    }
};

test "pop3 response parsing" {
    const allocator = std.testing.allocator;

    var response = try Pop3Response.parse(allocator, "+OK 2 messages (1230 octets)");
    defer response.deinit();

    try std.testing.expect(response.is_ok);
    try std.testing.expectEqualStrings("2 messages (1230 octets)", response.message);

    var error_response = try Pop3Response.parse(allocator, "-ERR no such message");
    defer error_response.deinit();

    try std.testing.expect(!error_response.is_ok);
    try std.testing.expectEqualStrings("no such message", error_response.message);
}

test "message content parsing" {
    const allocator = std.testing.allocator;

    const raw_message = "From: sender@example.com\r\nTo: recipient@example.com\r\nSubject: Test\r\n\r\nHello, World!";

    var content = try MessageContent.parseMessage(allocator, raw_message);
    defer content.deinit();

    try std.testing.expectEqualStrings("From: sender@example.com\r\nTo: recipient@example.com\r\nSubject: Test", content.headers);
    try std.testing.expectEqualStrings("Hello, World!", content.body);
}
