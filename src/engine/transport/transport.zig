const std = @import("std");
const TcpTransport = @import("tcp.zig").TcpTransport;
const UnixTransport = @import("unix.zig").UnixTransport;

pub const Transport = union(enum) {
    unix: UnixTransport,
    tcp: TcpTransport,

    pub const Config = union(enum) {
        unix: []const u8,
        tcp: struct {
            host: []const u8,
            port: u16,
        },
    };

    pub fn init(allocator: std.mem.Allocator, config: Config) !Transport {
        return switch (config) {
            .unix => |path| .{
                .unix = try UnixTransport.init(allocator, path),
            },

            .tcp => |tcp| .{
                .tcp = try TcpTransport.init(allocator, tcp.host, tcp.port),
            },
        };
    }

    pub fn deinit(self: *Transport, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .unix => |*unix| unix.deinit(allocator),
            .tcp => |*tcp| tcp.deinit(allocator),
        }
    }
};
