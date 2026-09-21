const std = @import("std");
const Client = @import("../client.zig").Client;
const models = @import("../generated/models.zig");
const QueryParam = @import("../http.zig").QueryParam;
const writeTargetUrl = @import("../http.zig").writeTargetURL;

const Paths = struct {
    const List = "/containers/json";
    const Create = "/containers/create";
    const Get = "/containers/{f}/json";
    const Start = "/containers/{f}/start";
    const Stop = "/containers/{f}/stop";
};

pub const ListOptions = struct {
    all: ?bool = null,
    limit: ?u32 = null,
};

pub const ContainerCreateRequest = struct {
    config: models.ContainerConfig,
    host_config: ?models.HostConfig,
    networking_config: ?models.NetworkingConfig,

    pub fn jsonStringify(self: ContainerCreateRequest, json_string: *std.json.Stringify) !void {
        try json_string.beginObject();

        inline for (std.meta.fields(models.ContainerConfig)) |field| {
            if (@field(self.config, field.name)) |value| {
                try json_string.objectField(field.name);
                try json_string.write(value);
            }
        }

        if (self.host_config) |host| {
            try json_string.objectField("HostConfig");
            try json_string.write(host);
        }

        if (self.networking_config) |network| {
            try json_string.objectField("NetworkingConfig");
            try json_string.write(network);
        }

        try json_string.endObject();
    }
};

pub const Containers = struct {
    client: *Client,

    pub fn list(self: Containers, options: ListOptions) !std.json.Parsed([]const models.ContainerSummary) {
        var target: std.Io.Writer.Allocating = .init(self.client.allocator);
        defer target.deinit();

        const writer = &target.writer;

        var params: [2]QueryParam = undefined;
        var count: u8 = 0;

        if (options.all) |value| {
            params[count] = .{ .name = "all", .value = .{
                .boolean = value,
            } };

            count += 1;
        }

        if (options.limit) |value| {
            params[count] = .{ .name = "limit", .value = .{
                .int = value,
            } };

            count += 1;
        }

        try writeTargetUrl(
            writer,
            Paths.List,
            .{},
            params[0..count],
        );

        return self.client.getJson([]const models.ContainerSummary, .{
            .target = writer.buffered(),
            .versioned = true,
        });
    }

    pub fn get(self: Containers, name_or_id: []const u8) !std.json.Parsed(models.ContainerInspectResponse) {
        var target: std.Io.Writer.Allocating = .init(self.client.allocator);
        defer target.deinit();

        const id: std.Uri.Component = .{
            .raw = name_or_id,
        };

        try writeTargetUrl(
            &target.writer,
            Paths.Get,
            .{std.fmt.alt(id, .formatEscaped)},
            &.{},
        );

        return self.client.getJson(models.ContainerInspectResponse, .{
            .target = target.writer.buffered(),
            .versioned = true,
        });
    }

    pub fn create(self: Containers, request: ContainerCreateRequest, params: []const QueryParam) !std.json.Parsed(models.ContainerCreateResponse) {
        var target: std.Io.Writer.Allocating = .init(self.client.allocator);
        defer target.deinit();

        const writer = &target.writer;

        try writeTargetUrl(writer, Paths.Create, .{}, params);

        const payload = try std.json.Stringify.valueAlloc(
            self.client.allocator,
            request,
            .{
                .emit_null_optional_fields = false,
            },
        );
        defer self.client.allocator.free(payload);

        return self.client.getJson(models.ContainerCreateResponse, .{
            .target = writer.buffered(),
            .versioned = true,
            .method = .post,
            .expected_status = .created,
            .payload = payload,
            .content_type = "application/json",
        });
    }
};
