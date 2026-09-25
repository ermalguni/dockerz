const std = @import("std");

pub const QueryValue = union(enum) {
    string: []const u8,
    int: i64,
    uint: u64,
    boolean: bool,
};

pub const QueryField = struct {
    field: []const u8,
    name: []const u8,
    tag: std.meta.Tag(QueryValue),
};

pub const Endpoint = struct {
    path: []const u8,
    query: []const QueryField = &.{},
};

pub const QueryParam = struct {
    name: []const u8,
    value: QueryValue,
};

pub fn QueryParams(comptime capacity: usize) type {
    return struct {
        const Self = @This();

        items: [capacity]QueryParam = undefined,
        len: usize = 0,

        pub fn addOptional(
            self: *Self,
            name: []const u8,
            comptime tag: std.meta.Tag(QueryValue),
            optional: anytype,
        ) void {
            if (optional) |value| {
                std.debug.assert(self.len < capacity);

                self.items[self.len] = .{
                    .name = name,
                    .value = @unionInit(
                        QueryValue,
                        @tagName(tag),
                        value,
                    ),
                };

                self.len += 1;
            }
        }

        pub fn slice(self: *const Self) []const QueryParam {
            return self.items[0..self.len];
        }
    };
}

pub fn query_params_tu_url_encoded_string(
    writer: *std.Io.Writer,
    params: []const QueryParam,
) !void {
    if (params.len == 0) return;

    try writer.writeByte('?');

    for (params, 0..) |param, i| {
        if (i != 0) try writer.writeByte('&');

        const key: std.Uri.Component = .{ .raw = param.name };
        try key.formatEscaped(writer);
        try writer.writeByte('=');

        switch (param.value) {
            .int => |value| try writer.print("{d}", .{value}),
            .uint => |value| try writer.print("{d}", .{value}),
            .boolean => |value| try writer.writeAll(if (value) "true" else "false"),
            .string => |value| {
                const component: std.Uri.Component = .{ .raw = value };
                try component.formatEscaped(writer);
            },
        }
    }
}

fn writeTargetURL(
    writer: *std.Io.Writer,
    comptime path: []const u8,
    path_args: anytype,
    params: []const QueryParam,
) !void {
    try writer.print(path, path_args);
    try query_params_tu_url_encoded_string(writer, params);
}

pub fn writeEndpointTarget(
    writer: *std.Io.Writer,
    comptime endpoint: Endpoint,
    path_args: anytype,
    options: anytype,
) !void {
    var params: QueryParams(endpoint.query.len) = .{};

    inline for (endpoint.query) |query_map| {
        const value = @field(options, query_map.field);

        switch (@typeInfo(@TypeOf(value))) {
            .optional => {
                params.addOptional(
                    query_map.name,
                    query_map.tag,
                    value,
                );
            },
            else => {
                params.addOptional(
                    query_map.name,
                    query_map.tag,
                    @as(?@TypeOf(value), value),
                );
            },
        }
    }

    try writeTargetURL(
        writer,
        endpoint.path,
        path_args,
        params.slice(),
    );
}
