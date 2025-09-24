<div align="center">
  <img src="assets/icons/zproto.png" alt="zproto Logo" width="200"/>
  
  # 🌐 zproto
  
  **A unified Zig-native library for application-layer protocols**
  
  [![Zig](https://img.shields.io/badge/Zig-0.16.0--dev-orange?style=for-the-badge&logo=zig)](https://ziglang.org/)
  [![Powered by Zig](https://img.shields.io/badge/Powered%20by-Zig-blue?style=for-the-badge&logo=zig&logoColor=yellow)](https://ziglang.org/)
  [![Protocol Suite](https://img.shields.io/badge/Protocol-Suite-green?style=for-the-badge)](https://github.com/ghostkellz/zproto)
  [![Memory Safe](https://img.shields.io/badge/Memory-Safe-purple?style=for-the-badge)](https://ziglang.org/)

  
  *Replace multiple C libraries with a single, fast, memory-safe Zig implementation*
</div>

---

## 🚀 Overview

**zproto** is a comprehensive protocol suite written entirely in Zig, designed to replace common C libraries like libcurl, OpenLDAP, mosquitto, and libtorrent. Built from the ground up with Zig's philosophy of performance, safety, and simplicity.

### ✨ Key Features

- 🔥 **Zero Dependencies** - Pure Zig implementation, no external libraries
- 🛡️ **Memory Safe** - Leverages Zig's compile-time safety guarantees
- ⚡ **High Performance** - Optimized for speed with minimal allocations
- 🌍 **Cross Platform** - Works on Linux, macOS, and Windows
- 🧩 **Modular Design** - Use only the protocols you need
- 🔧 **Developer Friendly** - Clean APIs with comprehensive examples

## ⚠️ DISCLAIMER

⚠️ **EXPERIMENTAL LIBRARY - FOR LAB/PERSONAL USE** ⚠️
This is an experimental library under active development. It is
intended for research, learning, and personal projects. The API is subject
to change!

---

## 📡 Supported Protocols

### ✅ **Core Web & Internet**
- **HTTP/HTTPS** - Web client with TLS support, HTTP/1.1 and HTTP/2 ready
- **DNS** - Fast domain name resolution with A/AAAA/CNAME/MX/TXT records

### ✅ **File Transfer & Communication** 
- **FTP/SFTP** - File transfer with authentication and passive/active modes
- **SMTP/IMAP/POP3** - Complete email stack with MIME support

### 🚧 **Directory & Network Services** *(Coming Soon)*
- **LDAP** - Directory services with TLS/StartTLS
- **DHCP** - Network configuration client/server
- **NTP** - Time synchronization with drift correction

### 🚧 **Monitoring & Management** *(Coming Soon)*
- **SNMP** - Network monitoring with v1/v2c/v3 support
- **Syslog** - System logging with RFC 3164/5424 compliance

### 🚧 **Real-time & Messaging** *(Coming Soon)*
- **MQTT** - IoT messaging with v3.1.1 & v5.0 support
- **IRC** - Chat protocol with channels and CTCP
- **SIP/RTP** - VoIP and real-time media transport

### 🚧 **P2P & Specialized** *(Coming Soon)*
- **BitTorrent** - Peer-to-peer file sharing with DHT
- **RADIUS** - Network authentication and accounting

### 🚧 **Industrial & IoT** *(Coming Soon)*
- **Modbus** - Industrial protocol for SCADA systems

---

## 🛠️ Shared Utilities

- **Stream Abstraction** - Unified TCP/TLS interface
- **Protocol Parsers** - Line-based, binary, and ASN.1 support
- **Authentication** - BASIC, DIGEST, OAuth2, and more
- **Connection Pooling** - Efficient connection reuse
- **Rate Limiting** - Built-in throttling and backoff
- **Configuration Management** - Unified config system

---

## 🎯 Quick Start

### Installation

Add zproto to your `build.zig.zon`:

```bash
zig fetch --save https://github.com/ghostkellz/zproto/archive/main.tar.gz
```
Alternatively: 
```zig
.dependencies = .{
    .zproto = .{
        .url = "https://github.com/ghostkellz/zproto/archive/main.tar.gz",
        .hash = "...", // zig will fill this in
    },
},
```

### Basic Usage

```zig
const std = @import("std");
const zproto = @import("zproto");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // HTTP Client
    var http_client = zproto.http.HttpClient.init(allocator);
    defer http_client.deinit();
    
    const response = try http_client.get("https://api.github.com/users/ghostkellz");
    defer response.deinit();
    
    // DNS Resolution
    var dns_client = try zproto.dns.DnsClient.initWithDefaultServers(allocator);
    defer dns_client.deinit();
    
    const addresses = try dns_client.resolveA("github.com");
    defer allocator.free(addresses);
    
    // SMTP Email
    var smtp_client = zproto.smtp.SmtpClient.init(allocator);
    defer smtp_client.deinit();
    
    // Send email (see examples for full implementation)
}
```

---

## 📚 Examples

Comprehensive examples are available in the [`examples/`](examples/) directory:

- [`http_client_example.zig`](examples/http_client_example.zig) - HTTP requests and responses
- [`dns_client_example.zig`](examples/dns_client_example.zig) - Domain name resolution
- [`smtp_client_example.zig`](examples/smtp_client_example.zig) - Sending emails
- More examples coming with each protocol implementation!

### Running Examples

```bash
# Run HTTP client example
zig build http-example

# Run DNS resolution example  
zig build dns-example

# Run SMTP client example
zig build smtp-example
```

---

## 🧪 Testing

Run the comprehensive test suite:

```bash
# Run all tests
zig build test

# Run custom test runner
zig build test-runner

# Run main demo
zig build run
```

---

## 🗺️ Roadmap

| Milestone | Protocols | Status |
|-----------|-----------|--------|
| **M1** | HTTP/HTTPS + DNS | ✅ **Complete** |
| **M2** | FTP + SMTP/IMAP/POP3 | ✅ **Complete** |
| **M3** | MQTT + IRC | 🚧 **In Progress** |
| **M4** | LDAP + SNMP + Syslog | 📋 **Planned** |
| **M5** | SIP/RTP + BitTorrent | 📋 **Planned** |
| **M6** | DHCP + NTP + RADIUS | 📋 **Planned** |
| **M7** | Modbus + Industrial | 📋 **Planned** |
| **M8** | Production Ready | 📋 **Planned** |

---

## 🏗️ Building

```bash
# Clone the repository
git clone https://github.com/ghostkellz/zproto.git
cd zproto

# Build the library
zig build

# Run the demo
zig build run

# Build and run tests
zig build test
```

### Requirements

- **Zig 0.16.0-dev.164+** or later
- No external dependencies required!

---

## 🤝 Contributing

We welcome contributions! Please see our [contribution guidelines](CONTRIBUTING.md) for details.

### Development Setup

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/amazing-protocol`
3. Make your changes and add tests
4. Ensure all tests pass: `zig build test`
5. Submit a pull request

### Adding New Protocols

1. Create protocol implementation in `src/protocols/`
2. Add to `src/root.zig` exports
3. Create example in `examples/`
4. Add tests in `tests/`
5. Update documentation

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## 🌟 Acknowledgments

- **Zig Language** - For making systems programming fun again
- **Protocol Specifications** - RFCs and standards that make the internet work
- **Open Source Community** - For inspiration and feedback

---

## 📞 Support & Community

- 🐛 **Issues**: [GitHub Issues](https://github.com/ghostkellz/zproto/issues)
- 💬 **Discussions**: [GitHub Discussions](https://github.com/ghostkellz/zproto/discussions)
- 📧 **Email**: zproto@example.com

---

<div align="center">
  
  **Built with ❤️ and ⚡ by the Zig community**
  
  [![Star this repo](https://img.shields.io/github/stars/ghostkellz/zproto?style=social)](https://github.com/ghostkellz/zproto)
  
</div>
