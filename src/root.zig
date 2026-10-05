pub const models = @import("generated/models.zig");
pub const Client = @import("client.zig").Client;
pub const ClientConfig = @import("client.zig").ClientConfig;
pub const TransportConfig = @import("client.zig").TransportConfig;
pub const executor = @import("compose/executor.zig");

pub const Version = @import("api/system/version.zig").Version;
pub const supported_versions = @import("api/system/version.zig").suppored_versions;

pub const compose = struct {
    pub const model = @import("compose/model.zig");
    pub const loader = @import("compose/loader.zig");
};

test {
    _ = @import("client.zig");
    _ = @import("api/system/root.zig");
    _ = @import("api/system/version.zig");
    _ = @import("api/containers.zig");
    _ = @import("transport/tcp.zig");
    _ = @import("compose/loader.zig");
    _ = @import("compose/executor.zig");
}
