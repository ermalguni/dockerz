const std = @import("std");
const Client = @import("../client.zig").Client;
const models = @import("../generated/models.zig");
const Endpoints = @import("registry_endpoints.zig");
const writeEndpointTarget = @import("../http.zig").writeEndpointTarget;

pub const Auth = struct {
    username: ?[]const u8 = null,
    password: ?[]const u8 = null,
    serveraddress: ?[]const u8 = null,
    identitytoken: ?[]const u8 = null,
    registrytoken: ?[]const u8 = null,
};

pub const SearchOptions = struct {
    limit: ?u32 = null,
    filters: ?[]const u8 = null,
};

pub const InspectOptions = struct {
    auth: Auth = .{},
};

pub const PullOptions = struct {
    tag: ?[]const u8 = null,
    platform: ?[]const u8 = null,
    auth: Auth = .{},
    timeout: std.Io.Timeout = .none,
};

pub const PushOptions = struct {
    tag: ?[]const u8 = null,

    // API v1.55 uses a JSON-encoded OCI platform object here.
    platform: ?[]const u8 = null,

    auth: Auth = .{},
    timeout: std.Io.Timeout = .none,
};

pub const SearchResult = struct {
    name: ?[]const u8 = null,
    description: ?[]const u8 = null,
    star_count: ?i64 = null,
    is_official: ?bool = null,
    is_automated: ?bool = null,
};

pub const ProgressEvent = struct {
    id: ?[]const u8 = null,
    status: ?[]const u8 = null,
    progress: ?[]const u8 = null,
    progressDetail: ?std.json.Value = null,
    aux: ?std.json.Value = null,
    @"error": ?[]const u8 = null,
    errorDetail: ?ErrorDetail = null,

    pub const ErrorDetail = struct {
        code: ?i64 = null,
        message: ?[]const u8 = null,
    };
};

pub const Registry = struct {
    client: *Client,

    pub fn search(self: Registry, term: []const u8, options: SearchOptions) !std.json.Parsed([]const SearchResult) {
        var target: std.Io.Writer.Allocating = .{ .allocator = self.client.allocator };
        defer target.deinit();

        try writeEndpointTarget(
            &target.writer,
            Endpoints.Search,
            .{},
            .{
                .term = term,
                .limit = options.limit,
                .filters = options.filters,
            },
        );

        return self.client.getJson(
            []const SearchResult,
            .{
                .target = target.writer.buffered(),
                .versioned = true,
                .method = .get,
                .expected_status = .ok,
            },
        );
    }

    pub fn inspect(
        self: Registry,
        reference: []const u8,
        options: InspectOptions,
    ) !std.json.Parsed(models.DistributionInspect) {
        var target: std.Io.Writer.Allocating = .init(self.client.allocator);
        defer target.deinit();

        const name: std.Uri.Component = .{ .raw = reference };

        try writeEndpointTarget(
            &target.writer,
            Endpoints.Inspect,
            .{std.fmt.alt(name, .formatEscaped)},
            .{},
        );

        const auth = try encodeAuth(self.client.allocator, options.auth);
        defer self.client.allocator.free(auth);

        return self.client.getJson(models.DistributionInspect, .{
            .target = target.writer.buffered(),
            .versioned = true,
            .method = .get,
            .expected_status = .ok,
            .registry_auth = auth,
        });
    }

    pub fn pull(
        self: Registry,
        reference: []const u8,
        options: PullOptions,
        progress: anytype,
    ) !void {
        var target: std.Io.Writer.Allocating = .init(self.client.allocator);
        defer target.deinit();

        try writeEndpointTarget(
            &target.writer,
            Endpoints.Pull,
            .{},
            .{
                .reference = reference,
                .tag = options.tag,
                .platform = options.platform,
            },
        );

        try self.runProgress(
            target.writer.buffered(),
            options.auth,
            options.timeout,
            progress,
        );
    }

    pub fn push(
        self: Registry,
        repository: []const u8,
        options: PushOptions,
        progress: anytype,
    ) !void {
        var target: std.Io.Writer.Allocating = .init(self.client.allocator);
        defer target.deinit();

        const name: std.Uri.Component = .{ .raw = repository };

        try writeEndpointTarget(
            &target.writer,
            Endpoints.Push,
            .{std.fmt.alt(name, .formatEscaped)},
            options,
        );

        try self.runProgress(
            target.writer.buffered(),
            options.auth,
            options.timeout,
            progress,
        );
    }

    fn runProgress(
        self: Registry,
        target: []const u8,
        auth_config: Auth,
        timeout: std.Io.Timeout,
        progress: anytype,
    ) !void {
        const auth = try encodeAuth(self.client.allocator, auth_config);
        defer self.client.allocator.free(auth);

        var resp = try self.client.request(
            .{
                .target = target,
                .versioned = true,
                .method = .post,
                .expected_status = .ok,
                .registry_auth = auth,
                .stream = true,
                .timeout = timeout,
            },
        );
        defer resp.deinit();

        var buffer: [8192]u8 = undefined;
        var body = try resp.reader(&buffer);

        var line: std.Io.Writer.Allocating = .init(self.client.allocator);
        defer line.deinit();

        var reached_end = false;

        while (!reached_end) {
            line.clearRetainingCapacity();

            _ = body.interface.streamDelimiter(&line.writer, '\n') catch |err| switch (err) {
                error.EndOfStream => blk: {
                    reached_end = true;
                    break :blk;
                },
                else => return err,
            };

            if (!reached_end) {
                body.interface.toss(1);
            }

            const bytes = std.mem.trim(
                u8,
                line.writer.buffered(),
                " \t\r",
            );

            if (bytes.len == 0) continue;

            const event = try std.json.parseFromSlice(
                ProgressEvent,
                self.client.allocator,
                bytes,
                .{ .allocate = .alloc_if_needed, .ignore_unknown_fields = true },
            );
            defer event.deinit();

            try progress.onProgress(event.value);

            if (event.value.@"error" != null or event.value.errorDetail != null) {
                return error.RegistryOperationFailed;
            }
        }
    }
};

fn encodeAuth(allocator: std.mem.Allocator, auth: Auth) ![]u8 {
    const json = try std.json.Stringify.valueAlloc(
        allocator,
        auth,
        .{ .emit_null_optional_fields = false },
    );
    defer allocator.free(json);

    const encoder = std.base64.url_safe.Encoder;

    const encoded = try allocator.alloc(
        u8,
        encoder.calcSize(json.len),
    );

    _ = encoder.encode(encoded, json);

    return encoded;
}
