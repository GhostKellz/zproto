# Getting Started with zproto

Welcome to **zproto**, the modern Zig protocol suite! This guide will help you get up and running quickly.

## 📦 Installation

### Prerequisites

- **Zig 0.16.0-dev.164+** (or compatible version)
- Linux, macOS, or Windows

### Adding to Your Project

1. **Using Zig Package Manager (recommended):**

```bash
# Add zproto to your build.zig.zon
zig fetch --save https://github.com/ghostkellz/zproto/archive/main.tar.gz
```

2. **In your `build.zig`:**

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    // ... existing build setup ...
    
    // Add zproto dependency
    const zproto = b.dependency("zproto", .{
        .target = target,
        .optimize = optimize,
    });
    
    // Add to your executable
    exe.root_module.addImport("zproto", zproto.module("zproto"));
}
```

3. **Clone and build locally:**

```bash
git clone https://github.com/ghostkellz/zproto.git
cd zproto
zig build
```

## 🚀 First Steps

### Basic HTTP Request

```zig
const std = @import("std");
const zproto = @import("zproto");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Create HTTP client
    var http_client = zproto.http.HttpClient.init(allocator);
    defer http_client.deinit();
    
    // Make a GET request
    const response = try http_client.get("https://httpbin.org/json");
    defer response.deinit();
    
    std.debug.print("Status: {}\n", .{response.status_code});
    std.debug.print("Response: {s}\n", .{response.body});
}
```

### DNS Lookup

```zig
const std = @import("std");
const zproto = @import("zproto");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Create DNS client with default servers
    var dns_client = try zproto.dns.DnsClient.initWithDefaultServers(allocator);
    defer dns_client.deinit();
    
    // Resolve domain name
    const result = try dns_client.resolve("example.com", .A);
    defer result.deinit();
    
    std.debug.print("Resolved {s}:\n", .{"example.com"});
    for (result.answers) |answer| {
        if (answer == .A) {
            const ip = answer.A.address;
            std.debug.print("  {} (TTL: {}s)\n", .{ ip, answer.A.ttl });
        }
    }
}
```

### Send Email

```zig
const std = @import("std");
const zproto = @import("zproto");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Create SMTP client
    var smtp_client = zproto.smtp.SmtpClient.init(allocator);
    defer smtp_client.deinit();
    
    // Configure email
    const email = zproto.smtp.Email{
        .from = "sender@example.com",
        .to = &[_][]const u8{"recipient@example.com"},
        .subject = "Hello from zproto!",
        .body = "This email was sent using the zproto SMTP client.",
    };
    
    // Send email (requires SMTP server configuration)
    try smtp_client.sendEmail("smtp.example.com", 587, .{
        .username = "your-username",
        .password = "your-password",
        .auth_method = .PLAIN,
    }, email);
    
    std.debug.print("Email sent successfully!\n", .{});
}
```

## 🏗️ Project Structure

When using zproto in your project, organize your code like this:

```
your-project/
├── build.zig
├── build.zig.zon
├── src/
│   ├── main.zig
│   ├── http_client.zig      # Your HTTP logic
│   ├── email_service.zig    # Email functionality
│   └── dns_resolver.zig     # DNS operations
└── examples/
    ├── basic_http.zig
    └── send_email.zig
```

## 🔧 Configuration

### Setting Default Headers

```zig
var http_client = zproto.http.HttpClient.init(allocator);
defer http_client.deinit();

// Set default headers for all requests
try http_client.default_headers.set("User-Agent", "MyApp/1.0");
try http_client.default_headers.set("Accept", "application/json");
```

### Custom DNS Servers

```zig
// Use custom DNS servers
const servers = &[_][]const u8{
    "8.8.8.8",      // Google
    "1.1.1.1",      // Cloudflare
    "208.67.222.222" // OpenDNS
};

var dns_client = try zproto.dns.DnsClient.init(allocator, servers);
defer dns_client.deinit();
```

### SMTP Authentication

```zig
const smtp_config = zproto.smtp.SmtpConfig{
    .username = "your-email@gmail.com",
    .password = "your-app-password",
    .auth_method = .LOGIN,
    .use_tls = true,
};

try smtp_client.connect("smtp.gmail.com", 587, smtp_config);
```

## 🎯 Common Patterns

### Error Handling

```zig
const response = http_client.get("https://api.example.com") catch |err| switch (err) {
    error.NetworkError => {
        std.log.err("Failed to connect to server", .{});
        return;
    },
    error.InvalidResponse => {
        std.log.err("Server returned invalid response", .{});
        return;
    },
    error.OutOfMemory => {
        std.log.err("Out of memory", .{});
        return;
    },
    else => {
        std.log.err("Unexpected error: {}", .{err});
        return err;
    },
};
```

### Memory Management

```zig
// Always call deinit() for clients
var client = SomeClient.init(allocator);
defer client.deinit(); // This is required!

// Always call deinit() for responses
const response = try client.someRequest();
defer response.deinit(); // This is also required!
```

### Timeouts and Retries

```zig
// Simple retry logic
var attempts: u8 = 0;
const max_attempts = 3;

while (attempts < max_attempts) {
    const result = http_client.get("https://api.example.com");
    if (result) |response| {
        defer response.deinit();
        if (response.status_code == 200) {
            // Success!
            break;
        }
    } else |err| {
        attempts += 1;
        if (attempts >= max_attempts) return err;
        
        // Wait before retry
        std.time.sleep(1000000000); // 1 second
    }
}
```

## 📚 Next Steps

- [HTTP Guide](./http-guide.md) - Deep dive into HTTP client usage
- [DNS Guide](./dns-guide.md) - Advanced DNS resolution techniques  
- [SMTP Guide](./smtp-guide.md) - Complete email sending guide
- [FTP Guide](./ftp-guide.md) - File transfer operations
- [API Reference](../api/) - Complete API documentation
- [Examples](../examples/) - More comprehensive examples

## ❓ Getting Help

- Check the [API documentation](../api/) for detailed function references
- Browse [examples](../examples/) for common use cases
- Read [error handling guide](./error-handling.md) for troubleshooting
- Open an issue on [GitHub](https://github.com/ghostkellz/zproto) for bugs or questions

## 🎉 Welcome to zproto!

You're now ready to start building network applications with Zig. The protocol suite is designed to be simple, efficient, and safe. Happy coding!