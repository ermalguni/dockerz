const Client = @import("../../client.zig").Client;
const local_api = @import("./local.zig");

pub const Images = struct {
    client: *Client,

    pub fn local(self: Images) local_api.Local {
        return .{ .client = self.client };
    }
};
