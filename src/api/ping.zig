const std = @import("std");

pub const GetPingPath = "/_ping";

pub const PingError = error{ UnexpectedHttpStatus, UnsupportedContentEncoding, InvalidPingResponse };

pub fn runPing(http_client: *std.http.Client, connection: *std.http.Client.Connection, uri: std.Uri) !void {
    var request = blk: {
        errdefer http_client.connection_pool.release(connection, http_client.io);

        break :blk try http_client.request(.GET, uri, .{ .connection = connection, .redirect_behavior = .unhandled, .headers = .{ .accept_encoding = .{ .override = "identity" } } });
    };
    defer request.deinit();

    try request.sendBodiless();
    var response = try request.receiveHead(&.{});

    const status = response.head.status;
    const encoding = response.head.content_encoding;

    var transfer_buffer: [64]u8 = undefined;
    const body = response.reader(&transfer_buffer);

    if (status != .ok) {
        return PingError.UnexpectedHttpStatus;
    }

    if (encoding != .identity) {
        return PingError.UnsupportedContentEncoding;
    }

    var bytes: [3]u8 = undefined;

    const len = body.readSliceShort(&bytes) catch |err| {
        return err;
    };

    if (!std.mem.eql(u8, bytes[0..len], "OK")) {
        return PingError.InvalidPingResponse;
    }
}
