const std = @import("std");
const Client = @import("../client.zig").Client;
const models = @import("../generated/models.zig");
const QueryParam = @import("../http.zig").QueryParam;
const query_param_to_url = @import("../http.zig").query_params_tu_url_encoded_string;

pub const ListOptions = struct {
    all: ?bool = null,
    limit: ?u32 = null,
};

pub const ContainerCreateRequest = struct {
    config: models.ContainerConfig,
    host_config: ?models.HostConfig,
    networking_config: ?models.NetworkingConfig,

    pub fn toJsonString(self: ContainerCreateRequest, json_string: *std.json.Stringify) !void {
        try json_string.beginObject();

        for (std.meta.fields(models.ContainerConfig)) |field| {
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

// API endpoint paths
const ListContainersPath = "/containers/json";
const ContainerCreatePath = "/containers/create";

pub const Containers = struct {
    client: *Client,

    pub fn list(self: Containers, options: ListOptions) !std.json.Parsed([]const models.ContainerSummary) {
        var target: std.Io.Writer.Allocating = .init(self.client.allocator);
        defer target.deinit();

        const writer = &target.writer;

        try writer.writeAll(ListContainersPath);
        var first = true;

        if (options.all) |value| {
            try appendQuery(writer, &first, "all", if (value) "true" else "false");
        }

        if (options.limit) |value| {
            var buffer: [10]u8 = undefined;

            const text = try std.fmt.bufPrint(&buffer, "{d}", .{value});

            try appendQuery(writer, &first, "limit", text);
        }

        return self.client.getJson([]const models.ContainerSummary, .{
            .target = writer.buffered(),
            .versioned = true,
        });
    }

    pub fn get(self: Containers, name_or_id: []const u8) !std.json.Parsed(models.ContainerInspectResponse) {
        var target: std.Io.Writer.Allocating = .init(self.client.allocator);
        defer target.deinit();

        const writer = &target.writer;

        try writer.writeAll("/containers/");

        const id: std.Uri.Component = .{
            .raw = name_or_id,
        };
        try id.formatEscaped(writer);

        try writer.writeAll("/json");

        return self.client.getJson(models.ContainerInspectResponse, .{
            .target = writer.buffered(),
            .versioned = true,
        });
    }

    pub fn create(self: Containers, request: ContainerCreateRequest, params: []const QueryParam) !std.json.Parsed(models.ContainerCreateResponse) {
        var target: std.Io.Writer.Allocating = .init(self.client.allocator);
        defer target.deinit();

        const writer = &target.writer;

        try writer.writeAll(ContainerCreatePath);

        try query_param_to_url(writer, params);

        const payload = try std.json.Stringify.valueAlloc(self.client.allocator, request, .{
            .emit_null_optional_fields = false,
        });

        return self.client.getJson(models.ContainerCreateResponse, .{ .target = writer.buffered(), .versioned = true, .method = .POST, .expected_status = .created, .payload = payload, .content_type = "application/json" });
    }
};

fn appendQuery(
    writer: *std.Io.Writer,
    first: *bool,
    name: []const u8,
    value: []const u8,
) !void {
    try writer.writeByte(if (first.*) '?' else '&');
    first.* = false;

    const key_component: std.Uri.Component = .{
        .raw = name,
    };

    const value_component: std.Uri.Component = .{
        .raw = value,
    };

    try key_component.formatEscaped(writer);
    try writer.writeByte('=');
    try value_component.formatEscaped(writer);
}
