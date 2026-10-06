const Endpoint = @import("../http.zig").Endpoint;

pub const Build: Endpoint = .{
    .path = "/build",
    .query = &.{
        .{ .field = "version", .name = "version", .tag = .string },
        .{ .field = "dockerfile", .name = "dockerfile", .tag = .string },
        .{ .field = "extra_hosts", .name = "extrahosts", .tag = .string },
        .{ .field = "quiet", .name = "q", .tag = .boolean },
        .{ .field = "no_cache", .name = "nocache", .tag = .boolean },
        .{ .field = "cache_from", .name = "cachefrom", .tag = .string },
        .{ .field = "pull", .name = "pull", .tag = .boolean },
        .{ .field = "remove_intermediate", .name = "rm", .tag = .boolean },
        .{ .field = "force_remove", .name = "forcerm", .tag = .boolean },
        .{ .field = "memory", .name = "memory", .tag = .int },
        .{ .field = "memory_swap", .name = "memswap", .tag = .int },
        .{ .field = "cpu_shares", .name = "cpushares", .tag = .int },
        .{ .field = "cpu_set", .name = "cpusetcpus", .tag = .string },
        .{ .field = "cpu_period", .name = "cpuperiod", .tag = .int },
        .{ .field = "cpu_quota", .name = "cpuquota", .tag = .int },
        .{ .field = "build_args", .name = "buildargs", .tag = .string },
        .{ .field = "shm_size", .name = "shmsize", .tag = .int },
        .{ .field = "squash", .name = "squash", .tag = .boolean },
        .{ .field = "labels", .name = "labels", .tag = .string },
        .{ .field = "network_mode", .name = "networkmode", .tag = .string },
        .{ .field = "platform", .name = "platform", .tag = .string },
        .{ .field = "target", .name = "target", .tag = .string },
        .{ .field = "outputs", .name = "outputs", .tag = .string },
        .{ .field = "tags", .name = "t", .tag = .strings },
    },
};

pub const Prune: Endpoint = .{
    .path = "/build/prune",
    .query = &.{
        .{ .field = "all", .name = "all", .tag = .boolean },
        .{ .field = "filters", .name = "filters", .tag = .string },
        .{ .field = "reserved_space", .name = "reserved-space", .tag = .int },
        .{ .field = "max_used_space", .name = "max-used-space", .tag = .int },
        .{ .field = "min_free_space", .name = "min-free-space", .tag = .int },
    },
};
