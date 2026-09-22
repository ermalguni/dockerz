const std = @import("std");
const Client = @import("../client.zig").Client;
const models = @import("../generated/models.zig");
const QueryParam = @import("../http.zig").QueryParam;
const writeTargetUrl = @import("../http.zig").writeTargetURL;

const Paths = struct {
    const List = "/containers/json";
    const Create = "/containers/create";
    const Get = "/containers/{f}/json";
    const Start = "/containers/{f}/start";
    const Stop = "/containers/{f}/stop";
    const Pause = "/containers/{f}/pause";
    const Unpause = "/containers/{f}/unpause";
    const Rename = "/containers/{f}/restart";
    const Kill = "/containers/{f}/kill";
    const Restart = "/containers/{f}/restart";
};

pub const ListOptions = struct {
    all: ?bool = null,
    limit: ?u32 = null,
};

pub const StartOptions = struct {
    detach_keys: ?[]const u8 = null,
};

pub const StopOptions = struct {
    signal: ?[]const u8 = null,
    timeout_signal: ?i32 = null,
};

pub const KillOptions = struct {
    signal: ?[]const u8 = null,
};

pub const RestartOptions = struct {
    signal: ?[]const u8 = null,
    timeout_seconds: ?i32 = null,
};

pub const ContainerCreateRequest = struct {
    config: models.ContainerConfig,
    host_config: ?models.HostConfig,
    networking_config: ?models.NetworkingConfig,

    pub fn jsonStringify(self: ContainerCreateRequest, json_string: *std.json.Stringify) !void {
        try json_string.beginObject();

        inline for (std.meta.fields(models.ContainerConfig)) |field| {
            if (@field(self.config, field.name)) |value| {
                try json_string.objectField(field.name);
                try json_string.write(value);
            }
        }

        if (self.host_config) |host| {
            try json_string.objectField("HostConfig");
            try json_string.write(host);
        }

        if (self.networking_config) |network| {
            try json_string.objectField("NetworkingConfig");
            try json_string.write(network);
        }

        try json_string.endObject();
    }
};

pub const Containers = struct {
    client: *Client,

    pub fn list(self: Containers, options: ListOptions) !std.json.Parsed([]const models.ContainerSummary) {
        var target: std.Io.Writer.Allocating = .init(self.client.allocator);
        defer target.deinit();

        const writer = &target.writer;

        var params: [2]QueryParam = undefined;
        var count: u8 = 0;

        if (options.all) |value| {
            params[count] = .{ .name = "all", .value = .{
                .boolean = value,
            } };

            count += 1;
        }

        if (options.limit) |value| {
            params[count] = .{ .name = "limit", .value = .{
                .int = value,
            } };

            count += 1;
        }

        try writeTargetUrl(
            writer,
            Paths.List,
            .{},
            params[0..count],
        );

        return self.client.getJson([]const models.ContainerSummary, .{
            .target = writer.buffered(),
            .versioned = true,
        });
    }

    pub fn get(self: Containers, name_or_id: []const u8) !std.json.Parsed(models.ContainerInspectResponse) {
        var target: std.Io.Writer.Allocating = .init(self.client.allocator);
        defer target.deinit();

        const id: std.Uri.Component = .{
            .raw = name_or_id,
        };

        try writeTargetUrl(
            &target.writer,
            Paths.Get,
            .{std.fmt.alt(id, .formatEscaped)},
            &.{},
        );

        return self.client.getJson(models.ContainerInspectResponse, .{
            .target = target.writer.buffered(),
            .versioned = true,
        });
    }

    pub fn create(self: Containers, request: ContainerCreateRequest, params: []const QueryParam) !std.json.Parsed(models.ContainerCreateResponse) {
        var target: std.Io.Writer.Allocating = .init(self.client.allocator);
        defer target.deinit();

        const writer = &target.writer;

        try writeTargetUrl(writer, Paths.Create, .{}, params);

        const payload = try std.json.Stringify.valueAlloc(
            self.client.allocator,
            request,
            .{
                .emit_null_optional_fields = false,
            },
        );
        defer self.client.allocator.free(payload);

        return self.client.getJson(models.ContainerCreateResponse, .{
            .target = writer.buffered(),
            .versioned = true,
            .method = .post,
            .expected_status = .created,
            .payload = payload,
            .content_type = "application/json",
        });
    }

    pub fn start(self: Containers, name_or_id: []const u8, options: StartOptions) !void {
        var target: std.Io.Writer.Allocating = .init(self.client.allocator);
        defer target.deinit();

        const id: std.Uri.Component = .{
            .raw = name_or_id,
        };

        var params: [1]QueryParam = undefined;
        var count = 0;

        if (options.detach_keys) |value| {
            params[count] = .{
                .name = "detachKeys",
                .value = .{
                    .string = value,
                },
            };

            count += 1;
        }

        try writeTargetUrl(
            &target.writer,
            Paths.Start,
            .{std.fmt.alt(id, .formatEscaped)},
            params[0..count],
        );

        var resp = try self.client.request(.{
            .target = target.writer.buffered(),
            .versioned = true,
            .method = .post,
            .expected_status = .no_content,
        });
        defer resp.deinit();
    }

    pub fn stop(self: Containers, name_or_id: []const u8, options: StopOptions) !void {
        var target: std.Io.Writer.Allocating = .init(self.client.allocator);
        defer target.deinit();

        const id: std.Uri.Component = .{
            .raw = name_or_id,
        };

        var params: [2]QueryParam = undefined;
        var count = 0;

        if (options.signal) |value| {
            params[count] = .{ .name = "signal", .value = .{ .string = value } };
            count += 1;
        }

        if (options.timeout_signal) |value| {
            params[count] = .{ .name = "t", .value = .{ .int = value } };
            count += 1;
        }

        try writeTargetUrl(
            &target.writer,
            Paths.Stop,
            .{std.fmt.alt(id, .formatEscaped)},
            params,
        );

        var resp = try self.client.request(.{
            .target = target.writer.buffered(),
            .versioned = true,
            .method = .post,
            .expected_status = .no_content,
        });
        defer resp.deinit();
    }

    pub fn pause(self: Containers, name_or_id: []const u8) !void {
        var target: std.Io.Writer.Allocating = .init(self.client.allocator);
        defer target.deinit();

        const id: std.Uri.Component = .{
            .raw = name_or_id,
        };

        try writeTargetUrl(
            &target.writer,
            Paths.Pause,
            .{std.fmt.alt(id, .formatEscaped)},
            &.{},
        );

        var resp = try self.client.request(.{
            .target = target.writer.buffered(),
            .versioned = true,
            .method = .post,
            .expected_status = .no_content,
        });
        defer resp.deinit();
    }

    pub fn unpause(self: Containers, name_or_id: []const u8) !void {
        var target: std.Io.Writer.Allocating = .init(self.client.allocator);
        defer target.deinit();

        const id: std.Uri.Component = .{
            .raw = name_or_id,
        };

        try writeTargetUrl(
            &target.writer,
            Paths.Unpause,
            .{std.fmt.alt(id, .formatEscaped)},
            &.{},
        );

        var resp = try self.client.request(.{
            .target = target.writer.buffered(),
            .versioned = true,
            .method = .post,
            .expected_status = .no_content,
        });
        defer resp.deinit();
    }
};

pub fn rename(self: Containers, name_or_id: []const u8, new_name: []const u8) !void {
    var target: std.Io.Writer.Allocating = .init(self.client.allocator);
    defer target.deinit();

    const id: std.Uri.Component = .{
        .raw = name_or_id,
    };

    const params = [_]QueryParam{
        .{
            .name = "name",
            .value = .{
                .string = new_name,
            },
        },
    };

    try writeTargetUrl(
        &target.writer,
        Paths.Rename,
        .{std.fmt.alt(id, .formatEscaped)},
        params,
    );

    var resp = try self.client.request(.{
        .target = target.writer.buffered(),
        .versioned = true,
        .method = .post,
        .expected_status = .no_content,
    });
    defer resp.deinit();
}

pub fn kill(self: Containers, name_or_id: []const u8, options: KillOptions) !void {
    var target: std.Io.Writer.Allocating = .init(self.client.allocator);
    defer target.deinit();

    const id: std.Uri.Component = .{
        .raw = name_or_id,
    };

    var params: [1]QueryParam = undefined;
    var count = 0;

    if (options.signal) |value| {
        params[count] = .{
            .name = "signal",
            .value = .{
                .string = value,
            },
        };

        count += 1;
    }

    try writeTargetUrl(
        &target.writer,
        Paths.Kill,
        .{std.fmt.alt(id, .formatEscaped)},
        params,
    );

    var resp = try self.client.request(.{
        .target = target.writer.buffered(),
        .versioned = true,
        .method = .post,
        .expected_status = .no_content,
    });
    defer resp.deinit();
}

pub fn restart(self: Containers, name_or_id: []const u8, options: RestartOptions) !void {
    var target: std.Io.Writer.Allocating = .init(self.client.allocator);
    defer target.deinit();

    const id: std.Uri.Component = .{
        .raw = name_or_id,
    };

    var params: [2]QueryParam = undefined;
    var count = 0;

    if (options.signal) |value| {
        params[count] = .{
            .name = "signal",
            .value = .{
                .string = value,
            },
        };

        count += 1;
    }

    if (options.timeout_seconds) |value| {
        params[count] = .{
            .name = "t",
            .value = .{
                .int = value,
            },
        };
    }

    try writeTargetUrl(
        &target.writer,
        Paths.Restart,
        .{std.fmt.alt(id, .formatEscaped)},
        params,
    );

    var resp = try self.client.request(.{
        .target = target.writer.buffered(),
        .versioned = true,
        .method = .post,
        .expected_status = .no_content,
    });
    defer resp.deinit();
}

test "integration: container list test" {
    if (!@import("test_options").docker_integration) {
        return error.SkipZigTest;
    }

    var client = try Client.init(
        std.testing.allocator,
        std.testing.io,
        .{
            .transport = .{ .unix = "/var/run/docker.sock" },
        },
    );
    defer client.deinit();

    try client.connect();

    const result = try client.containers().list(
        .{
            .all = true,
        },
    );
    defer result.deinit();

    std.debug.print("{any}", .{result.value});

    try std.testing.expect(result.value.len > 0);
}
