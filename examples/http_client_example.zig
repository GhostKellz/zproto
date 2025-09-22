//! Example demonstrating HTTP client usage
const std = @import("std");
const zproto = @import("zproto");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create HTTP client
    var client = zproto.http.HttpClient.init(allocator);
    defer client.deinit();

    std.debug.print("Making HTTP GET request to httpbin.org...\n", .{});

    // Make a GET request
    const response = client.get("http://httpbin.org/get") catch |err| {
        std.debug.print("Error making request: {}\n", .{err});
        return;
    };
    defer response.deinit();

    std.debug.print("Response Status: {} {s}\n", .{ response.status.code, response.status.phrase });

    if (response.body) |body| {
        std.debug.print("Response Body: {s}\n", .{body});
    }

    // Example POST request with JSON body
    std.debug.print("\nMaking HTTP POST request...\n", .{});

    const json_body =
        \\{
        \\  "name": "zproto",
        \\  "version": "0.1.0",
        \\  "description": "Zig protocol suite"
        \\}
    ;

    const post_response = client.post("http://httpbin.org/post", json_body) catch |err| {
        std.debug.print("Error making POST request: {}\n", .{err});
        return;
    };
    defer post_response.deinit();

    std.debug.print("POST Response Status: {} {s}\n", .{ post_response.status.code, post_response.status.phrase });
}
