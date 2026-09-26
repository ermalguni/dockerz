const Endpoint = @import("../http.zig").Endpoint;

pub const List: Endpoint = .{
    .path = "/images/json",
    .query = &.{
        .{ .field = "all", .name = "all", .tag = .boolean },
        .{ .field = "filters", .name = "filters", .tag = .string },
        .{ .field = "shared_size", .name = "shared-size", .tag = .boolean },
        .{ .field = "digests", .name = "digests", .tag = .boolean },
    },
};

pub const Get: Endpoint = .{
    .path = "/images/{f}/json",
};

pub const History: Endpoint = .{
    .path = "/images/{f}/history",
};

pub const Tag: Endpoint = .{
    .path = "/images/{f}/tag",
    .query = &.{
        .{ .field = "repo", .name = "repo", .tag = .string },
        .{ .field = "tag", .name = "tag", .tag = .string },
    },
};

pub const Remove: Endpoint = .{
    .path = "/images/{f}",
    .query = &.{
        .{ .field = "force", .name = "force", .tag = .boolean },
        .{ .field = "no_prune", .name = "noprune", .tag = .boolean },
    },
};

pub const Prune: Endpoint = .{
    .path = "/images/prune",
    .query = &.{
        .{ .field = "filters", .name = "filters", .tag = .string },
    },
};
