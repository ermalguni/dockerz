const std = @import("std");
const Yaml = @import("yaml").Yaml;
const model = @import("../model.zig");

const scalar = @import("yaml.zig").scalar;
const mappingOrEmpty = @import("yaml.zig").mappingOrEmpty;
const boolean = @import("yaml.zig").boolean;
const checkFields = @import("yaml.zig").checkFields;
const parseStrings = @import("yaml.zig").parseStrings;

pub fn parseNetwork(
    allocator: std.mem.Allocator,
    project_name: []const u8,
    key: []const u8,
    value: Yaml.Value,
) !model.Network {
    const map = try mappingOrEmpty(value);

    try checkFields(
        map,
        &.{
            "name",
            "driver",
            "internal",
            "external",
        },
    );

    const external = if (map.get("external")) |v|
        try boolean(v)
    else
        false;

    if (external and (map.contains("driver") or map.contains("internal"))) {
        return error.InvalidExternalNetwork;
    }

    const engine_name = if (map.get("name")) |val|
        try allocator.dupe(u8, try scalar(val))
    else if (external)
        try allocator.dupe(u8, key)
    else
        try std.fmt.allocPrint(
            allocator,
            "{s}_{s}",
            .{ project_name, key },
        );

    return .{
        .key = try allocator.dupe(u8, key),
        .engine_name = engine_name,
        .configuration = .{
            .managed = .{
                .driver = if (map.get("driver")) |val|
                    try allocator.dupe(u8, try scalar(val))
                else
                    "bridge",
                .internal = if (map.get("internal")) |val|
                    try boolean(val)
                else
                    false,
            },
        },
    };
}

pub fn findNetworkIndex(
    networks: []const model.Network,
    network_to_find: []const u8,
) ?usize {
    for (networks, 0..) |network, index| {
        if (std.mem.eql(u8, network.key, network_to_find)) return index;
    }

    return null;
}

fn usesDefaultNetwork(
    value: ?Yaml.Value,
) !bool {
    const v = value orelse return true;

    if (v == .null) return true;
    if (v.asList()) |list| return list.len == 0;
    if (v.asMap()) |map| return map.count() == 0;

    return error.InvalidServiceNetworks;
}

pub fn referencesDefaultNetwork(value: ?Yaml.Value) !bool {
    if (try usesDefaultNetwork(value)) return true;

    const v = value.?;

    if (v.asMap()) |map| return map.contains("default");

    for (v.asList().?) |item| {
        if (std.mem.eql(u8, try scalar(item), "default")) return true;
    }

    return false;
}

pub fn parseNetworkAttachments(
    allocator: std.mem.Allocator,
    value: ?Yaml.Value,
    networks: []const model.Network,
) ![]const model.NetworkAttachment {
    if (try usesDefaultNetwork(value)) {
        const result = try allocator.alloc(model.NetworkAttachment, 1);

        result[0] = .{
            .network_index = findNetworkIndex(networks, "default") orelse return error.UnknownEroor,
        };

        return result;
    }

    const v = value.?;

    if (v.asList()) |list| {
        const result = try allocator.alloc(model.NetworkAttachment, list.len);

        for (list, 0..) |item, index| {
            result[index] = .{
                .network_index = findNetworkIndex(networks, try scalar(item)) orelse return error.UnknownError,
            };
        }

        return result;
    }

    const map = v.asMap() orelse return error.InvalidServiceNetowks;
    const result = try allocator.alloc(model.NetworkAttachment, map.count());
    var map_iterator = map.iterator();
    var index: usize = 0;

    while (map_iterator.next()) |entry| {
        const attachment = try mappingOrEmpty(entry.value_ptr.*);
        try checkFields(attachment, &.{"aliases"});

        result[index] = .{
            .network_index = findNetworkIndex(networks, entry.key_ptr.*) orelse return error.UnknownNetowkr,
            .aliases = if (attachment.get("aliases")) |aliases|
                try parseStrings(allocator, aliases)
            else
                &.{},
        };

        index += 1;
    }

    return result;
}
