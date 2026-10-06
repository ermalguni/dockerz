const Endpoint = @import("../http.zig").Endpoint;

pub const List: Endpoint = .{
    .path = "/images/json",
    .query = &.{
        .{ .field = "all", .name = "all", .tag = .boolean },
        .{ .field = "filters", .name = "filters", .tag = .string },
        .{ .field = "shared_size", .name = "shared-size", .tag = .boolean },
        .{ .field = "digests", .name = "digests", .tag = .boolean },
        .{ .field = "manifests", .name = "manifests", .tag = .boolean },
        .{ .field = "identity", .name = "identity", .tag = .boolean },
    },
};

pub const Get: Endpoint = .{
    .path = "/images/{f}/json",
    .query = &.{
        .{ .field = "manifests", .name = "manifests", .tag = .boolean },
        .{ .field = "platform", .name = "platform", .tag = .string },
    },
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

pub const Commit: Endpoint = .{
    .path = "/commit",
    .query = &.{
        .{ .field = "container", .name = "container", .tag = .string },
        .{ .field = "repo", .name = "repo", .tag = .string },
        .{ .field = "tag", .name = "tag", .tag = .string },
        .{ .field = "comment", .name = "comment", .tag = .string },
        .{ .field = "author", .name = "author", .tag = .string },
        .{ .field = "pause", .name = "pause", .tag = .boolean },
        .{ .field = "changes", .name = "changes", .tag = .string },
    },
};

pub const Attestations: Endpoint = .{
    .path = "/images/{f}/attestations",
    .query = &.{
        .{ .field = "platform", .name = "platform", .tag = .string },
        .{ .field = "predicate_types", .name = "type", .tag = .strings },
        .{ .field = "include_statement", .name = "statement", .tag = .boolean },
    },
};
