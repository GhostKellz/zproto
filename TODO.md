# TODO — zproto (Protocol Suite)

A unified Zig-native library for application-layer protocols.  
C Libraries Replaced: libcurl (protocol bits), OpenLDAP, mosquitto, libtorrent, etc.

---

## ✅ Core Goals
- Provide **client + server implementations** for common network protocols
- No dependency on ghostnet (works over `std.net` sockets)
- Modular: each protocol is self-contained but shares core utilities

---

## 🛠️ Protocol Targets (MVP Set)

### Core Web & Internet
- [x] **HTTP/HTTPS** ✅ COMPLETED
  - [x] Client implementation
  - [x] HTTP/1.1 support
  - [x] TLS integration, certificate validation
  - [x] Common methods (GET, POST, PUT, DELETE)

- [x] **DNS** ✅ COMPLETED
  - [x] Recursive resolver client
  - [x] A/AAAA/CNAME/MX/TXT records
  - [x] Basic query and response parsing

### File Transfer & Communication
- [x] **FTP** ✅ COMPLETED
  - [x] Client implementation
  - [x] Authentication, file transfer
  - [x] Passive & active modes

- [x] **SMTP/IMAP/POP3** ✅ COMPLETED
  - [x] Enhanced SMTP/SMTPS client with TLS support
  - [x] Complete IMAP4rev1 client with mailbox management
  - [x] Full POP3/POP3S client with STARTTLS
  - [x] Authentication (LOGIN, PLAIN, XOAUTH2)
  - [x] MIME parsing and generation
  - [x] Comprehensive examples and documentation
  - [x] Zig 0.16 compatibility fixes

### Directory & Network Services
- [ ] **LDAP**
  - Bind/search/add/modify/delete operations
  - Schema + directory query support
  - TLS/StartTLS integration

- [ ] **DHCP**
  - Client implementation
  - Basic server with lease management
  - Option parsing (DNS, gateway, etc.)

- [ ] **NTP**
  - Client for time synchronization
  - SNTP simple implementation
  - Offset calculation & drift correction

### Monitoring & Management
- [ ] **SNMP**
  - v1/v2c basic GET/SET/Trap
  - v3 authentication + privacy
  - MIB parsing support

- [ ] **Syslog**
  - RFC 3164/5424 support
  - UDP/TCP/TLS transport
  - Structured data parsing

### Real-time & Messaging
- [ ] **SIP/RTP**
  - Session initiation + teardown
  - SDP parsing
  - Real-time media transport

- [ ] **MQTT**
  - v3.1.1 & v5.0 support
  - QoS 0/1/2
  - Broker + client
  - Retained messages, wildcards

- [ ] **IRC**
  - Client + minimal server
  - Channels, nick registration
  - Basic commands + CTCP

### P2P & Specialized
- [ ] **BitTorrent**
  - Peer wire protocol
  - DHT + magnet links
  - Piece verification

- [ ] **RADIUS**
  - Authentication, authorization, accounting
  - PAP/CHAP/EAP support
  - Client + basic server

### Industrial & IoT
- [ ] **Modbus**
  - TCP & RTU variants
  - Function codes 1-6, 15-16
  - Client + server implementation

---

## � Current Project Status (Updated)

### ✅ COMPLETED PHASES
**Phase 1: Foundation & Basic Protocols**
- HTTP/HTTPS client implementation ✅
- DNS resolution client ✅  
- FTP client implementation ✅
- Basic SMTP client ✅
- Shared utilities (stream abstraction, parsers, auth, etc.) ✅

**Phase 2: Email Stack** 
- Enhanced SMTP/SMTPS client with TLS support and advanced authentication ✅
- IMAP client for mailbox access and message management ✅
- POP3 client for simple email retrieval ✅
- Email parsing utilities for MIME messages and attachments ✅
- Comprehensive examples and documentation ✅
- Zig 0.16 compatibility fixes (ArrayList, print formatting, split functions) ✅

### 🚀 NEXT UP: Real-time & Messaging Protocols
- WebSocket client/server implementation
- MQTT client for IoT messaging  
- Socket.IO client implementation
- Server-Sent Events (SSE) support

### Recent Achievements
- All email protocols successfully adapted for Zig 0.16.0-dev.164
- SMTP enhanced example now runs with full SMTPS/STARTTLS support
- Complete IMAP4rev1 implementation with mailbox operations
- POP3/POP3S client with unique ID support and STARTTLS
- MIME email parsing with multipart content and attachment handling
- Unified error handling and authentication patterns across all protocols

---

## �🔧 Shared Utilities
- [ ] Common **framing/parsing** helpers (line-based, binary, ASN.1 BER/DER, etc.)
- [ ] Core **auth/credentials** helpers (reuse zcrypto if available, else std.crypto)
- [ ] Unified **async stream abstraction** for all protocols
- [ ] **Connection pooling** - Reusable connection management across protocols
- [ ] **Rate limiting** - Built-in rate limiting for client implementations
- [ ] **Retry/backoff logic** - Exponential backoff, circuit breaker patterns
- [ ] **Protocol detection** - Auto-detect protocol from raw bytes
- [ ] **Metrics/telemetry** - Built-in observability hooks
- [ ] **Configuration management** - Unified config format for all protocols
- [ ] **Test harness** with protocol simulators (mock servers/clients)

---

## 📅 Roadmap
1. **Milestone 1:** HTTP/HTTPS + DNS (web foundation + name resolution)
2. **Milestone 2:** FTP + SMTP/IMAP/POP3 (dev tools + email stack)  
3. **Milestone 3:** MQTT + IRC (lightweight messaging)  
4. **Milestone 4:** LDAP + SNMP + Syslog (enterprise/infra protocols)  
5. **Milestone 5:** SIP/RTP + BitTorrent (realtime + P2P heavy hitters)
6. **Milestone 6:** DHCP + NTP + RADIUS (network services)
7. **Milestone 7:** Modbus (industrial/IoT protocols)
8. **Milestone 8:** Harden, fuzz-test, and package release

---

## 🚨 Success Criteria
- Compile cleanly on **Linux/macOS/Windows** with Zig std
- Achieve **interoperability** with existing reference servers
- Pass **fuzzing + conformance tests** for each protocol
- Provide **examples** for each client/server in `/examples`

---

## 🌐 Soonish Extensions
- WebSocket (real-time web communication)
- STUN/TURN (NAT traversal for P2P)
- BGP (routing protocol - advanced)
- WebDAV (file sync over HTTP)

## 🌐 Future Extensions
- CoAP (IoT)
- XMPP (chat/messaging)
- NNTP (Usenet)



