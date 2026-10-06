const Endpoint = @import("../http.zig").Endpoint;

pub const Ping: Endpoint = .{
    .path = "/_ping",
};

pub const PingHead: Endpoint = .{
    .path = "/_ping",
};

pub const Version: Endpoint = .{
    .path = "/version",
};

pub const Info: Endpoint = .{
    .path = "/info",
};

pub const Auth: Endpoint = .{
    .path = "/auth",
};

pub const Events: Endpoint = .{
    .path = "/events",
    .query = &.{
        .{ .field = "since", .name = "since", .tag = .string },
        .{ .field = "until", .name = "until", .tag = .string },
        .{ .field = "filters", .name = "filters", .tag = .string },
    },
};

pub const DiskUsage: Endpoint = .{
    .path = "/system/df",
    .query = &.{
        .{ .field = "types", .name = "type", .tag = .strings },
        .{ .field = "verbose", .name = "verbose", .tag = .boolean },
    },
};
