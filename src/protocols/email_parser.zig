//! Email parsing utilities for MIME messages, headers, and attachments
const std = @import("std");

pub const EmailParseError = error{
    InvalidHeader,
    InvalidBoundary,
    MalformedMessage,
    UnsupportedEncoding,
    OutOfMemory,
};

pub const HeaderMap = struct {
    headers: std.StringHashMap([]const u8),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) HeaderMap {
        return HeaderMap{
            .headers = std.StringHashMap([]const u8).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *HeaderMap) void {
        var iterator = self.headers.iterator();
        while (iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.headers.deinit();
    }

    pub fn set(self: *HeaderMap, name: []const u8, value: []const u8) !void {
        // Convert header name to lowercase for case-insensitive access
        var lowercase_name = try self.allocator.alloc(u8, name.len);
        for (name, 0..) |char, i| {
            lowercase_name[i] = std.ascii.toLower(char);
        }

        const owned_value = try self.allocator.dupe(u8, value);
        try self.headers.put(lowercase_name, owned_value);
    }

    pub fn get(self: HeaderMap, name: []const u8) ?[]const u8 {
        // Create temporary lowercase version for lookup
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const temp_allocator = arena.allocator();

        const lowercase_name = temp_allocator.alloc(u8, name.len) catch return null;
        for (name, 0..) |char, i| {
            lowercase_name[i] = std.ascii.toLower(char);
        }

        return self.headers.get(lowercase_name);
    }

    pub fn contains(self: HeaderMap, name: []const u8) bool {
        return self.get(name) != null;
    }
};

pub const ContentType = struct {
    media_type: []const u8,
    subtype: []const u8,
    parameters: std.StringHashMap([]const u8),
    allocator: std.mem.Allocator,

    pub fn parse(allocator: std.mem.Allocator, content_type_header: []const u8) !ContentType {
        var parameters = std.StringHashMap([]const u8).init(allocator);

        // Split on semicolons to separate main type from parameters
        var parts = std.mem.splitScalar(u8, content_type_header, ';');

        const main_type = std.mem.trim(u8, parts.next() orelse return EmailParseError.InvalidHeader, " \t");

        // Parse media type and subtype
        const slash_pos = std.mem.indexOf(u8, main_type, "/") orelse return EmailParseError.InvalidHeader;
        const media_type = try allocator.dupe(u8, main_type[0..slash_pos]);
        const subtype = try allocator.dupe(u8, main_type[slash_pos + 1 ..]);

        // Parse parameters
        while (parts.next()) |param| {
            const trimmed = std.mem.trim(u8, param, " \t");
            const eq_pos = std.mem.indexOf(u8, trimmed, "=") orelse continue;

            const param_name = try allocator.dupe(u8, std.mem.trim(u8, trimmed[0..eq_pos], " \t"));
            var param_value = std.mem.trim(u8, trimmed[eq_pos + 1 ..], " \t");

            // Remove quotes if present
            if (param_value.len >= 2 and param_value[0] == '"' and param_value[param_value.len - 1] == '"') {
                param_value = param_value[1 .. param_value.len - 1];
            }

            const owned_value = try allocator.dupe(u8, param_value);
            try parameters.put(param_name, owned_value);
        }

        return ContentType{
            .media_type = media_type,
            .subtype = subtype,
            .parameters = parameters,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ContentType) void {
        self.allocator.free(self.media_type);
        self.allocator.free(self.subtype);

        var iterator = self.parameters.iterator();
        while (iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.parameters.deinit();
    }

    pub fn isText(self: ContentType) bool {
        return std.mem.eql(u8, self.media_type, "text");
    }

    pub fn isMultipart(self: ContentType) bool {
        return std.mem.eql(u8, self.media_type, "multipart");
    }

    pub fn getParameter(self: ContentType, name: []const u8) ?[]const u8 {
        return self.parameters.get(name);
    }

    pub fn getBoundary(self: ContentType) ?[]const u8 {
        return self.getParameter("boundary");
    }

    pub fn getCharset(self: ContentType) []const u8 {
        return self.getParameter("charset") orelse "utf-8";
    }
};

pub const MimePart = struct {
    headers: HeaderMap,
    content: []const u8,
    content_type: ?ContentType,
    children: std.ArrayList(*MimePart),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) MimePart {
        return MimePart{
            .headers = HeaderMap.init(allocator),
            .content = "",
            .content_type = null,
            .children = std.ArrayList(*MimePart).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *MimePart) void {
        self.headers.deinit();
        self.allocator.free(self.content);

        if (self.content_type) |*ct| {
            ct.deinit();
        }

        for (self.children.items) |child| {
            child.deinit();
            self.allocator.destroy(child);
        }
        self.children.deinit();
    }

    pub fn isMultipart(self: MimePart) bool {
        if (self.content_type) |ct| {
            return ct.isMultipart();
        }
        return false;
    }

    pub fn isText(self: MimePart) bool {
        if (self.content_type) |ct| {
            return ct.isText();
        }
        return false;
    }

    pub fn getHeader(self: MimePart, name: []const u8) ?[]const u8 {
        return self.headers.get(name);
    }

    pub fn getDecodedContent(self: MimePart) ![]const u8 {
        const encoding = self.getHeader("content-transfer-encoding") orelse "7bit";

        if (std.mem.eql(u8, encoding, "base64")) {
            return try decodeBase64(self.allocator, self.content);
        } else if (std.mem.eql(u8, encoding, "quoted-printable")) {
            return try decodeQuotedPrintable(self.allocator, self.content);
        } else {
            // 7bit, 8bit, binary - return as-is
            return try self.allocator.dupe(u8, self.content);
        }
    }
};

pub const EmailMessage = struct {
    headers: HeaderMap,
    parts: std.ArrayList(MimePart),
    raw_message: []const u8,
    allocator: std.mem.Allocator,

    pub fn parse(allocator: std.mem.Allocator, raw_message: []const u8) !EmailMessage {
        const owned_message = try allocator.dupe(u8, raw_message);

        var email = EmailMessage{
            .headers = HeaderMap.init(allocator),
            .parts = std.ArrayList(MimePart).init(allocator),
            .raw_message = owned_message,
            .allocator = allocator,
        };

        // Find the boundary between headers and body
        const header_end = std.mem.indexOf(u8, owned_message, "\r\n\r\n") orelse
            std.mem.indexOf(u8, owned_message, "\n\n") orelse owned_message.len;

        // Parse headers
        try parseHeaders(allocator, owned_message[0..header_end], &email.headers);

        // Parse body
        const body_start = if (header_end < owned_message.len) header_end + 4 else owned_message.len;
        if (body_start < owned_message.len) {
            const body = owned_message[body_start..];
            try parseBody(allocator, body, &email.headers, &email.parts);
        }

        return email;
    }

    pub fn deinit(self: *EmailMessage) void {
        self.headers.deinit();

        for (self.parts.items) |*part| {
            part.deinit();
        }
        self.parts.deinit();

        self.allocator.free(self.raw_message);
    }

    pub fn getHeader(self: EmailMessage, name: []const u8) ?[]const u8 {
        return self.headers.get(name);
    }

    pub fn getSubject(self: EmailMessage) ?[]const u8 {
        return self.getHeader("subject");
    }

    pub fn getFrom(self: EmailMessage) ?[]const u8 {
        return self.getHeader("from");
    }

    pub fn getTo(self: EmailMessage) ?[]const u8 {
        return self.getHeader("to");
    }

    pub fn getTextContent(self: EmailMessage) !?[]const u8 {
        for (self.parts.items) |part| {
            if (part.isText()) {
                if (part.content_type) |ct| {
                    if (std.mem.eql(u8, ct.subtype, "plain")) {
                        return try part.getDecodedContent();
                    }
                }
            }
        }
        return null;
    }

    pub fn getHtmlContent(self: EmailMessage) !?[]const u8 {
        for (self.parts.items) |part| {
            if (part.isText()) {
                if (part.content_type) |ct| {
                    if (std.mem.eql(u8, ct.subtype, "html")) {
                        return try part.getDecodedContent();
                    }
                }
            }
        }
        return null;
    }

    pub fn getAttachments(self: EmailMessage) !std.ArrayList(MimePart) {
        var attachments = std.ArrayList(MimePart).init(self.allocator);

        for (self.parts.items) |part| {
            if (part.getHeader("content-disposition")) |disposition| {
                if (std.mem.startsWith(u8, disposition, "attachment")) {
                    try attachments.append(part);
                }
            }
        }

        return attachments;
    }
};

fn parseHeaders(allocator: std.mem.Allocator, header_text: []const u8, headers: *HeaderMap) !void {
    var lines = std.mem.splitSequence(u8, header_text, "\n");
    var current_header_name: ?[]const u8 = null;
    var current_header_value = std.ArrayList(u8).init(allocator);
    defer current_header_value.deinit();

    while (lines.next()) |line| {
        const trimmed_line = std.mem.trim(u8, line, " \t\r");

        if (trimmed_line.len == 0) continue;

        // Check if this is a continuation line (starts with whitespace)
        if (trimmed_line[0] == ' ' or trimmed_line[0] == '\t') {
            if (current_header_name != null) {
                try current_header_value.append(' ');
                try current_header_value.appendSlice(std.mem.trim(u8, trimmed_line, " \t"));
            }
        } else {
            // Save previous header if exists
            if (current_header_name) |name| {
                try headers.set(name, current_header_value.items);
                current_header_value.clearAndFree();
            }

            // Parse new header
            const colon_pos = std.mem.indexOf(u8, trimmed_line, ":") orelse continue;
            current_header_name = std.mem.trim(u8, trimmed_line[0..colon_pos], " \t");
            const header_value = std.mem.trim(u8, trimmed_line[colon_pos + 1 ..], " \t");
            try current_header_value.appendSlice(header_value);
        }
    }

    // Save the last header
    if (current_header_name) |name| {
        try headers.set(name, current_header_value.items);
    }
}

fn parseBody(allocator: std.mem.Allocator, body: []const u8, headers: *HeaderMap, parts: *std.ArrayList(MimePart)) !void {
    const content_type_header = headers.get("content-type") orelse "text/plain";

    const content_type = ContentType.parse(allocator, content_type_header) catch |err| {
        // If parsing fails, treat as plain text
        if (err == EmailParseError.InvalidHeader) {
            var part = MimePart.init(allocator);
            part.content = try allocator.dupe(u8, body);
            try parts.append(part);
            return;
        }
        return err;
    };
    defer content_type.deinit();

    if (content_type.isMultipart()) {
        if (content_type.getBoundary()) |boundary| {
            try parseMultipartBody(allocator, body, boundary, parts);
        } else {
            return EmailParseError.InvalidBoundary;
        }
    } else {
        // Single part message
        var part = MimePart.init(allocator);
        part.content = try allocator.dupe(u8, body);
        part.content_type = try ContentType.parse(allocator, content_type_header);
        try parts.append(part);
    }
}

fn parseMultipartBody(allocator: std.mem.Allocator, body: []const u8, boundary: []const u8, parts: *std.ArrayList(MimePart)) !void {
    const boundary_start = try std.fmt.allocPrint(allocator, "--{s}", .{boundary});
    defer allocator.free(boundary_start);

    const boundary_end = try std.fmt.allocPrint(allocator, "--{s}--", .{boundary});
    defer allocator.free(boundary_end);

    var current_pos: usize = 0;

    // Find first boundary
    if (std.mem.indexOf(u8, body[current_pos..], boundary_start)) |first_boundary| {
        current_pos += first_boundary + boundary_start.len;

        // Skip to end of boundary line
        if (std.mem.indexOf(u8, body[current_pos..], "\n")) |newline| {
            current_pos += newline + 1;
        }
    }

    while (current_pos < body.len) {
        // Find next boundary
        const next_boundary = std.mem.indexOf(u8, body[current_pos..], boundary_start);
        const end_boundary = std.mem.indexOf(u8, body[current_pos..], boundary_end);

        const part_end = if (next_boundary != null and (end_boundary == null or next_boundary.? < end_boundary.?))
            current_pos + next_boundary.?
        else if (end_boundary != null)
            current_pos + end_boundary.?
        else
            body.len;

        if (part_end > current_pos) {
            const part_data = body[current_pos..part_end];

            // Parse this part
            const part = try parseEmailPart(allocator, part_data);
            try parts.append(part);
        }

        if (end_boundary != null and current_pos + end_boundary.? == part_end) {
            // Reached final boundary
            break;
        }

        // Move to next part
        current_pos = part_end + boundary_start.len;
        if (std.mem.indexOf(u8, body[current_pos..], "\n")) |newline| {
            current_pos += newline + 1;
        }
    }
}

fn parseEmailPart(allocator: std.mem.Allocator, part_data: []const u8) !MimePart {
    var part = MimePart.init(allocator);

    // Find boundary between headers and content
    const header_end = std.mem.indexOf(u8, part_data, "\r\n\r\n") orelse
        std.mem.indexOf(u8, part_data, "\n\n") orelse part_data.len;

    // Parse part headers
    if (header_end > 0) {
        try parseHeaders(allocator, part_data[0..header_end], &part.headers);
    }

    // Extract content
    const content_start = if (header_end < part_data.len) header_end + 4 else part_data.len;
    if (content_start < part_data.len) {
        part.content = try allocator.dupe(u8, part_data[content_start..]);
    }

    // Parse content type if present
    if (part.headers.get("content-type")) |ct_header| {
        part.content_type = ContentType.parse(allocator, ct_header) catch null;
    }

    return part;
}

fn decodeBase64(allocator: std.mem.Allocator, encoded: []const u8) ![]const u8 {
    const decoder = std.base64.standard.Decoder;
    const max_decoded_size = try decoder.calcSizeForSlice(encoded);
    const decoded = try allocator.alloc(u8, max_decoded_size);

    const actual_size = try decoder.decode(decoded, encoded);
    return allocator.realloc(decoded, actual_size);
}

fn decodeQuotedPrintable(allocator: std.mem.Allocator, encoded: []const u8) ![]const u8 {
    var decoded = std.ArrayList(u8).init(allocator);
    defer decoded.deinit();

    var i: usize = 0;
    while (i < encoded.len) {
        if (encoded[i] == '=') {
            if (i + 2 < encoded.len) {
                const hex = encoded[i + 1 .. i + 3];
                const byte_value = std.fmt.parseInt(u8, hex, 16) catch {
                    try decoded.append(encoded[i]);
                    i += 1;
                    continue;
                };
                try decoded.append(byte_value);
                i += 3;
                continue;
            }
        }
        try decoded.append(encoded[i]);
        i += 1;
    }

    return decoded.toOwnedSlice();
}

test "content type parsing" {
    const allocator = std.testing.allocator;

    var ct = try ContentType.parse(allocator, "text/html; charset=utf-8; boundary=\"boundary123\"");
    defer ct.deinit();

    try std.testing.expectEqualStrings("text", ct.media_type);
    try std.testing.expectEqualStrings("html", ct.subtype);
    try std.testing.expectEqualStrings("utf-8", ct.getCharset());
    try std.testing.expectEqualStrings("boundary123", ct.getBoundary().?);
}

test "header parsing" {
    const allocator = std.testing.allocator;

    var headers = HeaderMap.init(allocator);
    defer headers.deinit();

    const header_text = "From: sender@example.com\r\nTo: recipient@example.com\r\nSubject: Test Email\r\n";
    try parseHeaders(allocator, header_text, &headers);

    try std.testing.expectEqualStrings("sender@example.com", headers.get("from").?);
    try std.testing.expectEqualStrings("recipient@example.com", headers.get("to").?);
    try std.testing.expectEqualStrings("Test Email", headers.get("subject").?);
}
