const std = @import("std");
const Client = @import("../client.zig").Client;
const models = @import("../generated/models.zig");

pub const ListOptions = struct {
    all: ?bool = null,
    limit: ?u32 = null,
};

// API endpoint paths
const ListContainersPath = "/containers/json";

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
