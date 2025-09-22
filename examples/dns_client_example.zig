//! Example demonstrating DNS client usage
const std = @import("std");
const zproto = @import("zproto");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create DNS client with default servers (Google DNS, Cloudflare DNS)
    var client = zproto.dns.DnsClient.initWithDefaultServers(allocator) catch |err| {
        std.debug.print("Error creating DNS client: {}\n", .{err});
        return;
    };
    defer client.deinit();

    const domains = [_][]const u8{
        "google.com",
        "github.com",
        "stackoverflow.com",
        "zig.guide",
    };

    for (domains) |domain| {
        std.debug.print("\nResolving {s}...\n", .{domain});

        // Resolve A records (IPv4)
        const a_records = client.resolveA(domain) catch |err| {
            std.debug.print("  Error resolving A records: {}\n", .{err});
            continue;
        };
        defer allocator.free(a_records);

        std.debug.print("  A records ({} found):\n", .{a_records.len});
        for (a_records) |addr| {
            var buf: [64]u8 = undefined;
            const ip_str = std.fmt.bufPrint(buf[0..], "{}", .{addr}) catch "invalid";
            std.debug.print("    {s}\n", .{ip_str});
        }

        // Try to resolve AAAA records (IPv6)
        const aaaa_records = client.resolveAAAA(domain) catch |err| {
            std.debug.print("  No AAAA records or error: {}\n", .{err});
            continue;
        };
        defer allocator.free(aaaa_records);

        std.debug.print("  AAAA records ({} found):\n", .{aaaa_records.len});
        for (aaaa_records) |addr| {
            var buf: [64]u8 = undefined;
            const ip_str = std.fmt.bufPrint(buf[0..], "{}", .{addr}) catch "invalid";
            std.debug.print("    {s}\n", .{ip_str});
        }
    }
}
