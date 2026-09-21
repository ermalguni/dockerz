const std = @import("std");
const Transport = @import("transport/transport.zig").Transport;
pub const TransportConfig = Transport.Config;

const dusty = @import("dusty");

const models = @import("generated/models.zig");
const version_api = @import("api/version.zig");
const ping_api = @import("api/ping.zig");

const Version = version_api.Version;
const SupportedVersions = version_api.SupportedVersions;

const http = std.http;

pub const ClientConfig = struct {
    transport: TransportConfig = .{ .unix = "/var/run/docker.sock" },
};

pub const Client = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    client: dusty.Client,
    transport: Transport,
    base_url: []const u8,
    negotiated_version: ?Version,

    pub const RequestOptions = struct {
        target: []const u8,
        versioned: bool = true,
        method: dusty.Method = .get,
        expected_status: dusty.Status = .ok,
        max_body_bytes: usize = 8 * 1024 * 1024,
        payload: ?[]const u8 = null,
        content_type: ?[]const u8 = null,
    };

    pub fn init(allocator: std.mem.Allocator, io: std.Io, config: ClientConfig) !Client {
        var transport = try Transport.init(allocator, config.transport);
        errdefer transport.deinit(allocator);

        const base_url = switch (transport) {
            .unix => try allocator.dupe(u8, "http://localhost"),

            .tcp => |tcp| try std.fmt.allocPrint(allocator, "http://{s}:{d}", .{ tcp.host, tcp.port }),
        };
        errdefer allocator.free(base_url);

        const http_client = dusty.Client.init(allocator, io, .{
            .max_redirects = 0,
            .max_response_size = 8 * 1024 * 1024,
        });
        errdefer http_client.deinit();

        const client = Client{
            .allocator = allocator,
            .io = io,
            .client = http_client,
            .transport = transport,
            .base_url = base_url,
            .negotiated_version = null,
        };

        return client;
    }

    pub fn connect(self: *Client) !void {
        if (self.negotiated_version != null) {
            return;
        }

        self.negotiated_version = try version_api.getVersion(self);
    }

    fn ping(self: *Client) !void {
        try ping_api.runPing(self);
    }

    pub fn containers(self: *Client) @import("api/containers.zig").Containers {
        return .{ .client = self };
    }

    fn buildUrl(self: *Client, target: []const u8, versioned: bool) ![]u8 {
        if (!versioned) {
            return std.fmt.allocPrint(self.allocator, "{s}{s}", .{ self.base_url, target });
        }

        const vers = self.negotiated_version orelse return error.ApiVersionNotNegotiated;
        return std.fmt.allocPrint(self.allocator, "{s}/v{d}.{d}{s}", .{ self.base_url, vers.major, vers.minor, target });
    }

    pub fn request(self: *Client, options: RequestOptions) !dusty.ClientResponse {
        const url = try self.buildUrl(options.target, options.versioned);
        defer self.allocator.free(url);

        var headers = try dusty.Headers.init(self.allocator, 2);
        defer headers.deinit(self.allocator);

        try headers.put("Accept-Encoding", "identity");

        if (options.content_type) |content_type| {
            try headers.put("Content-Type", content_type);
        }

        var response = try self.client.fetch(url, .{
            .method = options.method,
            .headers = &headers,
            .body = options.payload,
            .max_redirects = 0,
            .decompress = false,
            .timeout = .{
                .duration = .{
                    .raw = .fromSeconds(3),
                    .clock = .awake,
                },
            },
            .unix_socket_path = switch (self.transport) {
                .unix => |unix| unix.socket_path,
                .tcp => null,
            },
        });
        errdefer response.deinit();

        if (response.status() != options.expected_status) {
            return error.UnexpectedHttpStatus;
        }

        if (response.contentEncoding() != .identity) {
            return error.UnsupportedContentEncoding;
        }

        response.max_response_size = @min(response.max_response_size, options.max_body_bytes);

        return response;
    }

    pub fn getJson(self: *Client, comptime T: type, options: RequestOptions) !std.json.Parsed(T) {
        var response = try self.request(options);
        defer response.deinit();

        const body = try response.body() orelse return error.EmptyResponseBody;

        return std.json.parseFromSlice(T, self.allocator, body, .{
            .allocate = .alloc_always,
            .ignore_unknown_fields = true,
        });
    }

    pub fn deinit(self: *Client) void {
        self.client.deinit();
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

    try std.testing.expectEqualStrings("/_ping", request.head.target);

    try request.respond(body, .{ .status = status, .keep_alive = false });
}

test "client ping HTTP over a tcp connection" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    const cases = [_]struct {
        status: http.Status,
        body: []const u8,
        expected: ?anyerror,
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

        const config: TransportConfig = .{
            .tcp = .{
                .host = "127.0.0.1",
                .port = listener.socket.address.getPort(),
            },
        };

        var client = try Client.init(allocator, io, .{ .transport = config });
        defer client.deinit();

        const result = client.ping();

        if (case.expected) |expected| {
            try std.testing.expectError(expected, result);
        } else {
            try result;
        }

        try server_task.await(io);
    }
}

test "client initialization does not require a running daemon" {
    const config: TransportConfig = .{
        .tcp = .{
            .host = "127.0.0.1",
            .port = 0,
        },
    };
    var client = try Client.init(
        std.testing.allocator,
        std.testing.io,
        .{ .transport = config },
    );
    defer client.deinit();
}
