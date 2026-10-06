pub const models = @import("generated/models.zig");
pub const Client = @import("client.zig").Client;
pub const ClientConfig = @import("client.zig").ClientConfig;
pub const TransportConfig = @import("client.zig").TransportConfig;

pub const Version = @import("system/version.zig").Version;
pub const supported_versions = @import("system/version.zig").supported_versions;

pub const containers = @import("containers/root.zig");
pub const networks = @import("networks/root.zig");
pub const volumes = @import("volumes/root.zig");
pub const images = @import("images/root.zig");
pub const system = @import("system/root.zig");

test {
    _ = @import("client.zig");
    _ = @import("system/root.zig");
    _ = @import("system/version.zig");
    _ = @import("containers/root.zig");
    _ = @import("transport/tcp.zig");
}
