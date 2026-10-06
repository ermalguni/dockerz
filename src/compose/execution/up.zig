const std = @import("std");
const Client = @import("../../engine/client.zig").Client;
const composeModel = @import("../model.zig");
const Options = @import("options.zig").Options;
const Report = @import("report.zig").Report;
const ownership = @import("ownership.zig");
const configuration = @import("configuration.zig");
const containers = @import("../../engine/containers/root.zig");

const Value = std.json.Value;

const NetworkPlan = configuration.NetworkPlan;
const digest = configuration.digest;
const environment = configuration.environment;
const canonicalAttachments = configuration.canonicalAttachments;
const checkAttachments = configuration.checkAttachments;
const setLabels = ownership.setLabels;
const eq = ownership.eq;
const isOwned = ownership.isOwned;
const labelIs = ownership.labelIs;
const stringField = ownership.stringField;
const network_label = ownership.network_label;
const hash_label = ownership.hash_label;
const service_label = ownership.service_label;

const ServicePlan = struct {
    name: []const u8,
    id: ?[]const u8,
    request: containers.ContainerCreateRequest,
};

pub fn up(
    client: *Client,
    project: composeModel.Project,
    options: Options,
) Report {
    var report: Report = .{
        .arena = .init(client.client.allocator),
    };

    apply(client, project, options, &report) catch |err| {
        report.failure = err;

        var index = report.created_containers.items.len;
        while (index > 0) {
            index -= 1;
            client.removeContainer(
                report.created_containers.items[index].value.Id,
                options,
                &report,
            );
        }

        index = report.created_networks.items.len;
        while (index > 0) {
            index -= 1;
            client.removeNetwork(
                report.created_networks.items[index].value.Id,
                &report,
            );
        }
    };

    return report;
}

fn apply(
    client: *Client,
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

        const existing_network = client.networks().get(
            network.engine_name,
            .{},
        ) catch |err| {
            if (err != error.NotFound) return err;

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
        const image = try client.resolveImage(
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

        const inspected = client.containers().get(
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
        const created = try client.networks().create(.{
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
            const created = try client.containers().create(
                plan.request,
                .{ .name = plan.name },
            );

            report.created_containers.appendAssumeCapacity(created);
            plan.id = created.value.Id;
        }
    }

    for (services) |plan| {
        try client.containers().start(plan.id.?, .{});
    }
}
