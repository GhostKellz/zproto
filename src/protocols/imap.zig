//! IMAP client implementation for accessing email mailboxes
const std = @import("std");
const net = std.net;
const common = @import("../common/common.zig");
const stream = @import("../common/stream.zig");
const Stream = common.Stream;
const Parser = common.Parser;
const Auth = common.Auth;

pub const ImapError = error{
    InvalidResponse,
    AuthenticationFailed,
    MailboxNotFound,
    CommandFailed,
    ConnectionFailed,
    ConnectionClosed,
    TlsNotSupported,
    TlsStartFailed,
    UnsupportedAuthMethod,
    InvalidMailbox,
    MessageNotFound,
    ParseError,
} || common.Error || stream.StreamError;

pub const ImapAuthMethod = enum {
    plain,
    login,
    cram_md5,
    digest_md5,
    xoauth2,
};

pub const ImapSecurity = enum {
    none, // Plain text connection
    starttls, // Upgrade to TLS after connection
    implicit, // Direct TLS connection (IMAPS)
};

pub const ImapConfig = struct {
    host: []const u8,
    port: u16,
    security: ImapSecurity,
    auth_method: ImapAuthMethod,
    username: []const u8,
    password: []const u8,
    timeout_ms: u32 = 30000,
};

pub const ImapCapability = enum {
    imap4rev1,
    starttls,
    auth_plain,
    auth_login,
    auth_cram_md5,
    uidplus,
    idle,
    namespace,
    quota,
    sort,
    thread_orderedsubject,
    thread_references,
    unselect,
    children,
    list_extended,
    condstore,
    esearch,
    within,
    context_search,
    context_sort,
    convert,
    move,

    pub fn fromString(str: []const u8) ?ImapCapability {
        if (std.mem.eql(u8, str, "IMAP4REV1")) return .imap4rev1;
        if (std.mem.eql(u8, str, "STARTTLS")) return .starttls;
        if (std.mem.eql(u8, str, "AUTH=PLAIN")) return .auth_plain;
        if (std.mem.eql(u8, str, "AUTH=LOGIN")) return .auth_login;
        if (std.mem.eql(u8, str, "AUTH=CRAM-MD5")) return .auth_cram_md5;
        if (std.mem.eql(u8, str, "UIDPLUS")) return .uidplus;
        if (std.mem.eql(u8, str, "IDLE")) return .idle;
        if (std.mem.eql(u8, str, "NAMESPACE")) return .namespace;
        if (std.mem.eql(u8, str, "QUOTA")) return .quota;
        if (std.mem.eql(u8, str, "SORT")) return .sort;
        if (std.mem.eql(u8, str, "THREAD=ORDEREDSUBJECT")) return .thread_orderedsubject;
        if (std.mem.eql(u8, str, "THREAD=REFERENCES")) return .thread_references;
        if (std.mem.eql(u8, str, "UNSELECT")) return .unselect;
        if (std.mem.eql(u8, str, "CHILDREN")) return .children;
        if (std.mem.eql(u8, str, "LIST-EXTENDED")) return .list_extended;
        if (std.mem.eql(u8, str, "CONDSTORE")) return .condstore;
        if (std.mem.eql(u8, str, "ESEARCH")) return .esearch;
        if (std.mem.eql(u8, str, "WITHIN")) return .within;
        if (std.mem.eql(u8, str, "CONTEXT=SEARCH")) return .context_search;
        if (std.mem.eql(u8, str, "CONTEXT=SORT")) return .context_sort;
        if (std.mem.eql(u8, str, "CONVERT")) return .convert;
        if (std.mem.eql(u8, str, "MOVE")) return .move;
        return null;
    }
};

pub const ImapResponseType = enum {
    ok,
    no,
    bad,
    preauth,
    bye,
    untagged,
};

pub const ImapResponse = struct {
    tag: ?[]const u8,
    response_type: ImapResponseType,
    message: []const u8,
    allocator: std.mem.Allocator,

    pub fn parse(allocator: std.mem.Allocator, line: []const u8) !ImapResponse {
        if (line.len == 0) return ImapError.InvalidResponse;

        var parts = std.mem.splitScalar(u8, line, ' ');

        const first_part = parts.next() orelse return ImapError.InvalidResponse;

        // Check if it's untagged response
        if (std.mem.eql(u8, first_part, "*")) {
            const second_part = parts.next() orelse return ImapError.InvalidResponse;
            const response_type = if (std.mem.eql(u8, second_part, "OK")) ImapResponseType.ok else if (std.mem.eql(u8, second_part, "NO")) ImapResponseType.no else if (std.mem.eql(u8, second_part, "BAD")) ImapResponseType.bad else if (std.mem.eql(u8, second_part, "PREAUTH")) ImapResponseType.preauth else if (std.mem.eql(u8, second_part, "BYE")) ImapResponseType.bye else ImapResponseType.untagged;

            const message_start = if (response_type == .untagged)
                first_part.len + 1
            else
                first_part.len + 1 + second_part.len + 1;

            const message = if (message_start < line.len)
                try allocator.dupe(u8, line[message_start..])
            else
                try allocator.dupe(u8, "");

            return ImapResponse{
                .tag = null,
                .response_type = response_type,
                .message = message,
                .allocator = allocator,
            };
        } else {
            // Tagged response
            const second_part = parts.next() orelse return ImapError.InvalidResponse;
            const response_type = if (std.mem.eql(u8, second_part, "OK")) ImapResponseType.ok else if (std.mem.eql(u8, second_part, "NO")) ImapResponseType.no else if (std.mem.eql(u8, second_part, "BAD")) ImapResponseType.bad else return ImapError.InvalidResponse;

            const tag = try allocator.dupe(u8, first_part);
            const message_start = first_part.len + 1 + second_part.len + 1;
            const message = if (message_start < line.len)
                try allocator.dupe(u8, line[message_start..])
            else
                try allocator.dupe(u8, "");

            return ImapResponse{
                .tag = tag,
                .response_type = response_type,
                .message = message,
                .allocator = allocator,
            };
        }
    }

    pub fn deinit(self: *ImapResponse) void {
        if (self.tag) |tag| self.allocator.free(tag);
        self.allocator.free(self.message);
    }

    pub fn isSuccess(self: ImapResponse) bool {
        return self.response_type == .ok or self.response_type == .preauth;
    }

    pub fn isError(self: ImapResponse) bool {
        return self.response_type == .no or self.response_type == .bad;
    }
};

pub const MailboxInfo = struct {
    name: []const u8,
    flags: [][]const u8,
    exists: u32,
    recent: u32,
    unseen: ?u32,
    uid_validity: ?u32,
    uid_next: ?u32,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *MailboxInfo) void {
        self.allocator.free(self.name);
        for (self.flags) |flag| {
            self.allocator.free(flag);
        }
        self.allocator.free(self.flags);
    }
};

pub const MessageInfo = struct {
    sequence_number: u32,
    uid: ?u32,
    flags: [][]const u8,
    size: ?u32,
    envelope: ?MessageEnvelope,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *MessageInfo) void {
        for (self.flags) |flag| {
            self.allocator.free(flag);
        }
        self.allocator.free(self.flags);
        if (self.envelope) |*env| env.deinit();
    }
};

pub const MessageEnvelope = struct {
    date: ?[]const u8,
    subject: ?[]const u8,
    from: ?[][]const u8,
    sender: ?[][]const u8,
    reply_to: ?[][]const u8,
    to: ?[][]const u8,
    cc: ?[][]const u8,
    bcc: ?[][]const u8,
    in_reply_to: ?[]const u8,
    message_id: ?[]const u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *MessageEnvelope) void {
        if (self.date) |date| self.allocator.free(date);
        if (self.subject) |subject| self.allocator.free(subject);
        if (self.from) |from| {
            for (from) |addr| self.allocator.free(addr);
            self.allocator.free(from);
        }
        if (self.sender) |sender| {
            for (sender) |addr| self.allocator.free(addr);
            self.allocator.free(sender);
        }
        if (self.reply_to) |reply_to| {
            for (reply_to) |addr| self.allocator.free(addr);
            self.allocator.free(reply_to);
        }
        if (self.to) |to| {
            for (to) |addr| self.allocator.free(addr);
            self.allocator.free(to);
        }
        if (self.cc) |cc| {
            for (cc) |addr| self.allocator.free(addr);
            self.allocator.free(cc);
        }
        if (self.bcc) |bcc| {
            for (bcc) |addr| self.allocator.free(addr);
            self.allocator.free(bcc);
        }
        if (self.in_reply_to) |in_reply_to| self.allocator.free(in_reply_to);
        if (self.message_id) |message_id| self.allocator.free(message_id);
    }
};

pub const ImapClient = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    stream: ?Stream,
    capabilities: std.ArrayList(ImapCapability),
    config: ?ImapConfig,
    is_authenticated: bool,
    is_secure: bool,
    selected_mailbox: ?[]const u8,
    tag_counter: u32,

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .stream = null,
            .capabilities = .{},
            .config = null,
            .is_authenticated = false,
            .is_secure = false,
            .selected_mailbox = null,
            .tag_counter = 1,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.stream) |*s| {
            s.close();
        }
        self.capabilities.deinit(self.allocator);
        if (self.selected_mailbox) |mailbox| {
            self.allocator.free(mailbox);
        }
    }

    pub fn connect(self: *Self, config: ImapConfig) !void {
        self.config = config;

        const address = try net.Address.resolveIp(config.host, config.port);
        const tcp_stream = try net.tcpConnectToAddress(address);

        // For implicit TLS (IMAPS), start with TLS immediately
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

        if (!greeting.isSuccess() and greeting.response_type != .preauth) {
            return ImapError.ConnectionFailed;
        }

        // If PREAUTH, we're already authenticated
        if (greeting.response_type == .preauth) {
            self.is_authenticated = true;
        }

        // Get server capabilities
        try self.getCapabilities();

        // Upgrade to TLS if using STARTTLS
        if (config.security == .starttls and !self.is_secure) {
            try self.startTls();
        }

        // Authenticate if not already authenticated and credentials provided
        if (!self.is_authenticated) {
            try self.authenticate(config.auth_method, config.username, config.password);
        }
    }

    fn startTls(self: *Self) !void {
        if (!self.hasCapability(.starttls)) {
            return ImapError.TlsNotSupported;
        }

        const tag = try self.sendCommand("STARTTLS", .{});
        var response = try self.readTaggedResponse(tag);
        defer response.deinit();

        if (!response.isSuccess()) {
            return ImapError.TlsStartFailed;
        }

        // Upgrade the stream to TLS
        if (self.stream) |*s| {
            const tcp_stream = s.transport.tcp;
            s.close();
            self.stream = Stream.initTls(self.allocator, tcp_stream);
            self.is_secure = true;

            // Re-get capabilities after TLS upgrade
            try self.getCapabilities();
        }
    }

    fn getCapabilities(self: *Self) !void {
        const tag = try self.sendCommand("CAPABILITY", .{});

        // Clear previous capabilities
        self.capabilities.clearAndFree(self.allocator);

        // Read responses until we get the tagged response
        while (true) {
            var response = try self.readResponse();
            defer response.deinit();

            if (response.tag != null and std.mem.eql(u8, response.tag.?, tag)) {
                if (!response.isSuccess()) {
                    return ImapError.CommandFailed;
                }
                break;
            } else if (response.tag == null and std.mem.startsWith(u8, response.message, "CAPABILITY")) {
                // Parse capabilities from untagged response
                var parts = std.mem.splitScalar(u8, response.message[11..], ' '); // Skip "CAPABILITY "
                while (parts.next()) |cap_str| {
                    if (ImapCapability.fromString(cap_str)) |capability| {
                        try self.capabilities.append(self.allocator, capability);
                    }
                }
            }
        }
    }

    fn hasCapability(self: Self, capability: ImapCapability) bool {
        for (self.capabilities.items) |cap| {
            if (cap == capability) return true;
        }
        return false;
    }

    pub fn authenticate(self: *Self, method: ImapAuthMethod, username: []const u8, password: []const u8) !void {
        switch (method) {
            .plain => try self.authPlain(username, password),
            .login => try self.authLogin(username, password),
            .cram_md5 => return ImapError.UnsupportedAuthMethod, // TODO: Implement
            .digest_md5 => return ImapError.UnsupportedAuthMethod, // TODO: Implement
            .xoauth2 => return ImapError.UnsupportedAuthMethod, // TODO: Implement
        }
        self.is_authenticated = true;
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

        const tag = try self.sendCommand("AUTHENTICATE PLAIN {s}", .{encoded});
        var response = try self.readTaggedResponse(tag);
        defer response.deinit();

        if (!response.isSuccess()) {
            return ImapError.AuthenticationFailed;
        }
    }

    fn authLogin(self: *Self, username: []const u8, password: []const u8) !void {
        const tag = try self.sendCommand("LOGIN {s} {s}", .{ username, password });
        var response = try self.readTaggedResponse(tag);
        defer response.deinit();

        if (!response.isSuccess()) {
            return ImapError.AuthenticationFailed;
        }
    }

    pub fn selectMailbox(self: *Self, mailbox_name: []const u8) !MailboxInfo {
        const tag = try self.sendCommand("SELECT {s}", .{mailbox_name});

        var mailbox_info = MailboxInfo{
            .name = try self.allocator.dupe(u8, mailbox_name),
            .flags = &[_][]const u8{},
            .exists = 0,
            .recent = 0,
            .unseen = null,
            .uid_validity = null,
            .uid_next = null,
            .allocator = self.allocator,
        };

        // Read responses until we get the tagged response
        while (true) {
            var response = try self.readResponse();
            defer response.deinit();

            if (response.tag != null and std.mem.eql(u8, response.tag.?, tag)) {
                if (!response.isSuccess()) {
                    mailbox_info.deinit();
                    return ImapError.InvalidMailbox;
                }
                break;
            } else if (response.tag == null) {
                // Parse untagged responses for mailbox info
                try self.parseMailboxResponse(response.message, &mailbox_info);
            }
        }

        // Update selected mailbox
        if (self.selected_mailbox) |old_mailbox| {
            self.allocator.free(old_mailbox);
        }
        self.selected_mailbox = try self.allocator.dupe(u8, mailbox_name);

        return mailbox_info;
    }

    fn parseMailboxResponse(self: *Self, message: []const u8, mailbox_info: *MailboxInfo) !void {
        _ = self; // unused for now
        if (std.mem.endsWith(u8, message, "EXISTS")) {
            var parts = std.mem.splitScalar(u8, message, ' ');
            if (parts.next()) |count_str| {
                mailbox_info.exists = std.fmt.parseInt(u32, count_str, 10) catch 0;
            }
        } else if (std.mem.endsWith(u8, message, "RECENT")) {
            var parts = std.mem.splitScalar(u8, message, ' ');
            if (parts.next()) |count_str| {
                mailbox_info.recent = std.fmt.parseInt(u32, count_str, 10) catch 0;
            }
        }
        // TODO: Parse FLAGS, UIDVALIDITY, UIDNEXT, etc.
    }

    pub fn fetchMessages(self: *Self, sequence_set: []const u8, items: []const u8) !std.ArrayList(MessageInfo) {
        const tag = try self.sendCommand("FETCH {s} {s}", .{ sequence_set, items });

        var messages = std.ArrayList(MessageInfo).init(self.allocator);

        // Read responses until we get the tagged response
        while (true) {
            var response = try self.readResponse();
            defer response.deinit();

            if (response.tag != null and std.mem.eql(u8, response.tag.?, tag)) {
                if (!response.isSuccess()) {
                    // Clean up messages on error
                    for (messages.items) |*msg| {
                        msg.deinit();
                    }
                    messages.deinit();
                    return ImapError.CommandFailed;
                }
                break;
            } else if (response.tag == null and std.mem.indexOf(u8, response.message, "FETCH")) |_| {
                // Parse FETCH response
                const message_info = try self.parseFetchResponse(response.message);
                try messages.append(message_info);
            }
        }

        return messages;
    }

    fn parseFetchResponse(self: *Self, message: []const u8) !MessageInfo {
        _ = message; // unused for now
        // Basic FETCH response parsing - simplified for now
        const message_info = MessageInfo{
            .sequence_number = 1, // TODO: Parse from response
            .uid = null,
            .flags = &[_][]const u8{},
            .size = null,
            .envelope = null,
            .allocator = self.allocator,
        };

        // TODO: Implement full FETCH response parsing
        return message_info;
    }

    pub fn listMailboxes(self: *Self, reference: []const u8, pattern: []const u8) !std.ArrayList([]const u8) {
        const tag = try self.sendCommand("LIST {s} {s}", .{ reference, pattern });

        var mailboxes: std.ArrayList([]const u8) = .{};

        // Read responses until we get the tagged response
        while (true) {
            var response = try self.readResponse();
            defer response.deinit();

            if (response.tag != null and std.mem.eql(u8, response.tag.?, tag)) {
                if (!response.isSuccess()) {
                    // Clean up mailboxes on error
                    for (mailboxes.items) |mailbox| {
                        self.allocator.free(mailbox);
                    }
                    mailboxes.deinit(self.allocator);
                    return ImapError.CommandFailed;
                }
                break;
            } else if (response.tag == null and std.mem.startsWith(u8, response.message, "LIST")) {
                // Parse LIST response to extract mailbox name
                if (self.parseListResponse(response.message)) |mailbox_name| {
                    try mailboxes.append(self.allocator, mailbox_name);
                }
            }
        }

        return mailboxes;
    }

    fn parseListResponse(self: *Self, message: []const u8) ?[]const u8 {
        // Simple LIST response parsing - extract mailbox name (last quoted string)
        // Format: LIST (flags) "delimiter" "mailbox_name"
        if (std.mem.lastIndexOf(u8, message, "\"")) |last_quote| {
            if (std.mem.lastIndexOf(u8, message[0..last_quote], "\"")) |second_quote| {
                return self.allocator.dupe(u8, message[second_quote + 1 .. last_quote]) catch null;
            }
        }
        return null;
    }

    pub fn logout(self: *Self) !void {
        const tag = try self.sendCommand("LOGOUT", .{});
        var response = try self.readTaggedResponse(tag);
        defer response.deinit();

        if (self.stream) |*s| {
            s.close();
            self.stream = null;
        }

        self.is_authenticated = false;
    }

    fn sendCommand(self: *Self, comptime fmt: []const u8, args: anytype) ![]const u8 {
        if (self.stream == null) return ImapError.ConnectionClosed;

        const tag = try std.fmt.allocPrint(self.allocator, "A{:04}", .{self.tag_counter});
        self.tag_counter += 1;

        const command = try std.fmt.allocPrint(self.allocator, "{s} " ++ fmt ++ "\r\n", .{tag} ++ args);
        defer self.allocator.free(command);

        try self.stream.?.writeAll(command);
        return tag;
    }

    fn readResponse(self: *Self) !ImapResponse {
        if (self.stream == null) return ImapError.ConnectionClosed;

        var buffer: [4096]u8 = undefined;
        const line = try self.stream.?.readLine(buffer[0..]);

        return ImapResponse.parse(self.allocator, line);
    }

    fn readTaggedResponse(self: *Self, expected_tag: []const u8) !ImapResponse {
        while (true) {
            var response = try self.readResponse();

            if (response.tag != null and std.mem.eql(u8, response.tag.?, expected_tag)) {
                return response;
            } else {
                // Skip untagged responses
                response.deinit();
            }
        }
    }
};

test "imap response parsing" {
    const allocator = std.testing.allocator;

    var response = try ImapResponse.parse(allocator, "A001 OK LOGIN completed");
    defer response.deinit();

    try std.testing.expectEqualStrings("A001", response.tag.?);
    try std.testing.expect(response.response_type == .ok);
    try std.testing.expectEqualStrings("LOGIN completed", response.message);
}

test "imap capability parsing" {
    const capability = ImapCapability.fromString("IMAP4REV1");
    try std.testing.expect(capability == .imap4rev1);

    const auth_cap = ImapCapability.fromString("AUTH=PLAIN");
    try std.testing.expect(auth_cap == .auth_plain);
}
