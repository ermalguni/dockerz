const std = @import("std");
const Transport = @import("transport/transport.zig").Transport;
const TransportConfig = Transport.Config;

const models = @import("generated/models.zig");
const version_api = @import("api/version.zig");

const Version = version_api.Version;
const SupportedVersions = version_api.SupportedVersions;

const ping_api = @import("api/ping.zig");

const http = std.http;

pub const ClientConfig = struct {
    transport: TransportConfig = .{ .unix = "/var/run/docker.sock" },
};

fn negotiateVersionBody(allocator: std.mem.Allocator, body: []const u8) !Version {
    const parsed = try std.json.parseFromSlice(models.SystemVersion, allocator, body, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();

    const max_version = parsed.value.ApiVersion orelse return version_api.VersionError.MissingApiVersion;
    const min_version = parsed.value.MinAPIVersion orelse return version_api.VersionError.MissingApiVersion;

    const server: SupportedVersions = .{
        .max_supported_version = try Version.parse_version(max_version),
        .min_supported_version = try Version.parse_version(min_version),
    };

    return version_api.suppored_versions.negotiate(server);
}

fn negotiateVersion(client: *http.Client, connection: *http.Client.Connection, uri: std.Uri) !Version {
    var req = blk: {
        errdefer client.connection_pool.release(connection, client.io);

        break :blk try client.request(.GET, uri, .{ .connection = connection, .redirect_behavior = .unhandled, .headers = .{ .accept_encoding = .{ .override = "identity" } } });
    };
    defer req.deinit();

    try req.sendBodiless();

    var resp = try req.receiveHead(&.{});

    const status = resp.head.status;
    const encoding = resp.head.content_encoding;

    var transfer_buff: [1024]u8 = undefined;
    const reader = resp.reader(&transfer_buff);

    if (status != .ok) {
        return error.UnexpectedHttpStatus;
    }

    if (encoding != .identity) {
        return error.UnsupportedContentEncoding;
    }

    const body = reader.allocRemaining(client.allocator, .limited(64 * 1024)) catch |err| switch (err) {
        error.ReadFailed => return resp.bodyErr() orelse err,
        else => return err,
    };
    defer client.allocator.free(body);

    return negotiateVersionBody(client.allocator, body);
}

pub const Client = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    client: *http.Client,
    transport: Transport,
    base_url: []const u8,
    negotiated_version: ?Version,

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
            .negotiated_version = undefined,
        };

        return client;
    }

    pub fn connect(self: *Client) !void {
        if (self.negotiated_version != null) {
            return;
        }

        const url = try std.fmt.allocPrint(self.allocator, "{s}/version", .{self.base_url});
        defer self.allocator.free(url);

        const uri = try std.Uri.parse(url);

        const connection = try self.transport.connect(self.client);

        const selected_version = try negotiateVersion(self.client, connection, uri);

        self.negotiated_version = selected_version;
    }

    fn ping(self: *Client) !void {
        const url = try std.fmt.allocPrint(self.allocator, "{s}/_ping", .{self.base_url});
        defer self.allocator.free(url);

        const uri = try std.Uri.parse(url);

        const connection = try self.transport.connect(self.client);

        try ping_api.runPing(self.client, connection, uri);
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

        const result = ping_api.runPing(client.client, connection, uri);

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
