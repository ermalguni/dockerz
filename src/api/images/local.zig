const std = @import("std");
pub const Client = @import("../../client.zig").Client;
const Endpoints = @import("local_endpoints.zig");
const models = @import("../../generated/models.zig");
const writeEndpointTarget = @import("../../http.zig").writeEndpointTarget;

pub const ListOptions = struct {
    all: ?bool = null,
    filters: ?[]const u8 = null,
    shared_size: ?bool = null,
    digests: ?bool = null,
    manifests: ?bool = null,
    identity: ?bool = null,
};

pub const GetOptions = struct {
    manifests: ?bool = null,
    platform: ?[]const u8 = null,
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

pub const CommitOptions = struct {
    repo: ?[]const u8 = null,
    tag: ?[]const u8 = null,
    comment: ?[]const u8 = null,
    author: ?[]const u8 = null,
    pause: ?bool = null,
    changes: ?[]const u8 = null,

    config: ?models.ContainerConfig = null,
    timeout: std.Io.Timeout = .none,
};

pub const AttestationsOptions = struct {
    platform: ?[]const u8 = null,
    predicate_types: []const []const u8 = &.{},
    include_statement: ?bool = null,
};

pub const Local = struct {
    client: *Client,

    pub fn list(self: Local, options: ListOptions) !std.json.Parsed([]const models.ImageSummary) {
        if ((options.identity orelse false) and
            !(options.manifests orelse false))
        {
            return error.IdentityRequiresManifests;
        }

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
        options: GetOptions,
    ) !std.json.Parsed(models.ImageInspect) {
        if ((options.manifests orelse false) and
            options.platform != null)
        {
            return error.ConflictingInspectOptions;
        }

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

    pub fn commit(
        self: Local,
        container: []const u8,
        options: CommitOptions,
    ) !std.json.Parsed(models.IDResponse) {
        var target: std.Io.Writer.Allocating = .init(self.client.allocator);
        defer target.deinit();

        try writeEndpointTarget(
            &target.writer,
            Endpoints.Commit,
            .{},
            .{
                .container = container,
                .repo = options.repo,
                .tag = options.tag,
                .comment = options.comment,
                .author = options.author,
                .pause = options.pause,
                .changes = options.changes,
            },
        );

        const payload: ?[]u8 =
            if (options.config) |config|
                try std.json.Stringify.valueAlloc(
                    self.client.allocator,
                    config,
                    .{
                        .emit_null_optional_fields = false,
                    },
                )
            else
                null;

        defer {
            if (payload) |bytes| {
                self.client.allocator.free(bytes);
            }
        }

        return self.client.getJson(models.IDResponse, .{
            .target = target.writer.buffered(),
            .versioned = true,
            .method = .post,
            .expected_status = .created,
            .payload = payload,
            .content_type = if (payload != null)
                "application/json"
            else
                null,
            .timeout = options.timeout,
        });
    }

    pub fn attestations(
        self: Local,
        name_or_id: []const u8,
        options: AttestationsOptions,
    ) !std.json.Parsed([]const models.AttestationStatement) {
        var target: std.Io.Writer.Allocating = .init(self.client.allocator);
        defer target.deinit();

        const name: std.Uri.Component = .{
            .raw = name_or_id,
        };

        try writeEndpointTarget(
            &target.writer,
            Endpoints.Attestations,
            .{std.fmt.alt(name, .formatEscaped)},
            options,
        );

        return self.client.getJson([]const models.AttestationStatement, .{
            .target = target.writer.buffered(),
            .versioned = true,
            .method = .get,
            .expected_status = .ok,
        });
    }
};
