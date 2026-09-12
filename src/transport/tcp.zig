const std = @import("std");

pub const TcpTransport = struct {
    host: []const u8,
    port: u16,

    pub fn init(allocator: std.mem.Allocator, host: []const u8, port: u16) !TcpTransport {
        try std.Io.net.HostName.validate(host);

        return .{ .host = try allocator.dupe(u8, host), .port = port };
    }

    pub fn deinit(self: *TcpTransport, allocator: std.mem.Allocator) void {
        allocator.free(self.host);
        self.* = undefined;
    }

    pub fn connect(self: *const TcpTransport, http: *std.http.Client) !*std.http.Client.Connection {
        return http.connectTcp(.{ .bytes = self.host }, self.port, .plain);
    }
};

test "test_tcp_connection" {
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
    var tcp_transport = try TcpTransport.init(allocator, "localhost", 1234);
    defer tcp_transport.deinit(allocator);

    _ = tcp_transport.connect(&client) catch |err| {
        try std.testing.expect(std.http.Client.ConnectTcpError.ConnectionRefused == err);
        // try std.testing.expectError(std.http.Client.ConnectUnixError, unix_transport.connect(&client));
    };
}
