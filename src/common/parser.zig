//! Common parsing utilities for protocol frames and messages
const std = @import("std");

pub const ParseError = error{
    InvalidFormat,
    UnexpectedEndOfData,
    BufferTooSmall,
};

/// Generic parser for various protocol formats
pub const Parser = struct {
    const Self = @This();

    data: []const u8,
    pos: usize,

    pub fn init(data: []const u8) Self {
        return Self{
            .data = data,
            .pos = 0,
        };
    }

    pub fn remaining(self: Self) usize {
        return self.data.len - self.pos;
    }

    pub fn peek(self: Self) ?u8 {
        if (self.pos >= self.data.len) return null;
        return self.data[self.pos];
    }

    pub fn advance(self: *Self, count: usize) !void {
        if (self.pos + count > self.data.len) return ParseError.UnexpectedEndOfData;
        self.pos += count;
    }

    pub fn readByte(self: *Self) !u8 {
        if (self.pos >= self.data.len) return ParseError.UnexpectedEndOfData;
        const byte = self.data[self.pos];
        self.pos += 1;
        return byte;
    }

    pub fn readBytes(self: *Self, count: usize) ![]const u8 {
        if (self.pos + count > self.data.len) return ParseError.UnexpectedEndOfData;
        const bytes = self.data[self.pos .. self.pos + count];
        self.pos += count;
        return bytes;
    }

    pub fn readU16Be(self: *Self) !u16 {
        const bytes = try self.readBytes(2);
        return std.mem.readInt(u16, bytes[0..2], .big);
    }

    pub fn readU32Be(self: *Self) !u32 {
        const bytes = try self.readBytes(4);
        return std.mem.readInt(u32, bytes[0..4], .big);
    }

    pub fn readLine(self: *Self) ![]const u8 {
        const start = self.pos;
        while (self.pos < self.data.len) {
            if (self.data[self.pos] == '\n') {
                const end = if (self.pos > start and self.data[self.pos - 1] == '\r')
                    self.pos - 1
                else
                    self.pos;
                self.pos += 1;
                return self.data[start..end];
            }
            self.pos += 1;
        }
        return ParseError.UnexpectedEndOfData;
    }

    pub fn readUntil(self: *Self, delimiter: u8) ![]const u8 {
        const start = self.pos;
        while (self.pos < self.data.len) {
            if (self.data[self.pos] == delimiter) {
                const result = self.data[start..self.pos];
                self.pos += 1;
                return result;
            }
            self.pos += 1;
        }
        return ParseError.UnexpectedEndOfData;
    }

    pub fn skipWhitespace(self: *Self) void {
        while (self.pos < self.data.len and std.ascii.isWhitespace(self.data[self.pos])) {
            self.pos += 1;
        }
    }

    pub fn expectBytes(self: *Self, expected: []const u8) !void {
        const actual = try self.readBytes(expected.len);
        if (!std.mem.eql(u8, actual, expected)) {
            return ParseError.InvalidFormat;
        }
    }
};

/// Line-based protocol parser (for HTTP, SMTP, FTP, etc.)
pub const LineParser = struct {
    const Self = @This();

    lines: std.ArrayList([]const u8),
    current: usize,

    pub fn init(allocator: std.mem.Allocator, data: []const u8) !Self {
        var lines = std.ArrayList([]const u8).init(allocator);

        var it = std.mem.split(u8, data, "\n");
        while (it.next()) |line| {
            // Remove trailing \r if present
            const trimmed = if (line.len > 0 and line[line.len - 1] == '\r')
                line[0 .. line.len - 1]
            else
                line;
            try lines.append(trimmed);
        }

        return Self{
            .lines = lines,
            .current = 0,
        };
    }

    pub fn deinit(self: *Self) void {
        self.lines.deinit();
    }

    pub fn nextLine(self: *Self) ?[]const u8 {
        if (self.current >= self.lines.items.len) return null;
        const line = self.lines.items[self.current];
        self.current += 1;
        return line;
    }

    pub fn peekLine(self: Self) ?[]const u8 {
        if (self.current >= self.lines.items.len) return null;
        return self.lines.items[self.current];
    }
};

test "parser basic operations" {
    const data = "Hello\r\nWorld\r\n\r\nData";
    var parser = Parser.init(data);

    const line1 = try parser.readLine();
    try std.testing.expectEqualStrings("Hello", line1);

    const line2 = try parser.readLine();
    try std.testing.expectEqualStrings("World", line2);

    const empty_line = try parser.readLine();
    try std.testing.expectEqualStrings("", empty_line);
}

test "line parser" {
    const allocator = std.testing.allocator;
    const data = "Line 1\r\nLine 2\nLine 3";

    var line_parser = try LineParser.init(allocator, data);
    defer line_parser.deinit();

    try std.testing.expectEqualStrings("Line 1", line_parser.nextLine().?);
    try std.testing.expectEqualStrings("Line 2", line_parser.nextLine().?);
    try std.testing.expectEqualStrings("Line 3", line_parser.nextLine().?);
    try std.testing.expect(line_parser.nextLine() == null);
}
