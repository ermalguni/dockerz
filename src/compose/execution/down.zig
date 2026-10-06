const std = @import("std");
const Client = @import("../../engine/client.zig").Client;
const Options = @import("options.zig").Options;
const Report = @import("report.zig").Report;
const composeModel = @import("../model.zig");
const cleanup = @import("cleanup.zig");
const ownership = @import("ownership.zig");

const isOwned = ownership.isOwned;
const project_label = ownership.project_label;
const managed_label = ownership.managed_label;
const service_label = ownership.service_label;
const network_label = ownership.network_label;

const removeContainer = cleanup.removeContainer;
const removeNetwork = cleanup.removeNetwork;

pub fn down(
    client: *Client,
    project_name: []const u8,
    options: Options,
) Report {
    var report: Report = .{
        .arena = .init(client.allocator),
    };

    destroy(client, project_name, options, &report) catch |err| {
        report.failure = err;
    };

    return report;
}

fn destroy(
    client: *Client,
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

    const container_list = try client.containers().list(.{
        .all = true,
        .filters = filters,
    });
    defer container_list.deinit();

    const network_list = try client.networks().list(.{
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
        removeContainer(client, id, options, report);
    }

    for (network_ids[0..nn]) |id| {
        removeNetwork(client, id, report);
    }
}
