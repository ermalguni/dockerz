pub const models = @import("generated/models.zig");
pub const Client = @import("client.zig").Client;
pub const ClientConfig = @import("client.zig").ClientConfig;
pub const TransportConfig = @import("client.zig").TransportConfig;

pub const Version = @import("api/version.zig").Version;
pub const supported_versions = @import("api/version.zig").suppored_versions;

test {
    _ = @import("client.zig");
    _ = @import("api/version.zig");
    _ = @import("api/containers.zig");
    _ = @import("transport/tcp.zig");
}
