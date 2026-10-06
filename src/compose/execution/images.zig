const std = @import("std");
const Options = @import("options.zig").Options;
const Client = @import("../../engine/client.zig").Client;
const registry = @import("../../engine/images/registry.zig");

const Allocator = std.mem.Allocator;

fn resolveImage(
    client: *Client,
    a: Allocator,
    reference: []const u8,
    options: Options,
) ![]const u8 {
    const inspected = client.images().local().get(
        reference,
        .{},
    ) catch |err| blk: {
        if (err != error.NotFound) return err;

        // An omitted tag means all tags to Engine.
        // For an untagged Compose reference, request latest.
        var repository = reference;
        var tag: ?[]const u8 = null;

        if (std.mem.lastIndexOfScalar(u8, reference, '@')) |at| {
            repository = reference[0..at];
            tag = reference[at + 1 ..];
        } else {
            const slash = std.mem.lastIndexOfScalar(
                u8,
                reference,
                '/',
            );
            const colon = std.mem.lastIndexOfScalar(
                u8,
                reference,
                ':',
            );

            if (colon != null and
                (slash == null or colon.? > slash.?))
            {
                repository = reference[0..colon.?];
                tag = reference[colon.? + 1 ..];
            } else {
                tag = "latest";
            }
        }

        try client.images().registry().pull(
            repository,
            .{
                .tag = tag,
                .auth = options.auth,
            },
            QuietProgress{},
        );

        break :blk try client.images().local().get(
            reference,
            .{},
        );
    };
    defer inspected.deinit();

    return a.dupe(
        u8,
        inspected.value.Id orelse return error.InvalidDaemonResponse,
    );
}

const QuietProgress = struct {
    pub fn onProgress(
        _: QuietProgress,
        _: registry.ProgressEvent,
    ) !void {}
};
