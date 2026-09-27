const std = @import("std");
const Client = @import("../client.zig").Client;
const models = @import("../generated/models.zig");
const Endpoints = @import("volumes_endpoints.zig");
const writeEndpointTarget = @import("../http.zig").writeEndpointTarget;

pub const ListOptions = struct {
    filters: ?[]const u8 = null,
};

pub const RemoveOptions = struct {
    force: ?bool = null,
};

pub const PruneOptions = struct {
    filters: ?[]const u8 = null,
};

pub const CreateRequest = struct {
    Name: ?[]const u8 = null,
    Driver: ?[]const u8 = null,
    DriverOpts: ?std.json.Value = null,
    Labels: ?std.json.Value = null,
    ClusterVolumeSpec: ?std.json.Value = null,
};

pub const ClusterVolumeResponse = struct {
    ID: ?[]const u8 = null,
    Version: ?models.ObjectVersion = null,
    CreatedAt: ?[]const u8 = null,
    UpdatedAt: ?[]const u8 = null,
    Spec: std.json.Value,

    PublishStatus: ?[]const models.ClusterVolumePublishStatusItem = null,
    Info: ?models.ClusterVolumeInfo = null,
};

pub const VolumeResponse = struct {
    Name: []const u8,
    Driver: []const u8,
    Mountpoint: []const u8,
    Scope: []const u8,

    CreatedAt: ?[]const u8 = null,
    Status: ?std.json.Value = null,
    Labels: std.json.Value,
    Options: std.json.Value,
    UsageData: ?models.VolumeUsageData = null,

    ClusterVolume: ?ClusterVolumeResponse = null,
};

pub const ListResponse = struct {
    Volumes: ?[]const VolumeResponse = null,
    Warnings: ?[]const []const u8 = null,
};

pub const PruneResponse = struct {
    VolumesDeleted: ?[]const []const u8 = null,
    SpaceReclaimed: ?i64 = null,
};

pub const Volumes = struct {
    client: *Client,

    pub fn list(
        self: Volumes,
        options: ListOptions,
    ) !std.json.Parsed(ListResponse) {
        var target: std.Io.Writer.Allocating = .init(self.client.allocator);
        defer target.deinit();

        try writeEndpointTarget(
            &target.writer,
            Endpoints.List,
            .{},
            options,
        );

        return self.client.getJson(ListResponse, .{
            .target = target.writer.buffered(),
            .versioned = true,
            .method = .get,
            .expected_status = .ok,
        });
    }

    pub fn get(
        self: Volumes,
        name: []const u8,
    ) !std.json.Parsed(VolumeResponse) {
        var target: std.Io.Writer.Allocating = .init(self.client.allocator);
        defer target.deinit();

        const volume: std.Uri.Component = .{
            .raw = name,
        };

        try writeEndpointTarget(
            &target.writer,
            Endpoints.Get,
            .{std.fmt.alt(volume, .formatEscaped)},
            .{},
        );

        return self.client.getJson(VolumeResponse, .{
            .target = target.writer.buffered(),
            .versioned = true,
            .method = .get,
            .expected_status = .ok,
        });
    }

    pub fn create(
        self: Volumes,
        request: CreateRequest,
    ) !std.json.Parsed(VolumeResponse) {
        const payload = try std.json.Stringify.valueAlloc(
            self.client.allocator,
            request,
            .{
                .emit_null_optional_fields = false,
            },
        );
        defer self.client.allocator.free(payload);

        return self.client.getJson(VolumeResponse, .{
            .target = Endpoints.Create.path,
            .versioned = true,
            .method = .post,
            .expected_status = .created,
            .payload = payload,
            .content_type = "application/json",
        });
    }

    pub fn update(
        self: Volumes,
        name: []const u8,
        version: i64,
        spec: std.json.Value,
    ) !void {
        var target: std.Io.Writer.Allocating = .init(self.client.allocator);
        defer target.deinit();

        const volume: std.Uri.Component = .{
            .raw = name,
        };

        try writeEndpointTarget(
            &target.writer,
            Endpoints.Update,
            .{std.fmt.alt(volume, .formatEscaped)},
            .{
                .version = version,
            },
        );

        const payload = try std.json.Stringify.valueAlloc(
            self.client.allocator,
            .{
                .Spec = spec,
            },
            .{
                .emit_null_optional_fields = false,
            },
        );
        defer self.client.allocator.free(payload);

        var response = try self.client.request(.{
            .target = target.writer.buffered(),
            .versioned = true,
            .method = .put,
            .expected_status = .ok,
            .payload = payload,
            .content_type = "application/json",
        });
        defer response.deinit();
    }

    pub fn remove(
        self: Volumes,
        name: []const u8,
        options: RemoveOptions,
    ) !void {
        var target: std.Io.Writer.Allocating = .init(self.client.allocator);
        defer target.deinit();

        const volume: std.Uri.Component = .{
            .raw = name,
        };

        try writeEndpointTarget(
            &target.writer,
            Endpoints.Remove,
            .{std.fmt.alt(volume, .formatEscaped)},
            options,
        );

        var response = try self.client.request(.{
            .target = target.writer.buffered(),
            .versioned = true,
            .method = .delete,
            .expected_status = .no_content,
        });
        defer response.deinit();
    }

    pub fn prune(
        self: Volumes,
        options: PruneOptions,
    ) !std.json.Parsed(PruneResponse) {
        var target: std.Io.Writer.Allocating = .init(self.client.allocator);
        defer target.deinit();

        try writeEndpointTarget(
            &target.writer,
            Endpoints.Prune,
            .{},
            options,
        );

        return self.client.getJson(PruneResponse, .{
            .target = target.writer.buffered(),
            .versioned = true,
            .method = .post,
            .expected_status = .ok,
        });
    }
};
