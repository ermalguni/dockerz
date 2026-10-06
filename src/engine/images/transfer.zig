const std = @import("std");
const Client = @import("../client.zig").Client;
const Endpoints = @import("transfer_endpoints.zig");
const writeEndpointTarget = @import("../http.zig").writeEndpointTarget;

pub const SaveOptions = struct {
    platforms: []const []const u8 = &.{},
    timeout: std.Io.Timeout,
};

pub const Transfer = struct {
    client: *Client,

    pub fn save(
        self: Transfer,
        name_or_id: []const u8,
        destination: *std.Io.Writer,
        options: SaveOptions,
    ) !void {
        var target: std.Io.Writer.Allocating = .{ .allocator = self.client.allocator };
        defer target.deinit();

        const id: std.Uri.Component = .{ .raw = name_or_id };

        try writeEndpointTarget(
            &target.writer,
            Endpoints.Save,
            .{std.fmt.alt(id, .formatEscaped)},
            options,
        );

        try self.download(
            target.writer.buffered(),
            destination,
            options.timeout,
        );
    }

    pub fn saveMany(
        self: Transfer,
        names: []const []const u8,
        destination: *std.Io.Writer,
        options: SaveOptions,
    ) !void {
        if (names.len == 0) {
            return error.NoImageSelected;
        }

        var target: std.Io.Writer.Allocating = .{ .allocator = self.client.allocator };
        defer target.deinit();

        try writeEndpointTarget(
            &target.writer,
            Endpoints.SaveMany,
            .{},
            .{
                .names = names,
                .platforms = options.platforms,
            },
        );

        try self.download(
            target.writer.buffered(),
            destination,
            options.timeout,
        );
    }

    fn download(
        self: Transfer,
        target: []const u8,
        destination: *std.Io.Writer,
        timeout: std.Io.Timeout,
    ) !void {
        var resp = try self.client.request(
            .{
                .target = target,
                .versioned = true,
                .method = .get,
                .expected_status = .ok,
                .stream = true,
                .timeout = timeout,
            },
        );
        defer resp.deinit();

        var buffer: [8192]u8 = undefined;
        var body = try resp.reader(&buffer);

        _ = try body.interface.streamRemaining(destination);
    }
};
