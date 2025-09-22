//! DNS client implementation
const std = @import("std");
const net = std.net;
const common = @import("../common/common.zig");
const Stream = common.Stream;
const Parser = common.Parser;

pub const DnsError = error{
    InvalidDomain,
    InvalidResponse,
    QueryTimeout,
    ServerError,
    NameNotFound,
} || common.Error;

pub const DnsRecordType = enum(u16) {
    A = 1,
    NS = 2,
    CNAME = 5,
    SOA = 6,
    PTR = 12,
    MX = 15,
    TXT = 16,
    AAAA = 28,

    pub fn toString(self: DnsRecordType) []const u8 {
        return switch (self) {
            .A => "A",
            .NS => "NS",
            .CNAME => "CNAME",
            .SOA => "SOA",
            .PTR => "PTR",
            .MX => "MX",
            .TXT => "TXT",
            .AAAA => "AAAA",
        };
    }
};

pub const DnsClass = enum(u16) {
    IN = 1, // Internet
    CS = 2, // CSNET
    CH = 3, // CHAOS
    HS = 4, // Hesiod
};

pub const DnsOpcode = enum(u4) {
    QUERY = 0,
    IQUERY = 1,
    STATUS = 2,
};

pub const DnsResponseCode = enum(u4) {
    NOERROR = 0,
    FORMERR = 1,
    SERVFAIL = 2,
    NXDOMAIN = 3,
    NOTIMP = 4,
    REFUSED = 5,
};

pub const DnsHeader = struct {
    id: u16,
    qr: bool, // Query/Response flag
    opcode: DnsOpcode,
    aa: bool, // Authoritative Answer
    tc: bool, // Truncated
    rd: bool, // Recursion Desired
    ra: bool, // Recursion Available
    z: u3, // Reserved
    rcode: DnsResponseCode,
    qdcount: u16, // Question count
    ancount: u16, // Answer count
    nscount: u16, // Authority count
    arcount: u16, // Additional count

    pub fn encode(self: DnsHeader, writer: anytype) !void {
        try writer.writeInt(u16, self.id, .big);

        var flags: u16 = 0;
        if (self.qr) flags |= 0x8000;
        flags |= (@as(u16, @intFromEnum(self.opcode)) << 11);
        if (self.aa) flags |= 0x0400;
        if (self.tc) flags |= 0x0200;
        if (self.rd) flags |= 0x0100;
        if (self.ra) flags |= 0x0080;
        flags |= (@as(u16, self.z) << 4);
        flags |= @intFromEnum(self.rcode);

        try writer.writeInt(u16, flags, .big);
        try writer.writeInt(u16, self.qdcount, .big);
        try writer.writeInt(u16, self.ancount, .big);
        try writer.writeInt(u16, self.nscount, .big);
        try writer.writeInt(u16, self.arcount, .big);
    }

    pub fn decode(reader: anytype) !DnsHeader {
        const id = try reader.readInt(u16, .big);
        const flags = try reader.readInt(u16, .big);

        return DnsHeader{
            .id = id,
            .qr = (flags & 0x8000) != 0,
            .opcode = @enumFromInt((flags >> 11) & 0x0F),
            .aa = (flags & 0x0400) != 0,
            .tc = (flags & 0x0200) != 0,
            .rd = (flags & 0x0100) != 0,
            .ra = (flags & 0x0080) != 0,
            .z = @truncate((flags >> 4) & 0x07),
            .rcode = @enumFromInt(flags & 0x0F),
            .qdcount = try reader.readInt(u16, .big),
            .ancount = try reader.readInt(u16, .big),
            .nscount = try reader.readInt(u16, .big),
            .arcount = try reader.readInt(u16, .big),
        };
    }
};

pub const DnsQuestion = struct {
    name: []const u8,
    record_type: DnsRecordType,
    class: DnsClass,

    pub fn encode(self: DnsQuestion, allocator: std.mem.Allocator, writer: anytype) !void {
        try encodeDomainName(allocator, self.name, writer);
        try writer.writeInt(u16, @intFromEnum(self.record_type), .big);
        try writer.writeInt(u16, @intFromEnum(self.class), .big);
    }
};

pub const DnsRecord = struct {
    name: []const u8,
    record_type: DnsRecordType,
    class: DnsClass,
    ttl: u32,
    data: []const u8,

    pub fn decode(allocator: std.mem.Allocator, reader: anytype, packet: []const u8) !DnsRecord {
        const name = try decodeDomainName(allocator, reader, packet);
        const record_type = @as(DnsRecordType, @enumFromInt(try reader.readInt(u16, .big)));
        const class = @as(DnsClass, @enumFromInt(try reader.readInt(u16, .big)));
        const ttl = try reader.readInt(u32, .big);
        const data_length = try reader.readInt(u16, .big);

        const data = try allocator.alloc(u8, data_length);
        _ = try reader.readAll(data);

        return DnsRecord{
            .name = name,
            .record_type = record_type,
            .class = class,
            .ttl = ttl,
            .data = data,
        };
    }

    pub fn getIpv4Address(self: DnsRecord) ?net.Address {
        if (self.record_type != .A or self.data.len != 4) return null;
        return net.Address.initIp4(self.data, 0);
    }

    pub fn getIpv6Address(self: DnsRecord) ?net.Address {
        if (self.record_type != .AAAA or self.data.len != 16) return null;
        return net.Address.initIp6(self.data, 0, 0, 0);
    }

    pub fn getCname(self: DnsRecord, allocator: std.mem.Allocator, packet: []const u8) !?[]const u8 {
        if (self.record_type != .CNAME) return null;

        var stream = std.io.fixedBufferStream(self.data);
        const reader = stream.reader();
        return decodeDomainName(allocator, reader, packet);
    }
};

pub const DnsResponse = struct {
    const Self = @This();

    header: DnsHeader,
    questions: []DnsQuestion,
    answers: []DnsRecord,
    authority: []DnsRecord,
    additional: []DnsRecord,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *Self) void {
        for (self.questions) |question| {
            self.allocator.free(question.name);
        }
        self.allocator.free(self.questions);

        for (self.answers) |answer| {
            self.allocator.free(answer.name);
            self.allocator.free(answer.data);
        }
        self.allocator.free(self.answers);

        for (self.authority) |auth| {
            self.allocator.free(auth.name);
            self.allocator.free(auth.data);
        }
        self.allocator.free(self.authority);

        for (self.additional) |add| {
            self.allocator.free(add.name);
            self.allocator.free(add.data);
        }
        self.allocator.free(self.additional);
    }

    pub fn decode(allocator: std.mem.Allocator, packet: []const u8) !Self {
        var stream = std.io.fixedBufferStream(packet);
        const reader = stream.reader();

        const header = try DnsHeader.decode(reader);

        // Read questions
        const questions = try allocator.alloc(DnsQuestion, header.qdcount);
        for (questions) |*question| {
            const name = try decodeDomainName(allocator, reader, packet);
            const record_type = @as(DnsRecordType, @enumFromInt(try reader.readInt(u16, .big)));
            const class = @as(DnsClass, @enumFromInt(try reader.readInt(u16, .big)));

            question.* = DnsQuestion{
                .name = name,
                .record_type = record_type,
                .class = class,
            };
        }

        // Read answers
        const answers = try allocator.alloc(DnsRecord, header.ancount);
        for (answers) |*answer| {
            answer.* = try DnsRecord.decode(allocator, reader, packet);
        }

        // Read authority records
        const authority = try allocator.alloc(DnsRecord, header.nscount);
        for (authority) |*auth| {
            auth.* = try DnsRecord.decode(allocator, reader, packet);
        }

        // Read additional records
        const additional = try allocator.alloc(DnsRecord, header.arcount);
        for (additional) |*add| {
            add.* = try DnsRecord.decode(allocator, reader, packet);
        }

        return Self{
            .header = header,
            .questions = questions,
            .answers = answers,
            .authority = authority,
            .additional = additional,
            .allocator = allocator,
        };
    }
};

pub const DnsClient = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    servers: []const net.Address,
    timeout_ms: u32,

    pub fn init(allocator: std.mem.Allocator, servers: []const net.Address) Self {
        return Self{
            .allocator = allocator,
            .servers = servers,
            .timeout_ms = 5000, // 5 seconds default
        };
    }

    pub fn initWithDefaultServers(allocator: std.mem.Allocator) !Self {
        const servers = try allocator.alloc(net.Address, 2);
        servers[0] = try net.Address.parseIp4("8.8.8.8", 53); // Google DNS
        servers[1] = try net.Address.parseIp4("1.1.1.1", 53); // Cloudflare DNS

        return Self{
            .allocator = allocator,
            .servers = servers,
            .timeout_ms = 5000,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.servers);
    }

    pub fn resolve(self: *Self, domain: []const u8, record_type: DnsRecordType) !DnsResponse {
        for (self.servers) |server| {
            return self.queryServer(server, domain, record_type) catch |err| switch (err) {
                DnsError.QueryTimeout, DnsError.ServerError => continue,
                else => return err,
            };
        }
        return DnsError.QueryTimeout;
    }

    pub fn resolveA(self: *Self, domain: []const u8) ![]net.Address {
        const response = try self.resolve(domain, .A);
        defer response.deinit();

        var addresses = std.ArrayList(net.Address).init(self.allocator);

        for (response.answers) |answer| {
            if (answer.getIpv4Address()) |addr| {
                try addresses.append(addr);
            }
        }

        return addresses.toOwnedSlice();
    }

    pub fn resolveAAAA(self: *Self, domain: []const u8) ![]net.Address {
        const response = try self.resolve(domain, .AAAA);
        defer response.deinit();

        var addresses = std.ArrayList(net.Address).init(self.allocator);

        for (response.answers) |answer| {
            if (answer.getIpv6Address()) |addr| {
                try addresses.append(addr);
            }
        }

        return addresses.toOwnedSlice();
    }

    fn queryServer(self: *Self, server: net.Address, domain: []const u8, record_type: DnsRecordType) !DnsResponse {
        const socket = try std.posix.socket(std.posix.AF.INET, std.posix.SOCK.DGRAM, 0);
        defer std.posix.close(socket);

        // Create query packet
        const query_packet = try self.createQuery(domain, record_type);
        defer self.allocator.free(query_packet);

        // Send query
        const server_addr = @as(*const std.posix.sockaddr, @ptrCast(&server.any));
        const bytes_sent = try std.posix.sendto(socket, query_packet, 0, server_addr, server.getOsSockLen());
        if (bytes_sent != query_packet.len) return DnsError.ServerError;

        // Receive response
        var response_buffer: [512]u8 = undefined;
        const bytes_received = try std.posix.recv(socket, &response_buffer, 0);

        return DnsResponse.decode(self.allocator, response_buffer[0..bytes_received]);
    }

    fn createQuery(self: *Self, domain: []const u8, record_type: DnsRecordType) ![]u8 {
        var packet = std.ArrayList(u8).init(self.allocator);
        defer packet.deinit();

        const writer = packet.writer();

        // Create header
        const header = DnsHeader{
            .id = @truncate(std.crypto.random.int(u16)),
            .qr = false,
            .opcode = .QUERY,
            .aa = false,
            .tc = false,
            .rd = true,
            .ra = false,
            .z = 0,
            .rcode = .NOERROR,
            .qdcount = 1,
            .ancount = 0,
            .nscount = 0,
            .arcount = 0,
        };

        try header.encode(writer);

        // Create question
        const question = DnsQuestion{
            .name = domain,
            .record_type = record_type,
            .class = .IN,
        };

        try question.encode(self.allocator, writer);

        return packet.toOwnedSlice();
    }
};

// Helper functions for domain name encoding/decoding
fn encodeDomainName(allocator: std.mem.Allocator, domain: []const u8, writer: anytype) !void {
    _ = allocator;
    var it = std.mem.splitScalar(u8, domain, '.');

    while (it.next()) |label| {
        if (label.len > 63) return DnsError.InvalidDomain;
        try writer.writeByte(@truncate(label.len));
        try writer.writeAll(label);
    }

    try writer.writeByte(0); // Null terminator
}

fn decodeDomainName(allocator: std.mem.Allocator, reader: anytype, packet: []const u8) ![]const u8 {
    var labels = std.ArrayList([]const u8).init(allocator);
    defer labels.deinit();

    while (true) {
        const length = try reader.readByte();

        if (length == 0) {
            break;
        } else if ((length & 0xC0) == 0xC0) {
            // Compression pointer
            const pointer = (@as(u16, length & 0x3F) << 8) | try reader.readByte();
            var sub_stream = std.io.fixedBufferStream(packet[pointer..]);
            const sub_reader = sub_stream.reader();
            const compressed_name = try decodeDomainName(allocator, sub_reader, packet);
            try labels.append(compressed_name);
            break;
        } else {
            // Regular label
            const label = try allocator.alloc(u8, length);
            _ = try reader.readAll(label);
            try labels.append(label);
        }
    }

    return std.mem.join(allocator, ".", labels.items);
}

test "dns header encoding/decoding" {
    const header = DnsHeader{
        .id = 0x1234,
        .qr = false,
        .opcode = .QUERY,
        .aa = false,
        .tc = false,
        .rd = true,
        .ra = false,
        .z = 0,
        .rcode = .NOERROR,
        .qdcount = 1,
        .ancount = 0,
        .nscount = 0,
        .arcount = 0,
    };

    var buffer: [12]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);

    try header.encode(stream.writer());

    stream.pos = 0;
    const decoded = try DnsHeader.decode(stream.reader());

    try std.testing.expect(decoded.id == 0x1234);
    try std.testing.expect(decoded.rd == true);
    try std.testing.expect(decoded.qdcount == 1);
}
