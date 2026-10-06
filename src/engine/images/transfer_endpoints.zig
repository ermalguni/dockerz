const Endpoint = @import("../http.zig").Endpoint;

pub const Save: Endpoint = .{
    .path = "/images/{f}/get",
    .query = &.{
        .{ .field = "platforms", .name = "platform", .tag = .strings },
    },
};

pub const SaveMany: Endpoint = .{
    .path = "/images/get",
    .query = &.{
        .{ .field = "names", .name = "name", .tag = .strings },
        .{ .field = "platforms", .name = "platform", .tag = .strings },
    },
};
