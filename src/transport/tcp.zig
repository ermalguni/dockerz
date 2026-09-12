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
    defer client.deinit();

    var tcp_transport = try TcpTransport.init(allocator, "localhost", 1234);
    defer tcp_transport.deinit(allocator);

    _ = tcp_transport.connect(&client) catch |err| {
        try std.testing.expect(std.http.Client.ConnectTcpError.ConnectionRefused == err);
        // try std.testing.expectError(std.http.Client.ConnectUnixError, unix_transport.connect(&client));
    };
}

test "TCP transport connects to a local listener" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    const address = try std.Io.net.IpAddress.parse("127.0.0.1", 0);
    var listener = try address.listen(io, .{});
    defer listener.deinit(io);

    var http_client = std.http.Client{
        .allocator = allocator,
        .io = io,
    };
    defer http_client.deinit();

    var tcp_transport = try TcpTransport.init(allocator, "127.0.0.1", listener.socket.address.getPort());
    defer tcp_transport.deinit(allocator);

    const connection = try tcp_transport.connect(&http_client);
    defer http_client.connection_pool.release(connection, io);

    const accepted = try listener.accept(io);
    defer accepted.close(io);
}
