const std = @import("std");

pub const QueryValue = union(enum) {
    string: []const u8,
    int: i64,
    uint: u64,
    boolean: bool,
};

pub const QueryParam = struct {
    name: []const u8,
    value: QueryValue,
};

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

pub fn writeTargetURL(
    writer: *std.Io.Writer,
    comptime path: []const u8,
    path_args: anytype,
    params: []const QueryParam,
) !void {
    try writer.print(path, path_args);
    try query_params_tu_url_encoded_string(writer, params);
}
