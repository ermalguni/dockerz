const std = @import("std");
pub const Client = @import("../client.zig").Client;
const Endpoints = @import("./local_endpoints.zig");
const models = @import("../generated/models.zig");
const writeEndpointTarget = @import("../http.zig").writeEndpointTarget;

pub const ListOptions = struct {
    all: ?bool = null,
    filters: ?[]const u8 = null,
    shared_size: ?bool = null,
    digests: ?bool = null,
};

pub const TagOptions = struct {
    repo: []const u8,
    tag: ?[]const u8 = null,
};

pub const RemoveOptions = struct {
    force: ?bool = null,
    no_prune: ?bool = null,
};

pub const PruneOptions = struct {
    filters: ?[]const u8 = null,
};

pub const PruneResponse = struct {
    ImagesDeleted: ?[]const models.ImageDeleteResponseItem = null,
    SpaceReclaimed: ?i64 = null,
};

pub const Local = struct {
    client: *Client,

    pub fn list(self: Local, options: ListOptions) !std.json.Parsed([]const models.ImageSummary) {
        var target: std.Io.Writer.Allocating = .init(self.client.allocator);
        defer target.deinit();

        try writeEndpointTarget(
            &target.writer,
            Endpoints.List,
            .{},
            options,
        );

        return self.client.getJson(
            []const models.ImageSummary,
            .{
                .target = target.writer.buffered(),
                .versioned = true,
                .method = .get,
                .expected_status = .ok,
            },
        );
    }

    pub fn get(
        self: Local,
        name_or_id: []const u8,
    ) !std.json.Parsed(models.ImageInspect) {
        var target: std.Io.Writer.Allocating = .init(self.client.allocator);
        defer target.deinit();

        const id: std.Uri.Component = .{
            .raw = name_or_id,
        };

        try writeEndpointTarget(
            &target.writer,
            Endpoints.Get,
            .{std.fmt.alt(id, .formatEscaped)},
            .{},
        );

        return self.client.getJson(
            models.ImageInspect,
            .{
                .target = target.writer.buffered(),
                .versioned = true,
                .method = .get,
                .expected_status = .ok,
            },
        );
    }

    pub fn history(
        self: Local,
        name_or_id: []const u8,
    ) !std.json.Parsed([]const models.ImageHistoryResponseItem) {
        var target: std.Io.Writer.Allocating = .init(self.client.allocator);
        defer target.deinit();

        const name: std.Uri.Component = .{
            .raw = name_or_id,
        };

        try writeEndpointTarget(
            &target.writer,
            Endpoints.History,
            .{std.fmt.alt(name, .formatEscaped)},
            .{},
        );

        return self.client.getJson([]const models.ImageHistoryResponseItem, .{
            .target = target.writer.buffered(),
            .versioned = true,
            .method = .get,
            .expected_status = .ok,
        });
    }

    pub fn tag(
        self: Local,
        name_or_id: []const u8,
        options: TagOptions,
    ) !void {
        var target: std.Io.Writer.Allocating = .init(self.client.allocator);
        defer target.deinit();

        const name: std.Uri.Component = .{
            .raw = name_or_id,
        };

        try writeEndpointTarget(
            &target.writer,
            Endpoints.Tag,
            .{std.fmt.alt(name, .formatEscaped)},
            options,
        );

        var response = try self.client.request(.{
            .target = target.writer.buffered(),
            .versioned = true,
            .method = .post,
            .expected_status = .created,
        });
        defer response.deinit();
    }

    pub fn remove(
        self: Local,
        name_or_id: []const u8,
        options: RemoveOptions,
    ) !std.json.Parsed([]const models.ImageDeleteResponseItem) {
        var target: std.Io.Writer.Allocating = .init(self.client.allocator);
        defer target.deinit();

        const name: std.Uri.Component = .{
            .raw = name_or_id,
        };

        try writeEndpointTarget(
            &target.writer,
            Endpoints.Remove,
            .{std.fmt.alt(name, .formatEscaped)},
            options,
        );

        return self.client.getJson([]const models.ImageDeleteResponseItem, .{
            .target = target.writer.buffered(),
            .versioned = true,
            .method = .delete,
            .expected_status = .ok,
        });
    }

    pub fn prune(
        self: Local,
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
