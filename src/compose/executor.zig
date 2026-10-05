const std = @import("std");
const Client = @import("../client.zig").Client;
const composeModel = @import("model.zig");
const dockerApiModel = @import("../generated/models.zig");
const containers = @import("../api/containers.zig");
const registry = @import("../api/images/registry.zig");

const Value = std.json.Value;
const Allocator = std.mem.Allocator;

const managed_label = "io.dockerz.managed";
const project_label = "com.docker.compose.project";
const service_label = "com.docker.compose.service";
const network_label = "com.docker.compose.network";
const hash_label = "com.dockerz.config-hash";

pub const Options = struct {
    auth: registry.Auth = .{},
    stop: containers.StopOptions = .{},
};

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

        self.cleanup_errors.?.appendAssumeCapacity(issue);
    }
};

const NetworkPlan = struct {
    id: ?[]const u8,
    labels: ?Value,
};

const ServicePlan = struct {
    name: []const u8,
    id: ?[]const u8,
    request: containers.ContainerCreateRequest,
};

const NetworkAttachment = struct {
    name: []const u8,
    key: []const u8,
    external: bool,
    aliases: []const []const u8,
};

pub const Executor = struct {
    client: *Client,

    pub fn up(
        self: Executor,
        project: composeModel.Project,
        options: Options,
    ) Report {
        var report: Report = .{
            .arena = .init(self.client.allocator),
        };

        self.apply(project, options, &report) catch |err| {
            report.failure = err;

            var index = report.created_containers.items.len;
            while (index > 0) {
                index -= 1;
                self.removeContainer(
                    report.created_containers.items[index].value.Id,
                    options,
                    &report,
                );
            }

            index = report.created_networks.items.len;
            while (index > 0) {
                index -= 1;
                self.removeNetwork(
                    report.created_networks.items[index].value.Id,
                    &report,
                );
            }
        };

        return report;
    }

    pub fn down(
        self: Executor,
        project_name: []const u8,
        options: Options,
    ) Report {
        var report: Report = .{
            .arena = .init(self.client.allocator),
        };

        self.destroy(project_name, options, &report) catch |err| {
            report.failure = err;
        };

        return report;
    }

    fn destroy(
        self: Executor,
        project_name: []const u8,
        options: Options,
        report: *Report,
    ) !void {
        if (!composeModel.isValidProjectName(project_name))
            return error.InvalidProjectName;

        const a = report.arena.allocator();

        const project_filter = try std.fmt.allocPrint(
            a,
            "{s}={s}",
            .{ project_label, project_name },
        );
        const filters = try std.json.Stringify.valueAlloc(
            a,
            .{
                .label = [_][]const u8{
                    managed_label ++ "=true",
                    project_filter,
                },
            },
            .{},
        );

        const container_list = try self.client.containers().list(.{
            .all = true,
            .filters = filters,
        });
        defer container_list.deinit();

        const network_list = try self.client.networks().list(.{
            .filters = filters,
        });
        defer network_list.deinit();

        const container_ids = try a.alloc(
            []const u8,
            container_list.value.len,
        );
        const network_ids = try a.alloc(
            []const u8,
            network_list.value.len,
        );

        var nc: usize = 0;
        var nn: usize = 0;

        for (container_list.value) |item| {
            if (!isOwned(item.Labels, project_name, service_label))
                continue;

            container_ids[nc] = try a.dupe(
                u8,
                item.Id orelse return error.InvalidDaemonResponse,
            );
            nc += 1;
        }

        for (network_list.value) |item| {
            if (!isOwned(item.Labels, project_name, network_label))
                continue;

            network_ids[nn] = try a.dupe(
                u8,
                item.Id orelse return error.InvalidDaemonResponse,
            );
            nn += 1;
        }

        try report.cleanup_errors.ensureTotalCapacity(a, nc + nn);

        for (container_ids[0..nc]) |id| {
            self.removeContainer(id, options, report);
        }

        for (network_ids[0..nn]) |id| {
            self.removeNetwork(id, report);
        }
    }

    fn apply(
        self: Executor,
        project: composeModel.Project,
        options: Options,
        report: *Report,
    ) !void {
        try project.validate();

        const a = report.arena.allocator();

        try report.cleanup_errors.ensureTotalCapacity(a, project.services.len + project.networks.len);
        try report.created_containers.ensureTotalCapacity(a, project.services.len);
        try report.created_networks.ensureTotalCapacity(a, project.networks.len);

        const networks = try a.alloc(NetworkPlan, project.networks.len);
        const services = try a.alloc(ServicePlan, project.services.len);

        for (project.networks, networks) |network, *plan| {
            plan.* = .{
                .id = null,
                .labels = null,
            };

            if (network.configuration == .managed) {
                const hash = try digest(a, .{
                    project.name,
                    network.key,
                    network.engine_name,
                    network.configuration.managed,
                });

                plan.labels = try setLabels(
                    a,
                    project.name,
                    network_label,
                    network.key,
                    hash,
                );
            }

            const existing_network = self.client.networks().get(
                network.engine_name,
                .{},
            ) catch |err| {
                if (err == error.NotFound) return err;

                if (network.configuration == .external) return error.ExternalNetworkNotFound;

                continue;
            };
            defer existing_network.deinit();

            const network_value = existing_network.value;

            if (!eq(network_value.Name, network.engine_name)) return error.NetworkNameCollision;

            if (network.configuration == .managed) {
                if (!isOwned(network_value.Labels, project.name, network_label) or !isOwned(network_value.Labels, network_label, network.key)) {
                    return error.NetworkNameCollision;
                }

                if (!labelIs(network_value.Labels, hash_label, stringField(plan.labels.?, hash_label).?) or
                    !eq(network_value.Driver, network.configuration.managed.driver) or (network_value.Internal orelse false) != network.configuration.managed.internal)
                {
                    return error.ConfigurationChanged;
                }
            }

            plan.id = try a.dupe(
                u8,
                network_value.Id orelse return error.InvalidDaemonResponse,
            );
        }

        // Check every existing service before creating project resources
        // or starting containers. Image pulls may populate Docker's cache.
        for (project.services, services) |service, *plan| {
            const image = try self.resolveImage(
                a,
                service.image,
                options,
            );
            const env = try environment(a, service.environment);
            const attachments = try canonicalAttachments(
                a,
                service,
                project.networks,
            );

            const hash = try digest(a, .{
                project.name,
                service.name,
                service.image,
                image,
                service.command,
                env,
                attachments,
            });

            var endpoints: Value = .{ .object = .{} };

            for (attachments) |attachment| {
                var endpoint: Value = .{ .object = .{} };
                var aliases: Value = .{
                    .array = std.json.Array.init(a),
                };

                for (attachment.aliases) |alias| {
                    try aliases.array.append(.{ .string = alias });
                }

                try endpoint.object.put(a, "Aliases", aliases);
                try endpoints.object.put(a, attachment.name, endpoint);
            }

            var host: Value = .{ .object = .{} };
            try host.object.put(
                a,
                "NetworkMode",
                .{ .string = attachments[0].name },
            );

            plan.* = .{
                .name = try std.fmt.allocPrint(
                    a,
                    "{s}-{s}-1",
                    .{ project.name, service.name },
                ),
                .id = null,
                .request = .{
                    .config = .{
                        .Image = image,
                        .Cmd = service.command,
                        .Env = env,
                        .Labels = try setLabels(
                            a,
                            project.name,
                            service_label,
                            service.name,
                            hash,
                        ),
                    },
                    .host_config = host,
                    .networking_config = .{
                        .EndpointsConfig = endpoints,
                    },
                },
            };

            const inspected = self.client.containers().get(
                plan.name,
            ) catch |err| {
                if (err == error.NotFound) continue;
                return err;
            };
            defer inspected.deinit();

            const value = inspected.value;
            const config = value.Config orelse
                return error.ContainerNameCollision;

            if (!isOwned(config.Labels, project.name, service_label) or
                !labelIs(config.Labels, service_label, service.name))
            {
                return error.ContainerNameCollision;
            }

            if (!labelIs(config.Labels, hash_label, hash) or
                !eq(value.Image, image))
            {
                return error.ConfigurationChanged;
            }

            try checkAttachments(value, service, project, networks);

            plan.id = try a.dupe(
                u8,
                value.Id orelse return error.InvalidDaemonResponse,
            );
        }

        for (project.networks, networks) |network, *plan| {
            if (plan.id != null) continue;

            const config = network.configuration.managed;
            const created = try self.client.networks().create(.{
                .Name = network.engine_name,
                .Driver = config.driver,
                .Internal = config.internal,
                .Labels = plan.labels,
            });

            report.created_networks.appendAssumeCapacity(created);
            plan.id = created.value.Id;
        }

        for (services) |*plan| {
            if (plan.id == null) {
                const created = try self.client.containers().create(
                    plan.request,
                    .{ .name = plan.name },
                );

                report.created_containers.appendAssumeCapacity(created);
                plan.id = created.value.Id;
            }
        }

        for (services) |plan| {
            try self.client.containers().start(plan.id.?, .{});
        }
    }

    fn resolveImage(
        self: Executor,
        a: Allocator,
        reference: []const u8,
        options: Options,
    ) ![]const u8 {
        const inspected = self.client.images().local().get(
            reference,
            .{},
        ) catch |err| blk: {
            if (err != error.NotFound) return err;

            // An omitted tag means all tags to Engine.
            // For an untagged Compose reference, request latest.
            var repository = reference;
            var tag: ?[]const u8 = null;

            if (std.mem.lastIndexOfScalar(u8, reference, '@')) |at| {
                repository = reference[0..at];
                tag = reference[at + 1 ..];
            } else {
                const slash = std.mem.lastIndexOfScalar(
                    u8,
                    reference,
                    '/',
                );
                const colon = std.mem.lastIndexOfScalar(
                    u8,
                    reference,
                    ':',
                );

                if (colon != null and
                    (slash == null or colon.? > slash.?))
                {
                    repository = reference[0..colon.?];
                    tag = reference[colon.? + 1 ..];
                } else {
                    tag = "latest";
                }
            }

            try self.client.images().registry().pull(
                repository,
                .{
                    .tag = tag,
                    .auth = options.auth,
                },
                QuietProgress{},
            );

            break :blk try self.client.images().local().get(
                reference,
                .{},
            );
        };
        defer inspected.deinit();

        return a.dupe(
            u8,
            inspected.value.Id orelse return error.InvalidDaemonResponse,
        );
    }

    fn removeContainer(
        self: Executor,
        id: []const u8,
        options: Options,
        report: *Report,
    ) void {
        self.client.containers().stop(id, options.stop) catch |err| {
            if (err == error.NotFound) return;

            report.record(.{
                .kind = .container,
                .id = id,
                .operation = .stop,
                .err = err,
            });

            // Never force-remove a container whose stop failed.
            return;
        };

        self.client.containers().remove(id, .{}) catch |err| {
            if (err != error.NotFound) {
                report.record(.{
                    .kind = .container,
                    .id = id,
                    .operation = .remove,
                    .err = err,
                });
            }
        };
    }

    fn removeNetwork(
        self: Executor,
        id: []const u8,
        report: *Report,
    ) void {
        self.client.networks().remove(id) catch |err| {
            if (err != error.NotFound) {
                report.record(.{
                    .kind = .network,
                    .id = id,
                    .operation = .remove,
                    .err = err,
                });
            }
        };
    }
};

const QuietProgress = struct {
    pub fn onProgress(
        _: QuietProgress,
        _: registry.ProgressEvent,
    ) !void {}
};

fn stringField(value: Value, key: []const u8) ?[]const u8 {
    if (value != .object) return null;

    const field = value.object.get(key) orelse return null;

    return if (field == .string) field.string else null;
}

fn eq(actual: ?[]const u8, expected: []const u8) bool {
    return std.mem.eql(u8, actual orelse return false, expected);
}

fn labelIs(
    value: ?Value,
    key: []const u8,
    expected: []const u8,
) bool {
    return eq(stringField(value orelse return false, key), expected);
}

fn isOwned(
    value: ?Value,
    project: []const u8,
    kind: []const u8,
) bool {
    return labelIs(value, managed_label, "true") and labelIs(value, project_label, project) and (stringField(value.?, kind) orelse return false).len != 0;
}

fn setLabels(
    a: Allocator,
    project: []const u8,
    name: []const u8,
    kind: []const u8,
    hash: []const u8,
) !Value {
    var result: Value = .{ .object = .empty };

    try result.object.put(a, managed_label, .{ .string = "true" });
    try result.object.put(a, project_label, .{ .string = project });
    try result.object.put(a, kind, .{ .string = name });
    try result.object.put(a, hash_label, .{ .string = hash });

    return result;
}

fn digest(a: Allocator, value: anytype) ![]const u8 {
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

fn lessString(_: void, left: []const u8, right: []const u8) bool {
    return std.mem.lessThan(u8, left, right);
}

fn lessNetworkAttachment(_: void, left: NetworkAttachment, right: NetworkAttachment) bool {
    return lessString({}, left.name, right.name);
}

fn environment(
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

fn hasAlias(
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

fn checkAttachments(
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

fn canonicalAttachments(
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
