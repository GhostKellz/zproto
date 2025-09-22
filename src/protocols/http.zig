//! HTTP/HTTPS client and server implementation
const std = @import("std");
const net = std.net;
const common = @import("../common/common.zig");
const Stream = common.Stream;
const Parser = common.Parser;
const Auth = common.Auth;

pub const HttpError = error{
    InvalidUrl,
    InvalidMethod,
    InvalidStatusCode,
    InvalidHeader,
    ChunkedEncodingError,
    RedirectLoop,
} || Stream.StreamError || common.Error;

pub const HttpMethod = enum {
    GET,
    POST,
    PUT,
    DELETE,
    HEAD,
    OPTIONS,
    PATCH,
    TRACE,

    pub fn toString(self: HttpMethod) []const u8 {
        return switch (self) {
            .GET => "GET",
            .POST => "POST",
            .PUT => "PUT",
            .DELETE => "DELETE",
            .HEAD => "HEAD",
            .OPTIONS => "OPTIONS",
            .PATCH => "PATCH",
            .TRACE => "TRACE",
        };
    }
};

pub const HttpVersion = enum {
    http_1_0,
    http_1_1,
    http_2,

    pub fn toString(self: HttpVersion) []const u8 {
        return switch (self) {
            .http_1_0 => "HTTP/1.0",
            .http_1_1 => "HTTP/1.1",
            .http_2 => "HTTP/2",
        };
    }
};

pub const HttpStatus = struct {
    code: u16,
    phrase: []const u8,

    pub fn fromCode(code: u16) HttpStatus {
        const phrase = switch (code) {
            200 => "OK",
            201 => "Created",
            204 => "No Content",
            301 => "Moved Permanently",
            302 => "Found",
            304 => "Not Modified",
            400 => "Bad Request",
            401 => "Unauthorized",
            403 => "Forbidden",
            404 => "Not Found",
            405 => "Method Not Allowed",
            500 => "Internal Server Error",
            501 => "Not Implemented",
            502 => "Bad Gateway",
            503 => "Service Unavailable",
            else => "Unknown",
        };

        return HttpStatus{
            .code = code,
            .phrase = phrase,
        };
    }
};

pub const HttpHeaders = struct {
    const Self = @This();

    headers: std.StringHashMap([]const u8),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .headers = std.StringHashMap([]const u8).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        // Free all allocated header keys and values
        var iterator = self.headers.iterator();
        while (iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.headers.deinit();
    }

    pub fn set(self: *Self, name: []const u8, value: []const u8) !void {
        const owned_name = try self.allocator.dupe(u8, name);
        const owned_value = try self.allocator.dupe(u8, value);
        try self.headers.put(owned_name, owned_value);
    }

    pub fn get(self: Self, name: []const u8) ?[]const u8 {
        return self.headers.get(name);
    }

    pub fn remove(self: *Self, name: []const u8) void {
        if (self.headers.fetchRemove(name)) |kv| {
            self.allocator.free(kv.key);
            self.allocator.free(kv.value);
        }
    }

    pub fn writeToStream(self: Self, stream: *Stream) !void {
        var iterator = self.headers.iterator();
        while (iterator.next()) |entry| {
            const header_line = try std.fmt.allocPrint(self.allocator, "{s}: {s}\r\n", .{ entry.key_ptr.*, entry.value_ptr.* });
            defer self.allocator.free(header_line);
            try stream.writeAll(header_line);
        }
    }
};

pub const HttpRequest = struct {
    const Self = @This();

    method: HttpMethod,
    uri: []const u8,
    version: HttpVersion,
    headers: HttpHeaders,
    body: ?[]const u8,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, method: HttpMethod, uri: []const u8) !Self {
        return Self{
            .method = method,
            .uri = try allocator.dupe(u8, uri),
            .version = .http_1_1,
            .headers = HttpHeaders.init(allocator),
            .body = null,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.uri);
        self.headers.deinit();
        if (self.body) |body| {
            self.allocator.free(body);
        }
    }

    pub fn setBody(self: *Self, body: []const u8) !void {
        if (self.body) |old_body| {
            self.allocator.free(old_body);
        }
        self.body = try self.allocator.dupe(u8, body);

        // Set Content-Length header
        const content_length = try std.fmt.allocPrint(self.allocator, "{d}", .{body.len});
        defer self.allocator.free(content_length);
        try self.headers.set("Content-Length", content_length);
    }

    pub fn writeToStream(self: Self, stream: *Stream) !void {
        // Request line
        const request_line = try std.fmt.allocPrint(self.allocator, "{s} {s} {s}\r\n", .{ self.method.toString(), self.uri, self.version.toString() });
        defer self.allocator.free(request_line);
        try stream.writeAll(request_line);

        // Headers
        try self.headers.writeToStream(stream);

        // Empty line
        try stream.writeAll("\r\n");

        // Body
        if (self.body) |body| {
            try stream.writeAll(body);
        }
    }
};

pub const HttpResponse = struct {
    const Self = @This();

    version: HttpVersion,
    status: HttpStatus,
    headers: HttpHeaders,
    body: ?[]const u8,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .version = .http_1_1,
            .status = HttpStatus.fromCode(200),
            .headers = HttpHeaders.init(allocator),
            .body = null,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.headers.deinit();
        if (self.body) |body| {
            self.allocator.free(body);
        }
    }

    pub fn parseFromStream(allocator: std.mem.Allocator, stream: *Stream) !Self {
        var response = Self.init(allocator);

        // Read status line
        var buffer: [8192]u8 = undefined;
        const status_line = try stream.readLine(buffer[0..]);
        try response.parseStatusLine(status_line);

        // Read headers
        while (true) {
            const header_line = try stream.readLine(buffer[0..]);
            if (header_line.len == 0) break; // Empty line indicates end of headers

            try response.parseHeaderLine(header_line);
        }

        // Read body if Content-Length is specified
        if (response.headers.get("Content-Length")) |content_length_str| {
            const content_length = try std.fmt.parseInt(usize, content_length_str, 10);
            const body = try allocator.alloc(u8, content_length);
            var total_read: usize = 0;

            while (total_read < content_length) {
                const bytes_read = try stream.read(body[total_read..]);
                if (bytes_read == 0) return HttpError.ConnectionClosed;
                total_read += bytes_read;
            }

            response.body = body;
        }
        // TODO: Handle chunked encoding

        return response;
    }

    fn parseStatusLine(self: *Self, line: []const u8) !void {
        var parts = std.mem.splitScalar(u8, line, ' ');

        // Parse version
        const version_str = parts.next() orelse return HttpError.InvalidStatusCode;
        self.version = if (std.mem.eql(u8, version_str, "HTTP/1.0"))
            .http_1_0
        else if (std.mem.eql(u8, version_str, "HTTP/1.1"))
            .http_1_1
        else if (std.mem.eql(u8, version_str, "HTTP/2"))
            .http_2
        else
            return HttpError.InvalidStatusCode;

        // Parse status code
        const status_code_str = parts.next() orelse return HttpError.InvalidStatusCode;
        const status_code = try std.fmt.parseInt(u16, status_code_str, 10);

        // Parse reason phrase (rest of the line)
        const reason_phrase = parts.rest();

        self.status = HttpStatus{
            .code = status_code,
            .phrase = try self.allocator.dupe(u8, reason_phrase),
        };
    }

    fn parseHeaderLine(self: *Self, line: []const u8) !void {
        const colon_pos = std.mem.indexOf(u8, line, ":") orelse return HttpError.InvalidHeader;

        const name = std.mem.trim(u8, line[0..colon_pos], " \t");
        const value = std.mem.trim(u8, line[colon_pos + 1 ..], " \t");

        try self.headers.set(name, value);
    }
};

pub const HttpClient = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    default_headers: HttpHeaders,

    pub fn init(allocator: std.mem.Allocator) Self {
        var default_headers = HttpHeaders.init(allocator);
        default_headers.set("User-Agent", "zproto/0.1.0") catch {};
        default_headers.set("Connection", "close") catch {};

        return Self{
            .allocator = allocator,
            .default_headers = default_headers,
        };
    }

    pub fn deinit(self: *Self) void {
        self.default_headers.deinit();
    }

    pub fn get(self: *Self, url: []const u8) !HttpResponse {
        return self.request(.GET, url, null);
    }

    pub fn post(self: *Self, url: []const u8, body: ?[]const u8) !HttpResponse {
        return self.request(.POST, url, body);
    }

    pub fn request(self: *Self, method: HttpMethod, url: []const u8, body: ?[]const u8) !HttpResponse {
        const parsed_url = try self.parseUrl(url);
        defer self.allocator.free(parsed_url.host);
        defer self.allocator.free(parsed_url.path);

        // Create connection
        const address = try net.Address.resolveIp(parsed_url.host, parsed_url.port);
        const tcp_stream = try net.tcpConnectToAddress(address);
        var stream = if (parsed_url.is_https)
            Stream.initTls(self.allocator, tcp_stream)
        else
            Stream.initTcp(self.allocator, tcp_stream);
        defer stream.close();

        // Create request
        var http_request = try HttpRequest.init(self.allocator, method, parsed_url.path);
        defer http_request.deinit();

        // Set default headers
        try http_request.headers.set("Host", parsed_url.host);
        var header_iter = self.default_headers.headers.iterator();
        while (header_iter.next()) |entry| {
            try http_request.headers.set(entry.key_ptr.*, entry.value_ptr.*);
        }

        // Set body if provided
        if (body) |request_body| {
            try http_request.setBody(request_body);
        }

        // Send request
        try http_request.writeToStream(&stream);

        // Read response
        return HttpResponse.parseFromStream(self.allocator, &stream);
    }

    const ParsedUrl = struct {
        is_https: bool,
        host: []const u8,
        port: u16,
        path: []const u8,
    };

    fn parseUrl(self: *Self, url: []const u8) !ParsedUrl {
        var remaining = url;

        // Parse scheme
        const is_https = if (std.mem.startsWith(u8, remaining, "https://")) blk: {
            remaining = remaining[8..];
            break :blk true;
        } else if (std.mem.startsWith(u8, remaining, "http://")) blk: {
            remaining = remaining[7..];
            break :blk false;
        } else {
            return HttpError.InvalidUrl;
        };

        // Find path separator
        const path_start = std.mem.indexOf(u8, remaining, "/") orelse remaining.len;
        const host_port = remaining[0..path_start];
        const path = if (path_start < remaining.len) remaining[path_start..] else "/";

        // Parse host and port
        const port_start = std.mem.indexOf(u8, host_port, ":");
        const host = if (port_start) |pos| host_port[0..pos] else host_port;
        const port = if (port_start) |pos|
            try std.fmt.parseInt(u16, host_port[pos + 1 ..], 10)
        else if (is_https)
            @as(u16, 443)
        else
            @as(u16, 80);

        return ParsedUrl{
            .is_https = is_https,
            .host = try self.allocator.dupe(u8, host),
            .port = port,
            .path = try self.allocator.dupe(u8, path),
        };
    }
};

test "http request creation" {
    const allocator = std.testing.allocator;

    var request = HttpRequest.init(allocator, .GET, "/test");
    defer request.deinit();

    try request.headers.set("User-Agent", "test");
    try std.testing.expectEqualStrings("/test", request.uri);
    try std.testing.expectEqualStrings("test", request.headers.get("User-Agent").?);
}

test "http status parsing" {
    const status = HttpStatus.fromCode(404);
    try std.testing.expect(status.code == 404);
    try std.testing.expectEqualStrings("Not Found", status.phrase);
}
