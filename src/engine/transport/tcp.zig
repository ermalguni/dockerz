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
};

test "test_tcp_connection" {
    const allocator = std.testing.allocator;
    var threaded_io = std.Io.Threaded.init(allocator, .{
        .argv0 = .empty,
        .environ = .empty,
    });
    defer threaded_io.deinit();

    var tcp_transport = try TcpTransport.init(allocator, "localhost", 1234);
    defer tcp_transport.deinit(allocator);
}
