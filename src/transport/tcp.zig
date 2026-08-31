const std = @import("std");

pub const TcpTransport = struct {
    host: []const u8,
    port: u16,

    pub fn connect(self: *const TcpTransport, http: *std.http.Client) !*std.http.Client.Connection {
        try std.Io.net.HostName.validate(self.host);
        return http.connectTcp(.{ .bytes = self.host }, self.port, .plain);
    }
};
