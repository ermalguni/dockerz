const std = @import("std");

const Yaml = @import("yaml").Yaml;

const model = @import("../model.zig");
const checkFields = @import("yaml.zig").checkFields;
const findNetworkIndex = @import("networks.zig").findNetworkIndex;
const mappingOrEmpty = @import("yaml.zig").mappingOrEmpty;
const parseNetwork = @import("networks.zig").parseNetwork;
const parseService = @import("services.zig").parseService;
const referencesDefaultNetwork = @import("networks.zig").referencesDefaultNetwork;
const scalar = @import("yaml.zig").scalar;

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
