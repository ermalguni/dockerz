const std = @import("std");
const Yaml = @import("yaml").Yaml;

pub fn scalar(value: Yaml.Value) ![]const u8 {
    return value.asScalar() orelse return error.ExpectedScalar;
}

pub fn mappingOrEmpty(value: Yaml.Value) !Yaml.Map {
    if (value == .null) return .{};

    return value.asMap() orelse error.ExpectedMapping;
}

pub fn boolean(value: Yaml.Value) !bool {
    const text_value = try scalar(value);

    if (std.ascii.eqlIgnoreCase(text_value, "true")) return true;
    if (std.ascii.eqlIgnoreCase(text_value, "false")) return false;

    return error.ExpectedBoolean;
}

pub fn parseStrings(
    allocator: std.mem.Allocator,
    value: Yaml.Value,
) ![]const []const u8 {
    const list = value.asList() orelse return error.ExpectedList;
    const result = try allocator.alloc([]u8, list.len);

    for (list, 0..) |item, index| {
        result[index] = try allocator.dupe(
            u8,
            try scalar(item),
        );
    }

    return result;
}

pub fn checkFields(
    map: Yaml.Map,
    allowed: []const []const u8,
) !void {
    var iterator = map.iterator();

    while (iterator.next()) |entry| {
        const key = entry.key_ptr.*;

        if (std.mem.startsWith(u8, key, "x-")) continue;

        for (allowed) |field| {
            if (std.mem.eql(u8, key, field)) break;
        } else {
            return error.UnsupportedComposeField;
        }
    }
}
