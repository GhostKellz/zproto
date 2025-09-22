# Contributing to zproto

Thank you for your interest in contributing to zproto! This document provides guidelines and information for contributors.

## 🎯 Getting Started

### Prerequisites

- **Zig 0.16.0-dev.164+** or later
- Basic understanding of network protocols
- Familiarity with Zig programming language

### Development Setup

1. **Fork and Clone**
   ```bash
   git clone https://github.com/YOUR-USERNAME/zproto.git
   cd zproto
   ```

2. **Build and Test**
   ```bash
   zig build
   zig build test
   zig build test-runner
   ```

3. **Run Examples**
   ```bash
   zig build run
   zig build http-example
   zig build dns-example
   ```

## 🏗️ Project Structure

```
zproto/
├── src/
│   ├── common/           # Shared utilities
│   │   ├── auth.zig     # Authentication helpers
│   │   ├── parser.zig   # Protocol parsers
│   │   └── stream.zig   # Stream abstraction
│   ├── protocols/       # Protocol implementations
│   │   ├── http.zig     # HTTP/HTTPS client
│   │   ├── dns.zig      # DNS resolver
│   │   ├── ftp.zig      # FTP client
│   │   └── smtp.zig     # SMTP client
│   ├── main.zig         # Main demo program
│   └── root.zig         # Library exports
├── examples/            # Usage examples
├── tests/               # Test suite
├── assets/              # Images and resources
└── TODO.md              # Development roadmap
```

## 🔧 Adding New Protocols

### 1. Choose a Protocol

Check our [roadmap](TODO.md) for planned protocols or propose a new one by opening an issue.

### 2. Implementation Guidelines

#### File Structure
```zig
//! Protocol Name client/server implementation
const std = @import("std");
const common = @import("../common/common.zig");

pub const ProtocolError = error{
    // Protocol-specific errors
} || common.Error;

pub const ProtocolClient = struct {
    // Client implementation
};

pub const ProtocolServer = struct {
    // Server implementation (if applicable)
};

// Tests
test "protocol basic functionality" {
    // Unit tests
}
```

#### Required Components

1. **Error Types** - Define protocol-specific errors
2. **Client Implementation** - Core client functionality
3. **Server Implementation** - If the protocol supports servers
4. **Message Structures** - Protocol message formats
5. **Authentication** - If the protocol requires auth
6. **Tests** - Comprehensive unit tests

### 3. Implementation Checklist

- [ ] Protocol client with core functionality
- [ ] Error handling and proper error types
- [ ] Memory management (no leaks!)
- [ ] Documentation and comments
- [ ] Unit tests with good coverage
- [ ] Integration with common utilities
- [ ] Example program demonstrating usage
- [ ] Update `src/root.zig` to export new protocol
- [ ] Update README.md with protocol status

### 4. Code Style

#### General Guidelines
- Follow Zig's standard formatting (`zig fmt`)
- Use descriptive variable and function names
- Add comprehensive documentation comments
- Prefer explicit error handling over silent failures
- Use Zig's built-in testing framework

#### Naming Conventions
```zig
// Constants: UPPER_SNAKE_CASE
const DEFAULT_TIMEOUT = 5000;

// Types: PascalCase
pub const HttpClient = struct { ... };

// Functions and variables: camelCase
pub fn connectToServer() !void { ... }
const serverAddress = "127.0.0.1";

// Protocol-specific prefixes
const HttpError = error{ ... };
const FtpResponse = struct { ... };
```

#### Error Handling
```zig
// Always use explicit error handling
const result = risky_operation() catch |err| switch (err) {
    error.NetworkError => return ProtocolError.ConnectionFailed,
    error.ParseError => return ProtocolError.InvalidMessage,
    else => return err,
};

// Document possible errors
/// Connects to the server and performs authentication.
/// Returns ProtocolError.ConnectionFailed if unable to connect.
/// Returns ProtocolError.AuthenticationFailed if credentials are invalid.
pub fn connect(host: []const u8, port: u16) !void {
    // implementation
}
```

## 🧪 Testing Guidelines

### Unit Tests

Each protocol should have comprehensive unit tests:

```zig
test "protocol message parsing" {
    const allocator = std.testing.allocator;
    
    const message_data = "PROTOCOL_MESSAGE\r\n";
    const parsed = try ProtocolMessage.parse(allocator, message_data);
    defer parsed.deinit(allocator);
    
    try std.testing.expectEqualStrings("PROTOCOL_MESSAGE", parsed.content);
}

test "protocol error handling" {
    const allocator = std.testing.allocator;
    
    const invalid_data = "INVALID\r\n";
    const result = ProtocolMessage.parse(allocator, invalid_data);
    
    try std.testing.expectError(ProtocolError.InvalidMessage, result);
}
```

### Integration Tests

Add integration tests to `tests/test_runner.zig`:

```zig
fn testNewProtocol(allocator: std.mem.Allocator) !void {
    var client = zproto.new_protocol.Client.init(allocator);
    defer client.deinit();
    
    // Test basic functionality without requiring network
    // Mock responses, test parsing, etc.
}
```

### Example Programs

Create a complete example in `examples/new_protocol_example.zig`:

```zig
//! Example demonstrating New Protocol usage
const std = @import("std");
const zproto = @import("zproto");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Demonstrate protocol usage
    var client = zproto.new_protocol.Client.init(allocator);
    defer client.deinit();
    
    // Show realistic usage patterns
    std.debug.print("New Protocol Example\n", .{});
    
    // Note: Add connection details for users to customize
}
```

## 📝 Documentation

### Code Documentation

- Use `///` for public API documentation
- Use `//!` for file-level documentation
- Document all public functions, types, and constants
- Include examples in documentation when helpful

```zig
//! HTTP client implementation for zproto
//! 
//! This module provides a complete HTTP/1.1 client with support for:
//! - GET, POST, PUT, DELETE requests
//! - Custom headers and authentication
//! - TLS/HTTPS connections
//! - Connection pooling and reuse

/// HTTP client for making web requests.
/// 
/// Example usage:
/// ```zig
/// var client = HttpClient.init(allocator);
/// defer client.deinit();
/// 
/// const response = try client.get("https://api.example.com/data");
/// defer response.deinit();
/// ```
pub const HttpClient = struct {
    // ...
};
```

### README Updates

When adding protocols, update:
1. Protocol status in the main table
2. Examples section with new example
3. Build commands if needed
4. Feature list if adding new capabilities

## 🔍 Code Review Process

### Before Submitting

1. **Build and Test**
   ```bash
   zig build
   zig build test
   zig build test-runner
   ```

2. **Format Code**
   ```bash
   zig fmt src/ examples/ tests/
   ```

3. **Check for Memory Leaks**
   ```bash
   zig build run  # Should show no memory leaks
   ```

4. **Run Examples**
   ```bash
   zig build your-new-example
   ```

### Pull Request Guidelines

#### Title Format
- `feat: add MQTT client implementation`
- `fix: resolve memory leak in HTTP client`
- `docs: update README with new protocol status`
- `test: add comprehensive DNS client tests`

#### Description Template
```markdown
## What This PR Does
Brief description of changes

## Protocol Implemented
- [ ] Client implementation
- [ ] Server implementation (if applicable)
- [ ] Unit tests
- [ ] Integration tests
- [ ] Example program
- [ ] Documentation

## Testing
- [ ] All existing tests pass
- [ ] New tests added and passing
- [ ] No memory leaks detected
- [ ] Example programs work correctly

## Breaking Changes
List any breaking changes (hopefully none!)

## Additional Notes
Any other relevant information
```

### Review Criteria

Reviewers will check:
- ✅ Code follows project style guidelines
- ✅ Tests are comprehensive and pass
- ✅ No memory leaks or safety issues
- ✅ Documentation is clear and complete
- ✅ Integration with existing codebase is clean
- ✅ Performance is reasonable
- ✅ Error handling is appropriate

## 🐛 Reporting Issues

### Bug Reports

Use this template for bug reports:

```markdown
**Protocol**: Which protocol is affected?
**Zig Version**: Output of `zig version`
**OS**: Linux/macOS/Windows and version

**Description**
Clear description of the bug

**Steps to Reproduce**
1. Step one
2. Step two
3. Expected vs actual behavior

**Code Sample**
Minimal code that reproduces the issue

**Additional Context**
Error messages, logs, etc.
```

### Feature Requests

Use this template for feature requests:

```markdown
**Protocol**: Which protocol to add/enhance?
**Priority**: High/Medium/Low
**Use Case**: Why is this needed?

**Description**
Detailed description of the feature

**Examples**
How would this be used?

**Implementation Ideas**
Any thoughts on implementation approach?
```

## 💡 Getting Help

- 📖 **Documentation**: Check the README and code comments
- 🔍 **Search Issues**: Look for similar issues/questions
- 💬 **Discussions**: Use GitHub Discussions for questions
- 📧 **Contact**: Reach out to maintainers

## 🎉 Recognition

Contributors will be:
- Listed in the README acknowledgments
- Credited in release notes
- Invited to join the core team (for significant contributions)

---

Thank you for contributing to zproto! Together we're building the future of network programming in Zig. 🚀