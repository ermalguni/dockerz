const std = @import("std");
const Client = @import("../client.zig").Client;
const Endpoints = @import("builder_endpoints.zig");
const writeEndpointTarget = @import("../http.zig").writeEndpointTarget;

pub const BuildContext = union(enum) {
    archive: []const u8,
    remote: []const u8,
};

pub const BuildOptions = struct {
    version: []const u8 = "1",

    dockerfile: ?[]const u8 = null,
    tags: []const []const u8 = &.{},
    extra_hosts: ?[]const u8 = null,

    quiet: ?bool = null,
    no_cache: ?bool = null,
    pull: ?bool = null,
    remove_intermediate: ?bool = null,
    force_remove: ?bool = null,

    memory: ?i64 = null,
    memory_swap: ?i64 = null,
    cpu_shares: ?i64 = null,
    cpu_set: ?[]const u8 = null,
    cpu_period: ?i64 = null,
    cpu_quota: ?i64 = null,
    shm_size: ?i64 = null,

    cache_from: ?[]const u8 = null,
    build_args: ?[]const u8 = null,
    labels: ?[]const u8 = null,
    outputs: ?[]const u8 = null,

    squash: ?bool = null,
    network_mode: ?[]const u8 = null,
    platform: ?[]const u8 = null,
    target: ?[]const u8 = null,

    registry_config_json: ?[]const u8 = null,
    timeout: std.Io.Timeout = .none,
};

pub const PruneOptions = struct {
    all: ?bool = null,
    filters: ?[]const u8 = null,
    reserved_space: ?i64 = null,
    max_used_space: ?i64 = null,
    min_free_space: ?i64 = null,
    timeout: std.Io.Timeout = .none,
};

pub const PruneResponse = struct {
    CachesDeleted: ?[]const []const u8 = null,
    SpaceReclaimed: ?i64 = null,
};

pub const BuildEvent = struct {
    stream: ?[]const u8 = null,
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

pub const Builder = struct {
    client: *Client,

    pub fn build(
        self: Builder,
        context: BuildContext,
        options: BuildOptions,
        progress: anytype,
    ) !void {
        var target: std.Io.Writer.Allocating = .{ .allocator = self.client.allocator };
        defer target.deinit();

        try writeEndpointTarget(
            &target.writer,
            Endpoints.Build,
            .{},
            options,
        );

        const payload: ?[]const u8 = switch (context) {
            .archive => |archive| archive,
            .remote => |remote| blk: {
                try target.writer.writeAll("&remote=");

                const component: std.Uri.Component = .{ .raw = remote };
                try component.formatEscaped(&target.writer);
                break :blk null;
            },
        };

        const reg_config: ?[]u8 = if (options.registry_config_json) |json|
            try encodeRegistryConfig(self.client.allocator, json)
        else
            null;

        defer {
            if (reg_config) |encoded| {
                self.client.allocator.free(encoded);
            }
        }

        var resp = try self.client.request(
            .{
                .target = target.writer.buffered(),
                .versioned = true,
                .method = .post,
                .expected_status = .ok,
                .payload = payload,
                .content_type = if (payload != null)
                    "application/x-tar"
                else
                    null,
                .registry_config = reg_config,
                .stream = true,
                .timeout = options.timeout,
            },
        );
        defer resp.deinit();

        var buffer: [8192]u8 = undefined;
        var body = try resp.reader(&buffer);

        try consumeBuildOutput(
            self.client.allocator,
            &body.interface,
            progress,
        );
    }

    pub fn prune(
        self: Builder,
        options: PruneOptions,
    ) !std.json.Parsed(PruneResponse) {
        var target: std.Io.Writer.Allocating = .{ .allocator = self.client.allocator };
        defer target.deinit();

        try writeEndpointTarget(
            &target.writer,
            Endpoints.Prune,
            .{},
            options,
        );

        return try self.client.getJson(
            PruneResponse,
            .{
                .target = target.writer.buffered(),
                .versioned = true,
                .method = .post,
                .expected_status = .ok,
                .timeout = options.timeout,
            },
        );
    }
};

fn encodeRegistryConfig(
    allocator: std.mem.Allocator,
    json: []const u8,
) ![]u8 {
    const encoder = std.base64.url_safe.Encoder;

    const encoded = try allocator.alloc(
        u8,
        encoder.calcSize(json.len),
    );

    _ = encoder.encode(encoded, json);

    return encoded;
}

fn consumeBuildOutput(
    allocator: std.mem.Allocator,
    reader: *std.Io.Reader,
    progress: anytype,
) !void {
    var line: std.Io.Writer.Allocating = .init(allocator);
    defer line.deinit();

    var reached_end = false;

    while (!reached_end) {
        line.clearRetainingCapacity();

        _ = reader.streamDelimiter(
            &line.writer,
            '\n',
        ) catch |err| switch (err) {
            error.EndOfStream => blk: {
                reached_end = true;
                break :blk 0;
            },
            else => return err,
        };

        if (!reached_end) {
            reader.toss(1);
        }

        const bytes = std.mem.trim(
            u8,
            line.writer.buffered(),
            " \t\r",
        );

        if (bytes.len == 0) continue;

        const event = try std.json.parseFromSlice(
            BuildEvent,
            allocator,
            bytes,
            .{
                .allocate = .alloc_if_needed,
                .ignore_unknown_fields = true,
            },
        );
        defer event.deinit();

        try progress.onProgress(event.value);

        if (event.value.@"error" != null or event.value.errorDetail != null) {
            return error.BuildFailed;
        }
    }
}
