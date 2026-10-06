const std = @import("std");
const dockerApiModel = @import("../../engine/generated/models.zig");

pub const CleanupError = struct {
    kind: enum { container, network },
    id: []const u8,
    operation: enum { stop, remove },
    err: anyerror,
};

pub const Report = struct {
    arena: std.heap.ArenaAllocator,
    failure: ?anyerror = null,
    cleanup_errors: std.ArrayList(CleanupError) = .empty,

    created_containers: std.ArrayList(std.json.Parsed(dockerApiModel.ContainerCreateResponse)) = .empty,
    created_networks: std.ArrayList(std.json.Parsed(dockerApiModel.NetworkCreateResponse)) = .empty,

    pub fn deinit(self: *Report) void {
        for (self.created_containers.items) |container| container.deinit();
        for (self.created_networks.items) |network| network.deinit();

        self.arena.deinit();
        self.* = undefined;
    }

    pub fn record(self: *Report, issue: CleanupError) void {
        if (self.failure == null) self.failure = issue.err;

        self.cleanup_errors.appendAssumeCapacity(issue);
    }
};
