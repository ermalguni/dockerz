const std = @import("std");
const Client = @import("../../client.zig").Client;
const models = @import("../../generated/models.zig");
const Endpoints = @import("system_endpoints.zig");
const writeEndpointTarget = @import("../../http.zig").writeEndpointTarget;

const version_types = @import("version.zig");
const Version = version_types.Version;
const VersionError = version_types.VersionError;
const SupportedVersions = version_types.SupportedVersions;

pub const PingError = error{
    UnexpectedHttpStatus,
    UnsupportedContentEncoding,
    InvalidPingResponse,
};

pub const AuthRequest = struct {
    username: ?[]const u8 = null,
    password: ?[]const u8 = null,
    serveraddress: ?[]const u8 = null,
    identitytoken: ?[]const u8 = null,
    registrytoken: ?[]const u8 = null,
};

pub const EventsOptions = struct {
    since: ?[]const u8 = null,
    until: ?[]const u8 = null,
    filters: ?[]const u8 = null,
    timeout: std.Io.Timeout = .none,
};

pub const DiskUsageOptions = struct {
    types: []const []const u8 = &.{},
    verbose: ?bool = null,
    timeout: std.Io.Timeout = .none,
};

pub const DiskUsageResponse = struct {
    ImageUsage: ?models.ImagesDiskUsage = null,
    ContainerUsage: ?models.ContainersDiskUsage = null,
    VolumeUsage: ?models.VolumesDiskUsage = null,
    BuildCacheUsage: ?models.BuildCacheDiskUsage = null,

    // Response fields used by older API versions.
    LayersSize: ?i64 = null,
    Images: ?[]const std.json.Value = null,
    Containers: ?[]const std.json.Value = null,
    Volumes: ?[]const std.json.Value = null,
    BuildCache: ?[]const std.json.Value = null,
};

pub const System = struct {
    client: *Client,

    pub fn ping(self: System) !void {
        var response = try self.client.request(.{
            .target = Endpoints.Ping.path,
            .versioned = false,
            .method = .get,
            .expected_status = .ok,
            .max_body_bytes = 8 * 1024,
        });
        defer response.deinit();

        const body = try response.body() orelse
            return PingError.InvalidPingResponse;

        if (!std.mem.eql(u8, body, "OK")) {
            return PingError.InvalidPingResponse;
        }
    }

    pub fn pingHead(self: System) !void {
        var response = try self.client.request(.{
            .target = Endpoints.PingHead.path,
            .versioned = false,
            .method = .head,
            .expected_status = .ok,
        });
        defer response.deinit();
    }

    pub fn version(
        self: System,
    ) !std.json.Parsed(models.SystemVersion) {
        return self.client.getJson(models.SystemVersion, .{
            .target = Endpoints.Version.path,
            .versioned = false,
            .method = .get,
            .expected_status = .ok,
            .max_body_bytes = 64 * 1024,
        });
    }

    pub fn negotiateVersion(self: System) !Version {
        var response = try self.client.request(.{
            .target = Endpoints.Version.path,
            .versioned = false,
            .method = .get,
            .expected_status = .ok,
            .max_body_bytes = 64 * 1024,
        });
        defer response.deinit();

        const body = try response.body() orelse
            return VersionError.MissingApiVersion;

        return negotiateVersionBody(
            self.client.allocator,
            body,
        );
    }

    pub fn info(
        self: System,
    ) !std.json.Parsed(models.SystemInfo) {
        return self.client.getJson(models.SystemInfo, .{
            .target = Endpoints.Info.path,
            .versioned = true,
            .method = .get,
            .expected_status = .ok,
        });
    }

    pub fn auth(
        self: System,
        credentials: AuthRequest,
    ) !?std.json.Parsed(models.AuthResponse) {
        const payload = try std.json.Stringify.valueAlloc(
            self.client.allocator,
            credentials,
            .{
                .emit_null_optional_fields = false,
            },
        );
        defer self.client.allocator.free(payload);

        var response = try self.client.request(.{
            .target = Endpoints.Auth.path,
            .versioned = true,
            .method = .post,
            .expected_status = .ok,
            .additional_expected_status = .no_content,
            .payload = payload,
            .content_type = "application/json",
        });
        defer response.deinit();

        if (response.status() == .no_content) {
            return null;
        }

        const body = try response.body() orelse
            return error.EmptyResponseBody;

        const parsed = try std.json.parseFromSlice(
            models.AuthResponse,
            self.client.allocator,
            body,
            .{
                .allocate = .alloc_always,
                .ignore_unknown_fields = true,
            },
        );

        return parsed;
    }

    pub fn diskUsage(
        self: System,
        options: DiskUsageOptions,
    ) !std.json.Parsed(DiskUsageResponse) {
        var target: std.Io.Writer.Allocating = .init(self.client.allocator);
        defer target.deinit();

        try writeEndpointTarget(
            &target.writer,
            Endpoints.DiskUsage,
            .{},
            options,
        );

        return self.client.getJson(DiskUsageResponse, .{
            .target = target.writer.buffered(),
            .versioned = true,
            .method = .get,
            .expected_status = .ok,
            .timeout = options.timeout,
        });
    }

    pub fn events(
        self: System,
        options: EventsOptions,
        handler: anytype,
    ) !void {
        var target: std.Io.Writer.Allocating = .init(self.client.allocator);
        defer target.deinit();

        try writeEndpointTarget(
            &target.writer,
            Endpoints.Events,
            .{},
            options,
        );

        var response = try self.client.request(.{
            .target = target.writer.buffered(),
            .versioned = true,
            .method = .get,
            .expected_status = .ok,
            .stream = true,
            .timeout = options.timeout,
        });
        defer response.deinit();

        var buffer: [8192]u8 = undefined;
        var body = try response.reader(&buffer);

        var line: std.Io.Writer.Allocating = .init(self.client.allocator);
        defer line.deinit();

        var reached_end = false;

        while (!reached_end) {
            line.clearRetainingCapacity();

            _ = body.interface.streamDelimiter(
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
                body.interface.toss(1);
            }

            const bytes = std.mem.trim(
                u8,
                line.writer.buffered(),
                " \t\r\x1e",
            );

            if (bytes.len == 0) continue;

            const event = try std.json.parseFromSlice(
                models.EventMessage,
                self.client.allocator,
                bytes,
                .{
                    .allocate = .alloc_if_needed,
                    .ignore_unknown_fields = true,
                },
            );
            defer event.deinit();

            if (!try handler.onEvent(event.value)) {
                return;
            }
        }
    }
};

fn negotiateVersionBody(allocator: std.mem.Allocator, body: []const u8) !Version {
    const parsed = try std.json.parseFromSlice(models.SystemVersion, allocator, body, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();

    const max_version = parsed.value.ApiVersion orelse return VersionError.MissingApiVersion;
    const min_version = parsed.value.MinAPIVersion orelse return VersionError.MissingApiVersion;

    const server: SupportedVersions = .{
        .max_supported_version = try Version.parse_version(max_version),
        .min_supported_version = try Version.parse_version(min_version),
    };

    return version_types.supported_versions.negotiate(server);
}
