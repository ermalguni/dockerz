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

    pub fn connect(self: *const UnixTransport, http: *std.http.Client) !*std.http.Client.Connection {
        return http.connectUnix(self.socket_path);
    }
};

test "UnixTransport" {
    const allocator = std.testing.allocator;
    var threaded_io = std.Io.Threaded.init(allocator, .{
        .argv0 = .empty,
        .environ = .empty,
    });
    defer threaded_io.deinit();

    var client = std.http.Client{
        .allocator = allocator,
        .io = threaded_io.io(),
    };
    const docker_socket = "/var/run/docker.sock";
    const unix_transport = UnixTransport{
        .socket_path = docker_socket,
    };

    _ = unix_transport.connect(&client) catch |err| {
        try std.testing.expect(err == error.FileNotFound or err == error.AccessDenied or err == error.ConnectionRefused);
        // try std.testing.expectError(std.http.Client.ConnectUnixError, unix_transport.connect(&client));
    };
}
