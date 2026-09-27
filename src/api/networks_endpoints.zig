const Endpoint = @import("../http.zig").Endpoint;

pub const List: Endpoint = .{
    .path = "/networks",
    .query = &.{
        .{ .field = "filters", .name = "filters", .tag = .string },
    },
};

pub const Get: Endpoint = .{
    .path = "/networks/{f}",
    .query = &.{
        .{ .field = "verbose", .name = "verbose", .tag = .boolean },
        .{ .field = "scope", .name = "scope", .tag = .string },
    },
};

pub const Create: Endpoint = .{
    .path = "/networks/create",
};

pub const Remove: Endpoint = .{
    .path = "/networks/{f}",
};

pub const Connect: Endpoint = .{
    .path = "/networks/{f}/connect",
};

pub const Disconnect: Endpoint = .{
    .path = "/networks/{f}/disconnect",
};

pub const Prune: Endpoint = .{
    .path = "/networks/prune",
    .query = &.{
        .{ .field = "filters", .name = "filters", .tag = .string },
    },
};
