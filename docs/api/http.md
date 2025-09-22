# HTTP Client API

The HTTP client provides a simple interface for making HTTP/HTTPS requests.

## HttpClient

### Initialization

```zig
const HttpClient = @import("zproto").http.HttpClient;

var client = HttpClient.init(allocator);
defer client.deinit();
```

### Methods

#### `get(url: []const u8) !HttpResponse`
Performs a GET request to the specified URL.

```zig
const response = try client.get("https://api.example.com/data");
defer response.deinit();

std.debug.print("Status: {}\n", .{response.status_code});
std.debug.print("Body: {s}\n", .{response.body});
```

#### `post(url: []const u8, body: ?[]const u8) !HttpResponse`
Performs a POST request with optional body content.

```zig
const json_body = "{\"name\": \"test\"}";
const response = try client.post("https://api.example.com/users", json_body);
defer response.deinit();
```

#### `request(method: HttpMethod, url: []const u8, body: ?[]const u8) !HttpResponse`
Performs a request with the specified HTTP method.

```zig
const response = try client.request(.PUT, "https://api.example.com/users/1", updated_data);
defer response.deinit();
```

### HTTP Methods

```zig
const HttpMethod = enum {
    GET,
    POST,
    PUT,
    DELETE,
    PATCH,
    HEAD,
    OPTIONS,
};
```

## HttpResponse

### Fields

- `status_code: u16` - HTTP status code (200, 404, etc.)
- `headers: HeaderMap` - Response headers
- `body: []const u8` - Response body content
- `allocator: std.mem.Allocator` - Memory allocator used

### Methods

#### `deinit()`
Frees all allocated memory. Must be called for every response.

```zig
const response = try client.get("https://example.com");
defer response.deinit(); // Important!
```

#### `getHeader(name: []const u8) ?[]const u8`
Retrieves a header value by name (case-insensitive).

```zig
if (response.getHeader("content-type")) |content_type| {
    std.debug.print("Content-Type: {s}\n", .{content_type});
}
```

## HeaderMap

Manages HTTP headers with case-insensitive access.

### Methods

#### `set(name: []const u8, value: []const u8) !void`
Sets a header value.

```zig
try client.default_headers.set("Authorization", "Bearer token123");
```

#### `get(name: []const u8) ?[]const u8`
Gets a header value by name.

#### `remove(name: []const u8) void`
Removes a header.

## URL Parsing

### UrlComponents

```zig
const UrlComponents = struct {
    scheme: []const u8,     // "http" or "https"
    host: []const u8,       // "example.com"
    port: u16,              // 80, 443, or custom
    path: []const u8,       // "/api/users"
    query: ?[]const u8,     // "?param=value"
    fragment: ?[]const u8,  // "#section"
};
```

### `parseUrl(url: []const u8) !UrlComponents`
Parses a URL string into components.

```zig
const components = try parseUrl("https://api.example.com:8080/users?active=true#results");
// components.scheme = "https"
// components.host = "api.example.com"
// components.port = 8080
// components.path = "/users"
// components.query = "active=true"
// components.fragment = "results"
```

## Examples

### Basic GET Request

```zig
const std = @import("std");
const zproto = @import("zproto");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    var client = zproto.http.HttpClient.init(allocator);
    defer client.deinit();
    
    const response = try client.get("https://httpbin.org/json");
    defer response.deinit();
    
    std.debug.print("Status: {}\n", .{response.status_code});
    std.debug.print("Body: {s}\n", .{response.body});
}
```

### POST with JSON

```zig
// Set content type header
try client.default_headers.set("Content-Type", "application/json");

const json_payload = 
    \\{
    \\  "name": "John Doe",
    \\  "email": "john@example.com"
    \\}
;

const response = try client.post("https://httpbin.org/post", json_payload);
defer response.deinit();

if (response.status_code == 200) {
    std.debug.print("Success: {s}\n", .{response.body});
} else {
    std.debug.print("Error: {} - {s}\n", .{ response.status_code, response.body });
}
```

### Custom Headers

```zig
// Add authentication
try client.default_headers.set("Authorization", "Bearer your-token-here");

// Add custom user agent
try client.default_headers.set("User-Agent", "MyApp/1.0");

// Make authenticated request
const response = try client.get("https://api.example.com/protected");
defer response.deinit();
```

## Error Handling

The HTTP client can return various errors:

```zig
const response = client.get("https://example.com") catch |err| switch (err) {
    error.NetworkError => {
        std.debug.print("Network connection failed\n", .{});
        return;
    },
    error.InvalidResponse => {
        std.debug.print("Server returned invalid response\n", .{});
        return;
    },
    error.OutOfMemory => {
        std.debug.print("Out of memory\n", .{});
        return;
    },
    else => return err,
};
```

## HTTPS Support

HTTPS requests are supported but require TLS implementation:

```zig
// HTTPS URLs are automatically detected
const response = try client.get("https://secure.example.com/api");
defer response.deinit();
```

**Note:** Current implementation includes TLS structure but requires completion for full HTTPS support.