const std = @import("std");

pub const UnixTransport = struct {
    socket_path: []const u8,

    pub fn connect(self: *const UnixTransport, http: *std.http.Client) !*std.http.Client.Connection {
        return http.connectUnix(self.socket_path);
    }
};

test "UnixTransport" {
    const client = std.http.Client{
        .allocator = std.heap.page_allocator,
    };
    const docker_socket = "/var/run/docker.sock";
    const unix_transport = UnixTransport{
        .socket_path = docker_socket,
    };

    std.testing.expectError(std.http.Client.ConnectUnixError, unix_transport.connect(client));
}
