const std = @import("std");
const Yaml = @import("yaml");
const composeModel = @import("../model.zig");
const dockerApiModel = @import("../../engine/generated/models.zig");
const eq = @import("ownership.zig").eq;
const stringField = @import("ownership.zig").stringField;

const Allocator = std.mem.Allocator;
const Value = std.json.Value;

pub const NetworkPlan = struct {
    id: ?[]const u8,
    labels: ?Value,
};

const NetworkAttachment = struct {
    name: []const u8,
    key: []const u8,
    external: bool,
    aliases: []const []const u8,
};

pub fn digest(a: Allocator, value: anytype) ![]const u8 {
    const canonical = try std.json.Stringify.valueAlloc(
        a,
        .{ "dockerz-config-v1", value },
        .{},
    );

    var hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(canonical, &hash, .{});

    return std.fmt.allocPrint(a, "v1:{s}", .{
        std.fmt.bytesToHex(hash, .lower),
    });
}

pub fn lessString(_: void, left: []const u8, right: []const u8) bool {
    return std.mem.lessThan(u8, left, right);
}

pub fn lessNetworkAttachment(_: void, left: NetworkAttachment, right: NetworkAttachment) bool {
    return lessString({}, left.name, right.name);
}

pub fn environment(
    a: Allocator,
    envs: []const composeModel.EnvironmentEntry,
) ![]const []const u8 {
    const sorted = try a.dupe(composeModel.EnvironmentEntry, envs);

    std.mem.sort(composeModel.EnvironmentEntry, sorted, {}, struct {
        fn less(
            _: void,
            left: composeModel.EnvironmentEntry,
            right: composeModel.EnvironmentEntry,
        ) bool {
            return lessString({}, left.name, right.name);
        }
    }.less);

    const result = try a.alloc([]const u8, sorted.len);

    for (sorted, result) |env, *text| {
        text.* = if (env.value) |value|
            try std.fmt.allocPrint(a, "{s}={s}", .{ env.name, value })
        else
            env.name;
    }

    return result;
}

pub fn hasAlias(
    endpoint: Value,
    alias: []const u8,
) bool {
    if (endpoint != .object) return false;

    const aliases = endpoint.object.get("Aliases") orelse return false;
    if (aliases != .array) return false;

    for (aliases.array.items) |value| {
        if (value == .string and std.mem.eql(u8, value.string, alias))
            return true;
    }

    return false;
}

pub fn checkAttachments(
    value: dockerApiModel.ContainerInspectResponse,
    service: composeModel.Service,
    project: composeModel.Project,
    networks: []const NetworkPlan,
) !void {
    const settings = value.NetworkSettings orelse
        return error.ConfigurationChanged;
    const attached = settings.Networks orelse
        return error.ConfigurationChanged;

    if (attached != .object or
        attached.object.count() != service.networks.len)
    {
        return error.ConfigurationChanged;
    }

    for (service.networks) |attachment| {
        const index = attachment.network_index;

        const endpoint = attached.object.get(
            project.networks[index].engine_name,
        ) orelse return error.ConfigurationChanged;

        const id = networks[index].id orelse
            return error.ConfigurationChanged;

        if (!eq(stringField(endpoint, "NetworkID"), id) or
            !hasAlias(endpoint, service.name))
        {
            return error.ConfigurationChanged;
        }

        for (attachment.aliases) |alias| {
            if (!hasAlias(endpoint, alias))
                return error.ConfigurationChanged;
        }
    }
}

pub fn canonicalAttachments(
    a: Allocator,
    service: composeModel.Service,
    networks: []const composeModel.Network,
) ![]NetworkAttachment {
    const result = try a.alloc(NetworkAttachment, service.networks.len);

    for (service.networks, result) |attachment, *canonical| {
        const network = networks[attachment.network_index];

        const aliases = try a.alloc(
            []const u8,
            attachment.aliases.len + 1,
        );
        aliases[0] = service.name;
        @memcpy(aliases[1..], attachment.aliases);

        std.mem.sort([]const u8, aliases, {}, lessString);

        var count: usize = 0;
        for (aliases) |alias| {
            if (count == 0 or
                !std.mem.eql(u8, aliases[count - 1], alias))
            {
                aliases[count] = alias;
                count += 1;
            }
        }

        canonical.* = .{
            .name = network.engine_name,
            .key = network.key,
            .external = network.configuration == .external,
            .aliases = aliases[0..count],
        };
    }

    std.mem.sort(NetworkAttachment, result, {}, lessNetworkAttachment);
    return result;
}

test "environment identity ignores ordering but distinguishes bare keys from empty values" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const entries = [_]composeModel.EnvironmentEntry{
        .{ .name = "Z", .value = "" },
        .{ .name = "A", .value = null },
    };
    const reordered = [_]composeModel.EnvironmentEntry{
        entries[1],
        entries[0],
    };

    const first = try environment(a, &entries);
    const second = try environment(a, &reordered);

    try std.testing.expectEqualStrings("A", first[0]);
    try std.testing.expectEqualStrings("Z=", first[1]);

    try std.testing.expectEqualStrings(
        try digest(a, first),
        try digest(a, second),
    );

    const changed = try environment(a, &.{
        .{ .name = "A", .value = "" },
        entries[0],
    });

    try std.testing.expect(!std.mem.eql(
        u8,
        try digest(a, first),
        try digest(a, changed),
    ));
}

test "attachment identity uses names not project indices and normalizes aliases" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const front: composeModel.Network = .{
        .key = "front",
        .engine_name = "p-front",
        .configuration = .{ .managed = .{} },
    };
    const back: composeModel.Network = .{
        .key = "back",
        .engine_name = "shared",
        .configuration = .external,
    };

    var service: composeModel.Service = .{
        .name = "web",
        .image = "alpine",
        .networks = &.{
            .{
                .network_index = 0,
                .aliases = &.{ "www", "web", "www" },
            },
            .{ .network_index = 1 },
        },
    };

    const first = try canonicalAttachments(
        a,
        service,
        &.{ front, back },
    );

    service.networks = &.{
        .{ .network_index = 0 },
        .{ .network_index = 1, .aliases = &.{"www"} },
    };

    const second = try canonicalAttachments(
        a,
        service,
        &.{ back, front },
    );

    try std.testing.expectEqualStrings(
        try digest(a, first),
        try digest(a, second),
    );

    service.networks = &.{
        .{ .network_index = 0 },
        .{ .network_index = 1, .aliases = &.{"other"} },
    };

    const changed = try canonicalAttachments(
        a,
        service,
        &.{ back, front },
    );

    try std.testing.expect(!std.mem.eql(
        u8,
        try digest(a, first),
        try digest(a, changed),
    ));
}
