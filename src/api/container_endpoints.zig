const Endpoint = @import("../http.zig").Endpoint;

pub const List: Endpoint = .{
    .path = "/containers/json",
    .query = &.{
        .{ .field = "all", .name = "all", .tag = .boolean },
        .{ .field = "limit", .name = "limit", .tag = .uint },
    },
};

pub const Start: Endpoint = .{
    .path = "/containers/{f}/start",
    .query = &.{
        .{ .field = "detach_keys", .name = "detachKeys", .tag = .string },
    },
};

pub const Restart: Endpoint = .{
    .path = "/containers/{f}/restart",
    .query = &.{
        .{ .field = "signal", .name = "signal", .tag = .string },
        .{ .field = "timeout_seconds", .name = "t", .tag = .int },
    },
};

pub const Remove: Endpoint = .{
    .path = "/containers/{f}",
    .query = &.{
        .{ .field = "force", .name = "force", .tag = .boolean },
        .{ .field = "volumes", .name = "v", .tag = .boolean },
        .{ .field = "link", .name = "link", .tag = .boolean },
    },
};

pub const Rename: Endpoint = .{
    .path = "/containers/{f}/rename",
    .query = &.{
        .{ .field = "name", .name = "name", .tag = .string },
    },
};

pub const Pause: Endpoint = .{
    .path = "/containers/{f}/pause",
};

pub const Prune: Endpoint = .{
    .path = "/containers/prune",
    .query = &.{
        .{ .field = "filters", .name = "filters", .tag = .string },
    },
};

pub const Get: Endpoint = .{
    .path = "/containers/{f}/json",
};

pub const Create: Endpoint = .{
    .path = "/containers/create",
};

pub const Stop: Endpoint = .{
    .path = "/containers/{f}/stop",
    .query = &.{
        .{ .field = "signal", .name = "signal", .tag = .string },
        .{ .field = "timeout_signal", .name = "t", .tag = .int },
    },
};

pub const Unpause: Endpoint = .{
    .path = "/containers/{f}/unpause",
};

pub const Kill: Endpoint = .{
    .path = "/containers/{f}/kill",
    .query = &.{
        .{ .field = "signal", .name = "signal", .tag = .string },
    },
};
