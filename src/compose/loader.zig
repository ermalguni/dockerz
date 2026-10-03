const std = @import("std");
const Yaml = @import("yaml").Yaml;
const model = @import("model.zig");
const interpolation = @import("interpolation.zig");

pub const Options = struct {
    name: ?[]const u8 = null,
    fallback_name: ?[]const u8 = null,
};

pub fn load(
    gpa: std.mem.Allocator,
    source: []const u8,
    options: Options,
) !model.LoadedProject {
    const allowed_fields: []const []const u8 = &.{
        "name",
        "services",
        "networks",
        "version",
    };

    var arena = std.heap.ArenaAllocator.init(gpa);
    errdefer arena.deinit();
    const allocator = arena.allocator();

    var yaml: Yaml = .{ .source = source };
    defer yaml.deinit(allocator);
    try yaml.load(allocator);

    if (yaml.docs.items.len != 1) return error.ExpectedOneDocument;

    const root = yaml.docs.items[0].asMap() orelse return error.ExpectedMapping;

    try checkFields(root, allowed_fields);

    // the version field is discardable
    if (root.get("version")) |value| _ = try scalar(value);

    // project name
    const declared_name = if (root.getEntry("name")) |value|
        try scalar(value.value_ptr.*)
    else
        null;

    const name = try allocator.dupe(u8, options.name orelse declared_name orelse options.fallback_name orelse return error.MissingProjectName);

    if (!model.isValidProjectName(name)) return error.InvalidProjectName;

    // network handling
    const network_declarations = try mappingOrEmpty(
        root.get("networks") orelse .null,
    );
    var networks = try std.ArrayList(model.Network).initCapacity(allocator, network_declarations.count() + 1);
    var network_iterator = network_declarations.iterator();

    while (network_iterator.next()) |entry| {
        networks.appendAssumeCapacity(
            try parseNetwork(
                allocator,
                name,
                entry.key_ptr.*,
                entry.value_ptr.*,
            ),
        );
    }

    // services
    const services_map = (root.get("services") orelse return error.MissingServices).asMap() orelse return error.ExpectedMap;
    const services = try allocator.alloc(
        model.Service,
        services_map.count(),
    );

    var needs_default = false;
    var service_iterator = services_map.iterator();

    while (service_iterator.next()) |entry| {
        const service = entry.value_ptr.asMap() orelse return error.ExpectedServiceMapping;

        if (try referencesDefaultNetwork(service.get("networks"))) {
            needs_default = true;
        }
    }

    if (needs_default and findNetworkIndex(networks.items, "default") == null) {
        networks.appendAssumeCapacity(
            try parseNetwork(
                allocator,
                name,
                "default",
                .null,
            ),
        );
    }

    service_iterator = services_map.iterator();
    var service_index: usize = 0;

    while (service_iterator.next()) |entry| {
        services[service_index] = try parseService(
            allocator,
            entry.key_ptr.*,
            entry.value_ptr.*,
            networks.items,
        );
        service_index += 1;
    }

    const project: model.Project = .{
        .name = name,
        .services = services,
        .networks = networks.items,
    };

    try project.validate();

    return .{
        .arena = arena,
        .value = project,
    };
}

fn scalar(value: Yaml.Value) ![]const u8 {
    return value.asScalar() orelse return error.ExpectedScalar;
}

fn mappingOrEmpty(value: Yaml.Value) !Yaml.Map {
    if (value == .null) return .{};

    return value.asMap() orelse error.ExpectedMapping;
}

fn boolean(value: Yaml.Value) !bool {
    const text_value = try scalar(value);

    if (std.ascii.eqlIgnoreCase(text_value, "true")) return true;
    if (std.ascii.eqlIgnoreCase(text_value, "false")) return false;

    return error.ExpectedBoolean;
}

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

fn checkFields(
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

fn parseNetwork(
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

fn parseService(
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

fn parseStrings(
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

fn findNetworkIndex(
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

fn referencesDefaultNetwork(value: ?Yaml.Value) !bool {
    if (try usesDefaultNetwork(value)) return true;

    const v = value.?;

    if (v.asMap()) |map| return map.contains("default");

    for (v.asList().?) |item| {
        if (std.mem.eql(u8, try scalar(item), "default")) return true;
    }

    return false;
}

fn parseNetworkAttachments(
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

test "explicit default resolves before implicit user and owns source data" {
    const allocator = std.testing.allocator;

    const source = try allocator.dupe(u8,
        \\name: demo
        \\services:
        \\  explicit:
        \\    image: nginx
        \\    networks: [default]
        \\  implicit:
        \\    image: busybox
    );

    var loaded = load(allocator, source, .{}) catch |err| {
        allocator.free(source);
        return err;
    };
    allocator.free(source);
    defer loaded.deinit();

    const project = loaded.value;

    try std.testing.expectEqualStrings("demo", project.name);
    try std.testing.expectEqualStrings(
        "explicit",
        project.services[0].name,
    );
    try std.testing.expectEqualStrings(
        "nginx",
        project.services[0].image,
    );

    const explicit = project.services[0].networks[0].network_index;
    const implicit = project.services[1].networks[0].network_index;

    try std.testing.expectEqual(explicit, implicit);
    try std.testing.expectEqualStrings(
        "default",
        project.networks[explicit].key,
    );
    try std.testing.expectEqualStrings(
        "demo_default",
        project.networks[explicit].engine_name,
    );
}
