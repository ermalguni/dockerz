const std = @import("std");
const Transport = @import("transport/transport.zig").Transport;
const TransportConfig = Transport.Config;

const http = std.http;

pub const ClientConfig = struct {
    transport: TransportConfig = .{ .unix = "/var/run/docker.sock" },
};

fn pingConnection(client: *http.Client, connection: *http.Client.Connection, uri: std.Uri) !void {
    var request = blk: {
        errdefer client.connection_pool.release(connection, client.io);

        break :blk try client.request(.GET, uri, .{ .connection = connection, .redirect_behavior = .unhandled, .headers = .{ .accept_encoding = .{ .override = "identity" } } });
    };
    defer request.deinit();

    try request.sendBodiless();
    var response = try request.receiveHead(&.{});

    const status = response.head.status;
    const encoding = response.head.content_encoding;

    var transfer_buffer: [64]u8 = undefined;
    const body = response.reader(&transfer_buffer);

    if (status != .ok) {
        return error.UnexpectedHttpStatus;
    }

    if (encoding != .identity) {
        return error.UnsupportedContentEncoding;
    }

    var bytes: [3]u8 = undefined;

    const len = body.readSliceShort(&bytes) catch |err| {
        return err;
    };

    if (!std.mem.eql(u8, bytes[0..len], "OK")) {
        return error.InvalidPingResponse;
    }
}

pub const Client = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    client: *http.Client,
    transport: Transport,
    base_url: []const u8,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, config: ClientConfig) !Client {
        var transport = try Transport.init(allocator, config.transport);
        errdefer transport.deinit(allocator);

        const base_url = switch (transport) {
            .unix => try allocator.dupe(u8, "http://localhost"),

            .tcp => |tcp| try std.fmt.allocPrint(allocator, "http://{s}:{d}", .{ tcp.host, tcp.port }),
        };
        errdefer allocator.free(base_url);

        const http_client = try allocator.create(http.Client);
        http_client.* = .{
            .allocator = allocator,
            .io = io,
        };
        errdefer http_client.deinit();

        const client = Client{
            .allocator = allocator,
            .io = io,
            .client = http_client,
            .transport = transport,
            .base_url = base_url,
        };

        return client;
    }

    // fn check_version(self: *Client) !bool {}

    fn do_request(self: *Client, method: http.Method, path: []const u8) ![]const u8 {
        const abs_url = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ self.base_url, path });
        defer self.allocator.destroy(abs_url);

        var body = std.ArrayList(u8).initCapacity(self.allocator, 512);
        errdefer body.deinit();

        const resp = try self.connection.client.fetch(.{
            .method = method,
            .location = .{ .url = self.base_url },
            .response_writer = body,
        });

        if (resp.status != .ok) {}

        return body.toOwnedSlice();
    }

    fn ping(self: *Client) !void {
        const url = try std.fmt.allocPrint(self.allocator, "{s}/_ping", .{self.base_url});
        defer self.allocator.free(url);

        const uri = try std.Uri.parse(url);

        const connection = try self.transport.connect(self.client);

        try pingConnection(self.client, connection, uri);
    }

    pub fn deinit(self: *Client) void {
        self.client.deinit();
        self.allocator.destroy(self.client);

        self.allocator.free(self.base_url);

        self.transport.deinit(self.allocator);

        self.* = undefined;
    }
};

fn servePing(io: std.Io, listener: *std.Io.net.Server, status: http.Status, body: []const u8) !void {
    const stream = try listener.accept(io);
    defer stream.close(io);

    var input: [4096]u8 = undefined;
    var output: [1024]u8 = undefined;

    var reader = stream.reader(io, &input);
    var writer = stream.writer(io, &output);

    var server = http.Server.init(&reader.interface, &writer.interface);

    var request = try server.receiveHead();

    try std.testing.expectEqual(http.Method.GET, request.head.method);

    try std.testing.expectEqual("/_ping", request.head.target);

    try request.respond(body, .{ .status = status, .keep_alive = false });
}

test "client ping HTTP over a tcp connection" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    const cases = [_]struct {
        status: http.Status,
        body: []const u8,
        expected: anyerror,
    }{ .{
        .status = .ok,
        .body = "OK",
        .expected = null,
    }, .{
        .status = .internal_server_error,
        .body = "error",
        .expected = error.UnexpectedHttpStatus,
    } };

    for (cases) |case| {
        const address = try std.Io.net.IpAddress.parse("127.0.0.1", 0);

        var listener = try address.listen(io, .{});
        defer listener.deinit(io);

        var server_task = try io.concurrent(servePing, .{ io, &listener, case.status, case.body });
        defer server_task.cancel(io) catch {};

        var client = try Client.init(allocator, io, .{ .transport = .{ .tcp = .{
            .host = "127.0.0.1",
            .port = listener.socket.address.getPort(),
        } } });
        defer client.deinit();

        const url = try std.fmt.allocPrint(allocator, "{s}/_ping}", .{client.base_url});
        defer allocator.free(url);

        const uri = try std.Uri.parse(url);

        const connection = try client.transport.connect();

        const result = pingConnection(client.client, connection, uri);

        try server_task.await(io);

        if (case.expected) |expected| {
            try std.testing.expectError(expected, result);
        } else {
            try result;
        }
    }
}

test "client initialization does not require a running daemon" {
    var client = try Client.init(std.testing.allocator, std.testing.io, .{ .transport = .{ .tcp = .{
        .host = "127.0.0.1",
        .port = 0,
    } } });
    defer client.deinit();
}
