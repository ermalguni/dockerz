const std = @import("std");
const Yaml = @import("yaml").Yaml;
const model = @import("../model.zig");
const interpolation = @import("interpolation.zig");

const scalar = @import("yaml.zig").scalar;
const checkFields = @import("yaml.zig").checkFields;
const parseStrings = @import("yaml.zig").parseStrings;

const parseNetworkAttachments = @import("networks.zig").parseNetworkAttachments;

fn parseEnvironment(
    arena: std.mem.Allocator,
    value: Yaml.Value,
) ![]model.EnvironmentEntry {
    if (value == .null) return &.{};

    if (value.asMap()) |map| {
        const entries = try arena.alloc(
            model.EnvironmentEntry,
            map.count(),
        );

        var iterator = map.iterator();
        var index: usize = 0;

        while (iterator.next()) |entry| {
            const raw_value = entry.value_ptr.*;

            entries[index] = .{
                .name = try arena.dupe(u8, entry.key_ptr.*),
                .value = if (raw_value == .null)
                    null
                else
                    try arena.dupe(
                        u8,
                        raw_value.asScalar() orelse return error.InvalidEnvironmentVariable,
                    ),
            };

            index += 1;
        }

        return entries;
    }

    if (value.asList()) |list| {
        const entries = try arena.alloc(model.EnvironmentEntry, list.len);

        for (list, 0..) |item, index| {
            const text = item.asScalar() orelse return error.InvalidEnvironmentEntry;

            if (std.mem.indexOfScalar(u8, text, '=')) |separator| {
                entries[index] = .{
                    .name = try arena.dupe(u8, text[0..separator]),
                    .value = try arena.dupe(u8, text[separator + 1 ..]),
                };
            } else {
                entries[index] = .{
                    .name = try arena.dupe(u8, text),
                    .value = null,
                };
            }
        }

        return entries;
    }

    return error.InvalidEnvironment;
}

pub fn parseService(
    allocator: std.mem.Allocator,
    name: []const u8,
    value: Yaml.Value,
    networks: []model.Network,
) !model.Service {
    const map = value.asMap() orelse return error.ExpectedMapping;

    try checkFields(
        map,
        &.{
            "image",
            "command",
            "network",
            "environment",
            "networks",
        },
    );

    return .{
        .name = try allocator.dupe(u8, name),
        .image = try allocator.dupe(u8, try scalar(
            map.get("image") orelse return error.MissingImage,
        )),
        .command = if (map.get("command")) |v|
            try parseCommand(allocator, v)
        else
            null,
        .environment = if (map.get("environment")) |v|
            try parseEnvironment(allocator, v)
        else
            &.{},
        .networks = try parseNetworkAttachments(
            allocator,
            map.get("networks"),
            networks,
        ),
    };
}

fn parseCommand(
    allocator: std.mem.Allocator,
    value: Yaml.Value,
) !?[]const []const u8 {
    if (value == .null) return null;

    if (value.asScalar()) |text| {
        return try interpolation.splitCommand(allocator, text);
    }

    return try parseStrings(allocator, value);
}
