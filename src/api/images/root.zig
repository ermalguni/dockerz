const Client = @import("../../client.zig").Client;
const local_api = @import("local.zig");
const registry_api = @import("registry.zig");
const builder_api = @import("builder.zig");
const transfer_api = @import("transfer.zig");

pub const Images = struct {
    client: *Client,

    pub fn local(self: Images) local_api.Local {
        return .{ .client = self.client };
    }

    pub fn registry(self: Images) registry_api.Registry {
        return .{ .client = self.client };
    }

    pub fn builder(self: Images) builder_api.Builder {
        return .{ .client = self.client };
    }

    pub fn transfer(self: Images) transfer_api.Transfer {
        return .{ .client = self.client };
    }
};
