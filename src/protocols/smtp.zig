//! SMTP client implementation for sending emails
const std = @import("std");
const net = std.net;
const common = @import("../common/common.zig");
const stream = @import("../common/stream.zig");
const Stream = common.Stream;
const Parser = common.Parser;
const Auth = common.Auth;

pub const SmtpError = error{
    InvalidResponse,
    AuthenticationFailed,
    MailboxUnavailable,
    MessageTooLarge,
    InvalidAddress,
    TransactionFailed,
    ConnectionFailed,
    ConnectionClosed,
    TlsNotSupported,
    TlsStartFailed,
    UnsupportedAuthMethod,
    AuthenticationRequired,
} || common.Error || stream.StreamError;

pub const SmtpAuthMethod = enum {
    none,
    plain,
    login,
    cram_md5,
    digest_md5,
    xoauth2,
};

pub const SmtpSecurity = enum {
    none, // Plain text connection
    starttls, // Upgrade to TLS after connection
    implicit, // Direct TLS connection (SMTPS)
};

pub const SmtpConfig = struct {
    host: []const u8,
    port: u16,
    security: SmtpSecurity,
    auth_method: SmtpAuthMethod,
    username: ?[]const u8,
    password: ?[]const u8,
    timeout_ms: u32 = 30000,
};

pub const SmtpResponse = struct {
    code: u16,
    message: []const u8,
    is_final: bool,

    pub fn parse(allocator: std.mem.Allocator, data: []const u8) !SmtpResponse {
        if (data.len < 3) return SmtpError.InvalidResponse;

        const code = std.fmt.parseInt(u16, data[0..3], 10) catch return SmtpError.InvalidResponse;
        const is_final = data.len > 3 and data[3] != '-';

        const message_start = if (data.len > 4) 4 else data.len;
        const message_end = if (std.mem.endsWith(u8, data, "\r\n")) data.len - 2 else data.len;
        const message = try allocator.dupe(u8, data[message_start..message_end]);

        return SmtpResponse{
            .code = code,
            .message = message,
            .is_final = is_final,
        };
    }

    pub fn deinit(self: *SmtpResponse, allocator: std.mem.Allocator) void {
        allocator.free(self.message);
    }

    pub fn isSuccess(self: SmtpResponse) bool {
        return self.code >= 200 and self.code < 300;
    }

    pub fn isIntermediate(self: SmtpResponse) bool {
        return self.code >= 300 and self.code < 400;
    }

    pub fn isError(self: SmtpResponse) bool {
        return self.code >= 400;
    }
};

pub const EmailAddress = struct {
    name: ?[]const u8,
    email: []const u8,

    pub fn format(self: EmailAddress, allocator: std.mem.Allocator) ![]const u8 {
        if (self.name) |name| {
            return std.fmt.allocPrint(allocator, "\"{s}\" <{s}>", .{ name, self.email });
        } else {
            return std.fmt.allocPrint(allocator, "<{s}>", .{self.email});
        }
    }

    pub fn formatSimple(self: EmailAddress) []const u8 {
        return self.email;
    }
};

pub const EmailMessage = struct {
    const Self = @This();

    from: EmailAddress,
    to: []const EmailAddress,
    cc: ?[]const EmailAddress,
    bcc: ?[]const EmailAddress,
    subject: []const u8,
    body: []const u8,
    headers: std.StringHashMap([]const u8),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, from: EmailAddress, to: []const EmailAddress, subject: []const u8, body: []const u8) !Self {
        return Self{
            .from = from,
            .to = try allocator.dupe(EmailAddress, to),
            .cc = null,
            .bcc = null,
            .subject = try allocator.dupe(u8, subject),
            .body = try allocator.dupe(u8, body),
            .headers = std.StringHashMap([]const u8).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.to);
        if (self.cc) |cc| self.allocator.free(cc);
        if (self.bcc) |bcc| self.allocator.free(bcc);
        self.allocator.free(self.subject);
        self.allocator.free(self.body);

        var iterator = self.headers.iterator();
        while (iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.headers.deinit();
    }

    pub fn addHeader(self: *Self, name: []const u8, value: []const u8) !void {
        const owned_name = try self.allocator.dupe(u8, name);
        const owned_value = try self.allocator.dupe(u8, value);
        try self.headers.put(owned_name, owned_value);
    }

    pub fn setCc(self: *Self, cc: []const EmailAddress) !void {
        if (self.cc) |old_cc| {
            self.allocator.free(old_cc);
        }
        self.cc = try self.allocator.dupe(EmailAddress, cc);
    }

    pub fn setBcc(self: *Self, bcc: []const EmailAddress) !void {
        if (self.bcc) |old_bcc| {
            self.allocator.free(old_bcc);
        }
        self.bcc = try self.allocator.dupe(EmailAddress, bcc);
    }

    pub fn formatMessage(self: Self, allocator: std.mem.Allocator) ![]const u8 {
        var message: std.ArrayList(u8) = .{};
        defer message.deinit(allocator);

        // Standard headers
        const from_formatted = try self.from.format(allocator);
        defer allocator.free(from_formatted);
        try message.appendSlice(allocator, "From: ");
        try message.appendSlice(allocator, from_formatted);
        try message.appendSlice(allocator, "\r\n");

        // To recipients
        try message.appendSlice(allocator, "To: ");
        for (self.to, 0..) |recipient, i| {
            const formatted = try recipient.format(allocator);
            defer allocator.free(formatted);
            try message.appendSlice(allocator, formatted);
            if (i < self.to.len - 1) try message.appendSlice(allocator, ", ");
        }
        try message.appendSlice(allocator, "\r\n");

        // CC recipients
        if (self.cc) |cc| {
            try message.appendSlice(allocator, "Cc: ");
            for (cc, 0..) |recipient, i| {
                const formatted = try recipient.format(allocator);
                defer allocator.free(formatted);
                try message.appendSlice(allocator, formatted);
                if (i < cc.len - 1) try message.appendSlice(allocator, ", ");
            }
            try message.appendSlice(allocator, "\r\n");
        }

        try message.appendSlice(allocator, "Subject: ");
        try message.appendSlice(allocator, self.subject);
        try message.appendSlice(allocator, "\r\n");

        // Add timestamp
        const timestamp = std.time.timestamp();
        var date_buf: [64]u8 = undefined;
        const date_str = try std.fmt.bufPrint(date_buf[0..], "Date: {d}\r\n", .{timestamp});
        try message.appendSlice(allocator, date_str);

        // Custom headers
        var header_iter = self.headers.iterator();
        while (header_iter.next()) |entry| {
            try message.appendSlice(allocator, entry.key_ptr.*);
            try message.appendSlice(allocator, ": ");
            try message.appendSlice(allocator, entry.value_ptr.*);
            try message.appendSlice(allocator, "\r\n");
        }

        // Empty line before body
        try message.appendSlice(allocator, "\r\n");

        // Message body
        try message.appendSlice(allocator, self.body);

        return try message.toOwnedSlice(allocator);
    }

    pub fn getAllRecipients(self: Self, allocator: std.mem.Allocator) ![]EmailAddress {
        var recipients = std.ArrayList(EmailAddress).init(allocator);

        try recipients.appendSlice(self.to);
        if (self.cc) |cc| try recipients.appendSlice(cc);
        if (self.bcc) |bcc| try recipients.appendSlice(bcc);

        return recipients.toOwnedSlice();
    }
};

pub const SmtpClient = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    stream: ?Stream,
    auth_methods: []SmtpAuthMethod,
    server_capabilities: std.StringHashMap([]const u8),
    config: ?SmtpConfig,
    is_authenticated: bool,
    is_secure: bool,

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .stream = null,
            .auth_methods = &[_]SmtpAuthMethod{},
            .server_capabilities = std.StringHashMap([]const u8).init(allocator),
            .config = null,
            .is_authenticated = false,
            .is_secure = false,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.stream) |*s| {
            s.close();
        }

        var cap_iter = self.server_capabilities.iterator();
        while (cap_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.server_capabilities.deinit();
    }

    pub fn connect(self: *Self, config: SmtpConfig) !void {
        self.config = config;

        const address = try net.Address.resolveIp(config.host, config.port);
        const tcp_stream = try net.tcpConnectToAddress(address);

        // For implicit TLS (SMTPS), start with TLS immediately
        if (config.security == .implicit) {
            self.stream = Stream.initTls(self.allocator, tcp_stream);
            self.is_secure = true;
        } else {
            self.stream = Stream.initTcp(self.allocator, tcp_stream);
            self.is_secure = false;
        }

        // Read server greeting
        var greeting = try self.readResponse();
        defer greeting.deinit(self.allocator);

        if (!greeting.isSuccess()) {
            return SmtpError.ConnectionFailed;
        }

        // Send EHLO to get server capabilities
        try self.sendEhlo();

        // Upgrade to TLS if using STARTTLS
        if (config.security == .starttls and !self.is_secure) {
            try self.startTls();
        }

        // Authenticate if credentials provided
        if (config.username != null and config.password != null) {
            try self.authenticate(config.auth_method, config.username.?, config.password.?);
        }
    }

    pub fn connectSimple(self: *Self, host: []const u8, port: u16) !void {
        const config = SmtpConfig{
            .host = host,
            .port = port,
            .security = .none,
            .auth_method = .none,
            .username = null,
            .password = null,
        };
        try self.connect(config);
    }

    fn startTls(self: *Self) !void {
        if (!self.hasCapability("STARTTLS")) {
            return SmtpError.TlsNotSupported;
        }

        try self.sendCommand("STARTTLS", .{});
        var response = try self.readResponse();
        defer response.deinit(self.allocator);

        if (!response.isSuccess()) {
            return SmtpError.TlsStartFailed;
        }

        // Upgrade the stream to TLS
        if (self.stream) |*s| {
            const tcp_stream = s.transport.tcp;
            s.close();
            self.stream = Stream.initTls(self.allocator, tcp_stream);
            self.is_secure = true;

            // Re-send EHLO after TLS upgrade
            try self.sendEhlo();
        }
    }

    fn sendEhlo(self: *Self) !void {
        try self.sendCommand("EHLO localhost", .{});

        // Clear previous capabilities
        var cap_iter = self.server_capabilities.iterator();
        while (cap_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.server_capabilities.clearAndFree();

        // Read multi-line EHLO response
        while (true) {
            var response = try self.readResponse();
            defer response.deinit(self.allocator);

            if (!response.isSuccess()) {
                return SmtpError.InvalidResponse;
            }

            // Parse capability line
            if (response.message.len > 0) {
                const space_pos = std.mem.indexOf(u8, response.message, " ");
                const capability = if (space_pos) |pos| response.message[0..pos] else response.message;
                const value = if (space_pos) |pos| response.message[pos + 1 ..] else "";

                const owned_cap = try self.allocator.dupe(u8, capability);
                const owned_val = try self.allocator.dupe(u8, value);
                try self.server_capabilities.put(owned_cap, owned_val);
            }

            if (response.is_final) break;
        }
    }

    fn hasCapability(self: Self, capability: []const u8) bool {
        return self.server_capabilities.contains(capability);
    }

    pub fn authenticate(self: *Self, method: SmtpAuthMethod, username: []const u8, password: []const u8) !void {
        switch (method) {
            .none => return,
            .plain => try self.authPlain(username, password),
            .login => try self.authLogin(username, password),
            .cram_md5 => return SmtpError.UnsupportedAuthMethod, // TODO: Implement
            .digest_md5 => return SmtpError.UnsupportedAuthMethod, // TODO: Implement
            .xoauth2 => return SmtpError.UnsupportedAuthMethod, // TODO: Implement
        }
        self.is_authenticated = true;
    }

    pub fn sendMail(self: *Self, message: EmailMessage) !void {
        // MAIL FROM command
        try self.sendCommand("MAIL FROM:<{s}>", .{message.from.email});
        var mail_response = try self.readResponse();
        defer mail_response.deinit(self.allocator);

        if (!mail_response.isSuccess()) {
            return SmtpError.TransactionFailed;
        }

        // RCPT TO commands for all recipients
        const all_recipients = try message.getAllRecipients(self.allocator);
        defer self.allocator.free(all_recipients);

        for (all_recipients) |recipient| {
            try self.sendCommand("RCPT TO:<{s}>", .{recipient.email});
            var rcpt_response = try self.readResponse();
            defer rcpt_response.deinit(self.allocator);

            if (!rcpt_response.isSuccess()) {
                return SmtpError.MailboxUnavailable;
            }
        }

        // DATA command
        try self.sendCommand("DATA", .{});
        var data_response = try self.readResponse();
        defer data_response.deinit(self.allocator);

        if (!data_response.isIntermediate()) {
            return SmtpError.TransactionFailed;
        }

        // Send message content
        const formatted_message = try message.formatMessage(self.allocator);
        defer self.allocator.free(formatted_message);

        try self.stream.?.writeAll(formatted_message);
        try self.stream.?.writeAll("\r\n.\r\n"); // End with CRLF.CRLF

        // Read final response
        var final_response = try self.readResponse();
        defer final_response.deinit(self.allocator);

        if (!final_response.isSuccess()) {
            return SmtpError.TransactionFailed;
        }
    }

    pub fn quit(self: *Self) !void {
        try self.sendCommand("QUIT", .{});
        var response = try self.readResponse();
        defer response.deinit(self.allocator);

        if (self.stream) |*s| {
            s.close();
            self.stream = null;
        }
    }

    fn sendCommand(self: *Self, comptime fmt: []const u8, args: anytype) !void {
        if (self.stream == null) return SmtpError.ConnectionClosed;

        const command = try std.fmt.allocPrint(self.allocator, fmt ++ "\r\n", args);
        defer self.allocator.free(command);

        try self.stream.?.writeAll(command);
    }

    fn readResponse(self: *Self) !SmtpResponse {
        if (self.stream == null) return SmtpError.ConnectionClosed;

        var buffer: [1024]u8 = undefined;
        const line = try self.stream.?.readLine(buffer[0..]);

        return SmtpResponse.parse(self.allocator, line);
    }

    fn authPlain(self: *Self, username: []const u8, password: []const u8) !void {
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
        defer response.deinit(self.allocator);

        if (!response.isSuccess()) {
            return SmtpError.AuthenticationFailed;
        }
    }

    fn authLogin(self: *Self, username: []const u8, password: []const u8) !void {
        try self.sendCommand("AUTH LOGIN", .{});

        var response = try self.readResponse();
        defer response.deinit(self.allocator);

        if (!response.isIntermediate()) {
            return SmtpError.AuthenticationFailed;
        }

        // Send base64-encoded username
        const encoder = std.base64.standard.Encoder;

        const username_encoded_len = encoder.calcSize(username.len);
        const username_encoded = try self.allocator.alloc(u8, username_encoded_len);
        defer self.allocator.free(username_encoded);
        _ = encoder.encode(username_encoded, username);

        try self.sendCommand("{s}", .{username_encoded});

        var username_response = try self.readResponse();
        defer username_response.deinit(self.allocator);

        if (!username_response.isIntermediate()) {
            return SmtpError.AuthenticationFailed;
        }

        // Send base64-encoded password
        const password_encoded_len = encoder.calcSize(password.len);
        const password_encoded = try self.allocator.alloc(u8, password_encoded_len);
        defer self.allocator.free(password_encoded);
        _ = encoder.encode(password_encoded, password);

        try self.sendCommand("{s}", .{password_encoded});

        var password_response = try self.readResponse();
        defer password_response.deinit(self.allocator);

        if (!password_response.isSuccess()) {
            return SmtpError.AuthenticationFailed;
        }
    }
};

test "smtp response parsing" {
    const allocator = std.testing.allocator;

    var response = try SmtpResponse.parse(allocator, "250 OK\r\n");
    defer response.deinit(allocator);

    try std.testing.expect(response.code == 250);
    try std.testing.expectEqualStrings("OK", response.message);
    try std.testing.expect(response.is_final);
}

test "email address formatting" {
    const allocator = std.testing.allocator;

    const addr = EmailAddress{ .name = "John Doe", .email = "john@example.com" };
    const formatted = try addr.format(allocator);
    defer allocator.free(formatted);

    try std.testing.expectEqualStrings("\"John Doe\" <john@example.com>", formatted);
}
