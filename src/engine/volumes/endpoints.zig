const Endpoint = @import("../http.zig").Endpoint;

pub const List: Endpoint = .{
    .path = "/volumes",
    .query = &.{
        .{ .field = "filters", .name = "filters", .tag = .string },
    },
};

pub const Get: Endpoint = .{
    .path = "/volumes/{f}",
};

pub const Create: Endpoint = .{
    .path = "/volumes/create",
};

pub const Update: Endpoint = .{
    .path = "/volumes/{f}",
    .query = &.{
        .{ .field = "version", .name = "version", .tag = .int },
    },
};

pub const Remove: Endpoint = .{
    .path = "/volumes/{f}",
    .query = &.{
        .{ .field = "force", .name = "force", .tag = .boolean },
    },
};

pub const Prune: Endpoint = .{
    .path = "/volumes/prune",
    .query = &.{
        .{ .field = "filters", .name = "filters", .tag = .string },
    },
};
