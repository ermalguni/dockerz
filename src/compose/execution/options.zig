const registry = @import("../../engine/images/registry.zig");
const containers = @import("../../engine/containers/root.zig");

pub const Options = struct {
    auth: registry.Auth = .{},
    stop: containers.StopOptions = .{},
};
