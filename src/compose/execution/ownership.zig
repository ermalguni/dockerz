const std = @import("std");

const Value = std.json.Value;
const Allocator = std.mem.Allocator;

pub const managed_label = "io.dockerz.managed";
pub const project_label = "com.docker.compose.project";
pub const service_label = "com.docker.compose.service";
pub const network_label = "com.docker.compose.network";
pub const hash_label = "com.dockerz.config-hash";

pub fn stringField(value: Value, key: []const u8) ?[]const u8 {
    if (value != .object) return null;

    const field = value.object.get(key) orelse return null;

    return if (field == .string) field.string else null;
}

pub fn eq(actual: ?[]const u8, expected: []const u8) bool {
    return std.mem.eql(u8, actual orelse return false, expected);
}

pub fn labelIs(
    value: ?Value,
    key: []const u8,
    expected: []const u8,
) bool {
    return eq(stringField(value orelse return false, key), expected);
}

pub fn isOwned(
    value: ?Value,
    project: []const u8,
    kind: []const u8,
) bool {
    return labelIs(value, managed_label, "true") and labelIs(value, project_label, project) and (stringField(value.?, kind) orelse return false).len != 0;
}

pub fn setLabels(
    a: Allocator,
    project: []const u8,
    kind: []const u8,
    name: []const u8,
    hash: []const u8,
) !Value {
    var result: Value = .{ .object = .empty };

    try result.object.put(a, managed_label, .{ .string = "true" });
    try result.object.put(a, project_label, .{ .string = project });
    try result.object.put(a, kind, .{ .string = name });
    try result.object.put(a, hash_label, .{ .string = hash });

    return result;
}

test "ownership rejects other projects and resource kinds" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var value = try setLabels(
        a,
        "demo",
        network_label,
        "default",
        "hash",
    );

    try std.testing.expect(isOwned(value, "demo", network_label));
    try std.testing.expect(labelIs(value, network_label, "default"));
    try std.testing.expect(!isOwned(value, "other", network_label));
    try std.testing.expect(!isOwned(value, "demo", service_label));

    try value.object.put(a, managed_label, .{ .string = "false" });

    try std.testing.expect(!isOwned(value, "demo", network_label));
}
