const std = @import("std");
const Client = @import("../client.zig").Client;
const models = @import("../generated/models.zig");
const Endpoints = @import("endpoints.zig");
const writeEndpointTarget = @import("../http.zig").writeEndpointTarget;

pub const ListOptions = struct {
    filters: ?[]const u8 = null,
};

pub const GetOptions = struct {
    verbose: ?bool = null,
    scope: ?[]const u8 = null,
};

pub const ConnectOptions = struct {
    endpoint_config: ?models.EndpointSettings = null,
};

pub const DisconnectOptions = struct {
    force: ?bool = null,
};

pub const PruneOptions = struct {
    filters: ?[]const u8 = null,
};

pub const CreateRequest = struct {
    Name: []const u8,
    Driver: ?[]const u8 = null,
    Scope: ?[]const u8 = null,

    Internal: ?bool = null,
    Attachable: ?bool = null,
    Ingress: ?bool = null,

    ConfigOnly: ?bool = null,
    ConfigFrom: ?models.ConfigReference = null,

    IPAM: ?models.IPAM = null,
    EnableIPv4: ?bool = null,
    EnableIPv6: ?bool = null,

    Options: ?std.json.Value = null,
    Labels: ?std.json.Value = null,
};

pub const InspectResponse = struct {
    Name: ?[]const u8 = null,
    Id: ?[]const u8 = null,
    Created: ?[]const u8 = null,
    Scope: ?[]const u8 = null,
    Driver: ?[]const u8 = null,

    EnableIPv4: ?bool = null,
    EnableIPv6: ?bool = null,
    Internal: ?bool = null,
    Attachable: ?bool = null,
    Ingress: ?bool = null,

    ConfigOnly: ?bool = null,
    ConfigFrom: ?models.ConfigReference = null,

    IPAM: ?models.IPAM = null,
    Options: ?std.json.Value = null,
    Labels: ?std.json.Value = null,
    Peers: ?[]const models.PeerInfo = null,

    Containers: ?std.json.Value = null,
    Services: ?std.json.Value = null,
    Status: ?models.NetworkStatus = null,
};

pub const PruneResponse = struct {
    NetworksDeleted: ?[]const []const u8 = null,
};

pub const Networks = struct {
    client: *Client,

    pub fn list(
        self: Networks,
        options: ListOptions,
    ) !std.json.Parsed([]const models.Network) {
        var target: std.Io.Writer.Allocating = .init(self.client.allocator);
        defer target.deinit();

        try writeEndpointTarget(
            &target.writer,
            Endpoints.List,
            .{},
            options,
        );

        return self.client.getJson([]const models.Network, .{
            .target = target.writer.buffered(),
            .versioned = true,
            .method = .get,
            .expected_status = .ok,
        });
    }

    pub fn get(
        self: Networks,
        name_or_id: []const u8,
        options: GetOptions,
    ) !std.json.Parsed(InspectResponse) {
        var target: std.Io.Writer.Allocating = .init(self.client.allocator);
        defer target.deinit();

        const name: std.Uri.Component = .{
            .raw = name_or_id,
        };

        try writeEndpointTarget(
            &target.writer,
            Endpoints.Get,
            .{std.fmt.alt(name, .formatEscaped)},
            options,
        );

        return self.client.getJson(InspectResponse, .{
            .target = target.writer.buffered(),
            .versioned = true,
            .method = .get,
            .expected_status = .ok,
        });
    }

    pub fn create(
        self: Networks,
        request: CreateRequest,
    ) !std.json.Parsed(models.NetworkCreateResponse) {
        const payload = try std.json.Stringify.valueAlloc(
            self.client.allocator,
            request,
            .{
                .emit_null_optional_fields = false,
            },
        );
        defer self.client.allocator.free(payload);

        return self.client.getJson(models.NetworkCreateResponse, .{
            .target = Endpoints.Create.path,
            .versioned = true,
            .method = .post,
            .expected_status = .created,
            .payload = payload,
            .content_type = "application/json",
        });
    }

    pub fn remove(
        self: Networks,
        name_or_id: []const u8,
    ) !void {
        var target: std.Io.Writer.Allocating = .init(self.client.allocator);
        defer target.deinit();

        const name: std.Uri.Component = .{
            .raw = name_or_id,
        };

        try writeEndpointTarget(
            &target.writer,
            Endpoints.Remove,
            .{std.fmt.alt(name, .formatEscaped)},
            .{},
        );

        var response = try self.client.request(.{
            .target = target.writer.buffered(),
            .versioned = true,
            .method = .delete,
            .expected_status = .no_content,
        });
        defer response.deinit();
    }

    pub fn connect(
        self: Networks,
        network: []const u8,
        container: []const u8,
        options: ConnectOptions,
    ) !void {
        var target: std.Io.Writer.Allocating = .init(self.client.allocator);
        defer target.deinit();

        const name: std.Uri.Component = .{
            .raw = network,
        };

        try writeEndpointTarget(
            &target.writer,
            Endpoints.Connect,
            .{std.fmt.alt(name, .formatEscaped)},
            .{},
        );

        const request: models.NetworkConnectRequest = .{
            .Container = container,
            .EndpointConfig = options.endpoint_config,
        };

        const payload = try std.json.Stringify.valueAlloc(
            self.client.allocator,
            request,
            .{
                .emit_null_optional_fields = false,
            },
        );
        defer self.client.allocator.free(payload);

        var response = try self.client.request(.{
            .target = target.writer.buffered(),
            .versioned = true,
            .method = .post,
            .expected_status = .ok,
            .payload = payload,
            .content_type = "application/json",
        });
        defer response.deinit();
    }

    pub fn disconnect(
        self: Networks,
        network: []const u8,
        container: []const u8,
        options: DisconnectOptions,
    ) !void {
        var target: std.Io.Writer.Allocating = .init(self.client.allocator);
        defer target.deinit();

        const name: std.Uri.Component = .{
            .raw = network,
        };

        try writeEndpointTarget(
            &target.writer,
            Endpoints.Disconnect,
            .{std.fmt.alt(name, .formatEscaped)},
            .{},
        );

        const request: models.NetworkDisconnectRequest = .{
            .Container = container,
            .Force = options.force,
        };

        const payload = try std.json.Stringify.valueAlloc(
            self.client.allocator,
            request,
            .{
                .emit_null_optional_fields = false,
            },
        );
        defer self.client.allocator.free(payload);

        var response = try self.client.request(.{
            .target = target.writer.buffered(),
            .versioned = true,
            .method = .post,
            .expected_status = .ok,
            .payload = payload,
            .content_type = "application/json",
        });
        defer response.deinit();
    }

    pub fn prune(
        self: Networks,
        options: PruneOptions,
    ) !std.json.Parsed(PruneResponse) {
        var target: std.Io.Writer.Allocating = .init(self.client.allocator);
        defer target.deinit();

        try writeEndpointTarget(
            &target.writer,
            Endpoints.Prune,
            .{},
            options,
        );

        return self.client.getJson(PruneResponse, .{
            .target = target.writer.buffered(),
            .versioned = true,
            .method = .post,
            .expected_status = .ok,
        });
    }
};
