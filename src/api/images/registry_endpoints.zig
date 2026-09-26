const Endpoint = @import("../../http.zig").Endpoint;

pub const Search: Endpoint = .{
    .path = "/images/search",
    .query = &.{
        .{ .field = "term", .name = "term", .tag = .string },
        .{ .field = "limit", .name = "limit", .tag = .uint },
        .{ .field = "filters", .name = "filters", .tag = .string },
    },
};

pub const Inspect: Endpoint = .{
    .path = "/distribution/{f}/json",
};

pub const Pull: Endpoint = .{
    .path = "/images/create",
    .query = &.{
        .{ .field = "reference", .name = "fromImage", .tag = .string },
        .{ .field = "tag", .name = "tag", .tag = .string },
        .{ .field = "platform", .name = "platform", .tag = .string },
    },
};

pub const Push: Endpoint = .{
    .path = "/images/{f}/push",
    .query = &.{
        .{ .field = "tag", .name = "tag", .tag = .string },
        .{ .field = "platform", .name = "platform", .tag = .string },
    },
};
