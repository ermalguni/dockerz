const std = @import("std");
const TcpTransport = @import("tcp.zig").TcpTransport;
const UnixTransport = @import("unix.zig").UnixTransport;

pub const Transport = union(enum) {
    unix: UnixTransport,
    tcp: TcpTransport,

    pub fn connect(self: *const Transport, http: *std.http.Client) anyerror!*std.http.Client.Connection {
        return switch (self.*) {
            .unix => |*transport| transport.connect(http),
            .tcp => |*transport| transport.connect(http),
        };
    }
};
