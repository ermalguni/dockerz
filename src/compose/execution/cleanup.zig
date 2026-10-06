const Client = @import("../../engine/client.zig").Client;
const Options = @import("options.zig").Options;
const Report = @import("report.zig").Report;

pub fn removeContainer(
    client: *Client,
    id: []const u8,
    options: Options,
    report: *Report,
) void {
    client.containers().stop(id, options.stop) catch |err| {
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

    client.containers().remove(id, .{}) catch |err| {
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

pub fn removeNetwork(
    client: *Client,
    id: []const u8,
    report: *Report,
) void {
    client.networks().remove(id) catch |err| {
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
