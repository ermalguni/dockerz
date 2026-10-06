const std = @import("std");

const UnixTransportError = error{InvalidSocketPath};

pub const UnixTransport = struct {
    socket_path: []const u8,

    pub fn init(allocator: std.mem.Allocator, path: []const u8) !UnixTransport {
        if (path.len == 0 or std.mem.findScalar(u8, path, 0) != null) {
            return UnixTransportError.InvalidSocketPath;
        }

        _ = try std.Io.net.UnixAddress.init(path);

        return .{
            .socket_path = try allocator.dupe(u8, path),
        };
    }

    pub fn deinit(self: *UnixTransport, allocator: std.mem.Allocator) void {
        allocator.free(self.socket_path);
        self.* = undefined;
    }
};

test "UnixTransport" {
    const allocator = std.testing.allocator;
    var threaded_io = std.Io.Threaded.init(allocator, .{
        .argv0 = .empty,
        .environ = .empty,
    });
    defer threaded_io.deinit();

    const docker_socket = "/var/run/docker.sock";

    var unix_transport = try UnixTransport.init(allocator, docker_socket);
    defer unix_transport.deinit(allocator);
}
