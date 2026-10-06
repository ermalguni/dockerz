const Client = @import("../../engine/client.zig").Client;
const composeModel = @import("../model.zig");
const up_impl = @import("up.zig");
const down_impl = @import("down.zig");

pub const Options = @import("options.zig").Options;
pub const Report = @import("report.zig").Report;
pub const CleanupError = @import("report.zig").CleanupError;

pub const Executor = struct {
    client: *Client,

    pub fn up(
        self: Executor,
        project: composeModel.Project,
        options: Options,
    ) Report {
        return up_impl.up(self.client, project, options);
    }

    pub fn down(
        self: Executor,
        project_name: []const u8,
        options: Options,
    ) Report {
        return down_impl.down(self.client, project_name, options);
    }
};
