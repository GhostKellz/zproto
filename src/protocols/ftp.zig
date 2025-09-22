//! FTP client implementation
const std = @import("std");
const net = std.net;
const common = @import("../common/common.zig");
const Stream = common.Stream;
const Parser = common.Parser;
const Auth = common.Auth;

pub const FtpError = error{
    InvalidResponse,
    AuthenticationFailed,
    TransferFailed,
    CommandFailed,
    PassiveModeError,
    FileNotFound,
} || common.Error || Stream.StreamError;

pub const FtpTransferMode = enum {
    active,
    passive,
};

pub const FtpTransferType = enum {
    ascii,
    binary,

    pub fn toString(self: FtpTransferType) []const u8 {
        return switch (self) {
            .ascii => "A",
            .binary => "I",
        };
    }
};

pub const FtpResponse = struct {
    code: u16,
    message: []const u8,
    is_multiline: bool,

    pub fn parse(allocator: std.mem.Allocator, data: []const u8) !FtpResponse {
        var lines = std.mem.splitSequence(u8, data, "\r\n");
        const first_line = lines.next() orelse return FtpError.InvalidResponse;

        if (first_line.len < 3) return FtpError.InvalidResponse;

        const code = std.fmt.parseInt(u16, first_line[0..3], 10) catch return FtpError.InvalidResponse;
        const is_multiline = first_line.len > 3 and first_line[3] == '-';

        var message_parts = std.ArrayList([]const u8).init(allocator);
        defer message_parts.deinit();

        // Add first line message (skip code and separator)
        const first_message = if (first_line.len > 4) first_line[4..] else "";
        try message_parts.append(first_message);

        if (is_multiline) {
            while (lines.next()) |line| {
                if (line.len >= 3) {
                    const line_code = std.fmt.parseInt(u16, line[0..3], 10) catch continue;
                    if (line_code == code and line.len > 3 and line[3] == ' ') {
                        // End of multiline response
                        if (line.len > 4) {
                            try message_parts.append(line[4..]);
                        }
                        break;
                    }
                }
                try message_parts.append(line);
            }
        }

        const message = try std.mem.join(allocator, "\n", message_parts.items);

        return FtpResponse{
            .code = code,
            .message = message,
            .is_multiline = is_multiline,
        };
    }

    pub fn deinit(self: *FtpResponse, allocator: std.mem.Allocator) void {
        allocator.free(self.message);
    }

    pub fn isSuccess(self: FtpResponse) bool {
        return self.code >= 200 and self.code < 300;
    }

    pub fn isIntermediate(self: FtpResponse) bool {
        return self.code >= 300 and self.code < 400;
    }

    pub fn isError(self: FtpResponse) bool {
        return self.code >= 400;
    }
};

pub const FtpClient = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    control_stream: ?Stream,
    data_stream: ?Stream,
    transfer_mode: FtpTransferMode,
    transfer_type: FtpTransferType,
    current_directory: ?[]const u8,

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .control_stream = null,
            .data_stream = null,
            .transfer_mode = .passive,
            .transfer_type = .binary,
            .current_directory = null,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.control_stream) |*stream| {
            stream.close();
        }
        if (self.data_stream) |*stream| {
            stream.close();
        }
        if (self.current_directory) |dir| {
            self.allocator.free(dir);
        }
    }

    pub fn connect(self: *Self, host: []const u8, port: u16) !void {
        const address = try net.Address.resolveIp(host, port);
        const tcp_stream = try net.tcpConnectToAddress(address);
        self.control_stream = Stream.initTcp(self.allocator, tcp_stream);

        // Read welcome message
        const welcome = try self.readResponse();
        defer welcome.deinit(self.allocator);

        if (!welcome.isSuccess()) {
            return FtpError.ConnectionFailed;
        }
    }

    pub fn login(self: *Self, username: []const u8, password: []const u8) !void {
        if (self.control_stream == null) return FtpError.ConnectionClosed;

        // Send USER command
        try self.sendCommand("USER {s}", .{username});
        const user_response = try self.readResponse();
        defer user_response.deinit(self.allocator);

        if (user_response.code == 230) {
            // Login successful, no password needed
            return;
        } else if (user_response.code == 331) {
            // Password required
            try self.sendCommand("PASS {s}", .{password});
            const pass_response = try self.readResponse();
            defer pass_response.deinit(self.allocator);

            if (!pass_response.isSuccess()) {
                return FtpError.AuthenticationFailed;
            }
        } else {
            return FtpError.AuthenticationFailed;
        }
    }

    pub fn setTransferType(self: *Self, transfer_type: FtpTransferType) !void {
        try self.sendCommand("TYPE {s}", .{transfer_type.toString()});
        const response = try self.readResponse();
        defer response.deinit(self.allocator);

        if (response.isSuccess()) {
            self.transfer_type = transfer_type;
        } else {
            return FtpError.CommandFailed;
        }
    }

    pub fn changeDirectory(self: *Self, path: []const u8) !void {
        try self.sendCommand("CWD {s}", .{path});
        const response = try self.readResponse();
        defer response.deinit(self.allocator);

        if (response.isSuccess()) {
            if (self.current_directory) |old_dir| {
                self.allocator.free(old_dir);
            }
            self.current_directory = try self.allocator.dupe(u8, path);
        } else {
            return FtpError.CommandFailed;
        }
    }

    pub fn getCurrentDirectory(self: *Self) ![]const u8 {
        try self.sendCommand("PWD", .{});
        const response = try self.readResponse();
        defer response.deinit(self.allocator);

        if (!response.isSuccess()) {
            return FtpError.CommandFailed;
        }

        // Parse directory from response message (format: "257 "/path" is current directory")
        const start = std.mem.indexOf(u8, response.message, "\"") orelse return FtpError.InvalidResponse;
        const end = std.mem.indexOfPos(u8, response.message, start + 1, "\"") orelse return FtpError.InvalidResponse;

        return self.allocator.dupe(u8, response.message[start + 1 .. end]);
    }

    pub fn listDirectory(self: *Self, path: ?[]const u8) ![]const u8 {
        // Set up data connection
        try self.setupDataConnection();
        defer self.closeDataConnection();

        // Send LIST command
        if (path) |dir_path| {
            try self.sendCommand("LIST {s}", .{dir_path});
        } else {
            try self.sendCommand("LIST", .{});
        }

        const response = try self.readResponse();
        defer response.deinit(self.allocator);

        if (!response.isIntermediate()) {
            return FtpError.CommandFailed;
        }

        // Read directory listing from data connection
        const listing = try self.readDataConnection();

        // Read final response
        const final_response = try self.readResponse();
        defer final_response.deinit(self.allocator);

        if (!final_response.isSuccess()) {
            self.allocator.free(listing);
            return FtpError.TransferFailed;
        }

        return listing;
    }

    pub fn downloadFile(self: *Self, remote_path: []const u8, local_path: []const u8) !void {
        // Set up data connection
        try self.setupDataConnection();
        defer self.closeDataConnection();

        // Send RETR command
        try self.sendCommand("RETR {s}", .{remote_path});
        const response = try self.readResponse();
        defer response.deinit(self.allocator);

        if (!response.isIntermediate()) {
            return FtpError.FileNotFound;
        }

        // Read file data
        const file_data = try self.readDataConnection();
        defer self.allocator.free(file_data);

        // Write to local file
        const file = try std.fs.cwd().createFile(local_path, .{});
        defer file.close();
        try file.writeAll(file_data);

        // Read final response
        const final_response = try self.readResponse();
        defer final_response.deinit(self.allocator);

        if (!final_response.isSuccess()) {
            return FtpError.TransferFailed;
        }
    }

    pub fn uploadFile(self: *Self, local_path: []const u8, remote_path: []const u8) !void {
        // Read local file
        const file = try std.fs.cwd().openFile(local_path, .{});
        defer file.close();
        const file_size = try file.getEndPos();
        const file_data = try self.allocator.alloc(u8, file_size);
        defer self.allocator.free(file_data);
        _ = try file.readAll(file_data);

        // Set up data connection
        try self.setupDataConnection();
        defer self.closeDataConnection();

        // Send STOR command
        try self.sendCommand("STOR {s}", .{remote_path});
        const response = try self.readResponse();
        defer response.deinit(self.allocator);

        if (!response.isIntermediate()) {
            return FtpError.CommandFailed;
        }

        // Send file data
        try self.data_stream.?.writeAll(file_data);
        self.closeDataConnection();

        // Read final response
        const final_response = try self.readResponse();
        defer final_response.deinit(self.allocator);

        if (!final_response.isSuccess()) {
            return FtpError.TransferFailed;
        }
    }

    pub fn deleteFile(self: *Self, remote_path: []const u8) !void {
        try self.sendCommand("DELE {s}", .{remote_path});
        const response = try self.readResponse();
        defer response.deinit(self.allocator);

        if (!response.isSuccess()) {
            return FtpError.CommandFailed;
        }
    }

    pub fn quit(self: *Self) !void {
        try self.sendCommand("QUIT", .{});
        const response = try self.readResponse();
        defer response.deinit(self.allocator);

        // Don't check response, server might close connection immediately
        if (self.control_stream) |*stream| {
            stream.close();
            self.control_stream = null;
        }
    }

    fn sendCommand(self: *Self, comptime fmt: []const u8, args: anytype) !void {
        if (self.control_stream == null) return FtpError.ConnectionClosed;

        const command = try std.fmt.allocPrint(self.allocator, fmt ++ "\r\n", args);
        defer self.allocator.free(command);

        try self.control_stream.?.writeAll(command);
    }

    fn readResponse(self: *Self) !FtpResponse {
        if (self.control_stream == null) return FtpError.ConnectionClosed;

        var response_data = std.ArrayList(u8).init(self.allocator);
        defer response_data.deinit();

        var buffer: [1024]u8 = undefined;

        while (true) {
            const line = try self.control_stream.?.readLine(buffer[0..]);
            try response_data.appendSlice(line);
            try response_data.appendSlice("\r\n");

            // Check if this is the end of a single-line or multi-line response
            if (line.len >= 3) {
                _ = std.fmt.parseInt(u16, line[0..3], 10) catch continue;
                if (line.len > 3 and line[3] == ' ') {
                    // Single line response or end of multi-line
                    break;
                } else if (line.len > 3 and line[3] == '-') {
                    // Start of multi-line response, continue reading
                    continue;
                }
            }
        }

        return FtpResponse.parse(self.allocator, response_data.items);
    }

    fn setupDataConnection(self: *Self) !void {
        if (self.transfer_mode == .passive) {
            try self.setupPassiveMode();
        } else {
            return FtpError.PassiveModeError; // Active mode not implemented yet
        }
    }

    fn setupPassiveMode(self: *Self) !void {
        try self.sendCommand("PASV", .{});
        const response = try self.readResponse();
        defer response.deinit(self.allocator);

        if (!response.isSuccess()) {
            return FtpError.PassiveModeError;
        }

        // Parse IP and port from response (format: "227 Entering Passive Mode (h1,h2,h3,h4,p1,p2)")
        const start = std.mem.indexOf(u8, response.message, "(") orelse return FtpError.InvalidResponse;
        const end = std.mem.indexOfPos(u8, response.message, start, ")") orelse return FtpError.InvalidResponse;
        const data_str = response.message[start + 1 .. end];

        var parts = std.mem.splitScalar(u8, data_str, ',');
        var ip_parts: [4]u8 = undefined;
        var port_parts: [2]u8 = undefined;

        for (0..4) |i| {
            const part = parts.next() orelse return FtpError.InvalidResponse;
            ip_parts[i] = try std.fmt.parseInt(u8, part, 10);
        }

        for (0..2) |i| {
            const part = parts.next() orelse return FtpError.InvalidResponse;
            port_parts[i] = try std.fmt.parseInt(u8, part, 10);
        }

        const data_port = (@as(u16, port_parts[0]) << 8) | port_parts[1];
        const data_address = net.Address.initIp4(ip_parts, data_port);

        const tcp_stream = try net.tcpConnectToAddress(data_address);
        self.data_stream = Stream.initTcp(self.allocator, tcp_stream);
    }

    fn readDataConnection(self: *Self) ![]const u8 {
        if (self.data_stream == null) return FtpError.ConnectionClosed;

        var data = std.ArrayList(u8).init(self.allocator);
        var buffer: [4096]u8 = undefined;

        while (true) {
            const bytes_read = self.data_stream.?.read(buffer[0..]) catch |err| switch (err) {
                error.ConnectionClosed => break,
                else => return err,
            };

            if (bytes_read == 0) break;
            try data.appendSlice(buffer[0..bytes_read]);
        }

        return data.toOwnedSlice();
    }

    fn closeDataConnection(self: *Self) void {
        if (self.data_stream) |*stream| {
            stream.close();
            self.data_stream = null;
        }
    }
};

test "ftp response parsing" {
    const allocator = std.testing.allocator;

    const single_line = "200 OK\r\n";
    var response = try FtpResponse.parse(allocator, single_line);
    defer response.deinit(allocator);

    try std.testing.expect(response.code == 200);
    try std.testing.expectEqualStrings("OK", response.message);
    try std.testing.expect(!response.is_multiline);
}
