const std = @import("std");

pub const EnvironmentEntry = struct {
    name: []const u8,
    value: ?[]const u8,
};

pub const NetworkAttachment = struct {
    network_index: usize,
    aliases: []const []const u8 = &.{},
};

pub const Service = struct {
    name: []const u8,
    image: []const u8,
    command: ?[]const []const u8 = null,
    environment: []EnvironmentEntry = &.{},
    networks: []const NetworkAttachment,
};

pub const ManagedNetwork = struct {
    driver: []const u8 = "bridge",
    internal: bool = false,
};

pub const Network = struct {
    key: []const u8,
    engine_name: []const u8,
    configuration: union(enum) {
        managed: ManagedNetwork,
        external,
    },
};

pub const Project = struct {
    name: []const u8,
    services: []const Service,
    networks: []const Network,

    pub fn validate(self: Project) !void {
        if (!isValidProjectName(self.name))
            return error.InvalidProjectName;

        if (self.services.len == 0)
            return error.NoServices;

        for (self.networks, 0..) |network, index| {
            if (!isValidName(network.key) or !isValidName(network.engine_name))
                return error.InvalidNetworkName;

            for (self.networks[0..index]) |previous_network| {
                if (std.mem.eql(u8, previous_network.key, network.key) or std.mem.eql(u8, previous_network.engine_name, network.engine_name))
                    return error.DuplicateNetworkNames;
            }

            switch (network.configuration) {
                .managed => |managed| {
                    if (!std.mem.eql(u8, managed.driver, "bridge")) return error.UnsupportedNetworkDriver;
                },
                .external => {},
            }
        }

        for (self.services, 0..) |service, index| {
            if (!isValidName(service.name)) return error.InvalidServiceName;

            for (self.services[0..index]) |previous_service| {
                if (std.mem.eql(u8, previous_service.name, service.name)) return error.DuplicateServices;
            }

            if (service.image.len == 0 or
                std.mem.indexOfAny(
                    u8,
                    service.image,
                    " \t\r\n\x00",
                ) != null) return error.InvalidImageReference;

            if (service.command) |command| {
                for (command) |arg| {
                    if (std.mem.findScalar(u8, arg, 0) != null) return error.InvalidCommand;
                }
            }

            for (service.environment, 0..) |env, i| {
                if (env.name.len == 0 or
                    std.mem.indexOfAny(u8, env.name, "=\x00") != null) return error.InvalidEnvironment;

                if (env.value) |value| {
                    if (std.mem.indexOfScalar(u8, value, 0) != null)
                        return error.InvalidEnvironment;
                }

                for (service.environment[0..i]) |previous| {
                    if (std.mem.eql(u8, previous.name, env.name))
                        return error.DuplicateEnvironment;
                }
            }

            if (service.networks.len == 0)
                return error.NoServiceNetwork;

            for (service.networks, 0..) |network, i| {
                if (network.network_index >= self.networks.len) return error.UnknownNetwork;

                for (service.networks[0..i]) |previous_network| {
                    if (previous_network.network_index == network.network_index) return error.DuplicateAttachment;
                }

                for (network.aliases) |alias| {
                    if (!isValidName(alias)) return error.InvalidNetworkAlias;
                }
            }
        }
    }
};

pub const LoadedProject = struct {
    arena: std.heap.ArenaAllocator,
    value: Project,

    pub fn deinit(self: *LoadedProject) void {
        self.arena.deinit();
        self.* = undefined;
    }
};

pub fn isValidName(name: []const u8) bool {
    if (name.len == 0) return false;

    for (name) |character| {
        if (!std.ascii.isAlphanumeric(character) and character != '_' and character != '-' and character != '.') return false;
    }

    return true;
}

pub fn isValidProjectName(name: []const u8) bool {
    if (name.len == 0) return false;

    if (!std.ascii.isLower(name[0]) and
        !std.ascii.isDigit(name[0]))
    {
        return false;
    }

    for (name) |character| {
        if (!std.ascii.isLower(character) and
            !std.ascii.isDigit(character) and
            character != '_' and
            character != '-')
        {
            return false;
        }
    }

    return true;
}
