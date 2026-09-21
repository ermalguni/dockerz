const std = @import("std");
const Client = @import("../client.zig").Client;

pub const GetPingPath = "/_ping";

pub const PingError = error{
    UnexpectedHttpStatus,
    UnsupportedContentEncoding,
    InvalidPingResponse,
};

pub fn runPing(client: *Client) !void {
    var response = try client.request(.{
        .target = GetPingPath,
        .versioned = false,
        .max_body_bytes = 8 * 1024,
    });
    defer response.deinit();

    const body = try response.body() orelse return PingError.InvalidPingResponse;

    if (!std.mem.eql(u8, body, "OK")) {
        return PingError.InvalidPingResponse;
    }
}
