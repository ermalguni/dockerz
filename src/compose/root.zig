const model = @import("model.zig");
const loading = @import("loading/root.zig");
const execution = @import("execution/root.zig");

pub const Project = model.Project;
pub const LoadedProject = model.LoadedProject;
pub const Service = model.Service;
pub const Network = model.Network;
pub const NetworkAttachment = model.NetworkAttachment;
pub const EnvironmentEntry = model.EnvironmentEntry;
pub const ManagedNetwork = model.ManagedNetwork;

pub const load = loading.load;
pub const LoadOptions = loading.Options;

pub const Executor = execution.Executor;
pub const ExecutionOptions = execution.Options;
pub const Report = execution.Report;
pub const CleanupError = execution.CleanupError;

test {
    _ = loading;
    _ = @import("execution/configuration.zig");
    _ = @import("execution/ownership.zig");
}
