# API Reference

Complete API documentation for all zproto protocols and utilities.

## Protocol Clients

### [HTTP Client](./http.md)
```zig
const HttpClient = @import("zproto").http.HttpClient;
var client = HttpClient.init(allocator);
defer client.deinit();
```

### [DNS Client](./dns.md)
```zig
const DnsClient = @import("zproto").dns.DnsClient;
var client = try DnsClient.initWithDefaultServers(allocator);
defer client.deinit();
```

### [FTP Client](./ftp.md)
```zig
const FtpClient = @import("zproto").ftp.FtpClient;
var client = FtpClient.init(allocator);
defer client.deinit();
```

### [SMTP Client](./smtp.md)
```zig
const SmtpClient = @import("zproto").smtp.SmtpClient;
var client = SmtpClient.init(allocator);
defer client.deinit();
```

## Common Utilities

### [Stream Abstraction](./common.md#stream)
Unified TCP/TLS stream interface for all protocols.

### [Protocol Parsers](./common.md#parsers)
Line-based and binary protocol parsing utilities.

### [Authentication](./common.md#auth)
Common authentication helpers for various protocols.

### [Connection Pooling](./common.md#connection-pool)
Efficient connection management and reuse.

### [Rate Limiting](./common.md#rate-limiter)
Request rate limiting and throttling.

## Error Types

All zproto functions return Zig errors. Common error types:

```zig
const ZprotoError = error{
    NetworkError,
    ParseError,
    AuthenticationError,
    TimeoutError,
    InvalidResponse,
    OutOfMemory,
};
```

## Memory Management

All zproto clients follow the same pattern:
1. Initialize with an allocator
2. Use the client for operations
3. Call `deinit()` to clean up resources

```zig
var client = SomeClient.init(allocator);
defer client.deinit(); // Always call deinit!

// Use client...
const result = try client.someOperation();
```

## Thread Safety

⚠️ **Important:** zproto clients are **not thread-safe**. Each thread should have its own client instance or use external synchronization.