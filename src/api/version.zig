const std = @import("std");
const models = @import("../generated/models.zig");

const http = std.http;

pub const GetVersionPath = "/version";

pub const VersionError = error{ MissingDotDelimiter, MissingApiVersion, WrongFormat, WrongMajor, WrongMinor };

pub const Version = struct {
    major: u8,
    minor: u8,

    // return the string version like "1.55"
    pub fn to_string(self: Version, allocator: std.mem.Allocator) ![]const u8 {
        return try std.fmt.allocPrint(allocator, "{d}.{d}", .{ self.major, self.minor });
    }

    // takes a version string and generates the Version struct
    pub fn parse_version(version: []const u8) VersionError!Version {
        if (std.mem.findScalar(u8, version, '.') == null) {
            return VersionError.MissingDotDelimiter;
        }

        var iterator = std.mem.splitScalar(u8, version, '.');

        const major_str = iterator.next() orelse return VersionError.WrongMajor;
        const minor_str = iterator.next() orelse return VersionError.WrongMinor;

        if (iterator.next() != null) {
            return VersionError.WrongFormat;
        }

        if (major_str.len == 0) {
            return VersionError.WrongMajor;
        }

        if (minor_str.len == 0) {
            return VersionError.WrongMinor;
        }

        for (major_str) |byte| {
            if (!std.ascii.isDigit(byte)) {
                return VersionError.WrongMajor;
            }
        }

        for (minor_str) |byte| {
            if (!std.ascii.isDigit(byte)) {
                return VersionError.WrongMinor;
            }
        }

        return .{
            .major = std.fmt.parseInt(u8, major_str, 10) catch return VersionError.WrongMajor,
            .minor = std.fmt.parseInt(u8, minor_str, 10) catch return VersionError.WrongMinor,
        };
    }

    pub fn order(self: Version, other: Version) std.math.Order {
        const major_order = std.math.order(self.major, other.major);

        if (major_order != .eq) {
            return major_order;
        }

        return std.math.order(self.minor, other.minor);
    }
};

pub const SupportedVersionsError = error{ InvalidVersionRange, NoCompatibleApiVersion };

pub const SupportedVersions = struct {
    min_supported_version: Version,
    max_supported_version: Version,

    pub fn isSupported(self: SupportedVersions, version: Version) bool {
        return version.order(self.min_supported_version) != .lt and version.order(self.max_supported_version) != .gt;
    }

    pub fn negotiate(self: SupportedVersions, server: SupportedVersions) SupportedVersionsError!Version {
        if (self.min_supported_version.order(self.max_supported_version) == .gt or server.min_supported_version.order(server.min_supported_version) == .gt) {
            return SupportedVersionsError.InvalidVersionRange;
        }

        const lower = if (self.min_supported_version.order(server.min_supported_version) == .gt) self.min_supported_version else server.min_supported_version;
        const upper = if (self.max_supported_version.order(server.max_supported_version) == .gt) self.max_supported_version else server.max_supported_version;

        if (lower.order(upper) == .gt) {
            return SupportedVersionsError.NoCompatibleApiVersion;
        }

        return upper;
    }
};

pub const suppored_versions: SupportedVersions = .{
    .max_supported_version = .{ .major = 1, .minor = 55 },

    .min_supported_version = .{ .major = 1, .minor = 40 },
};

fn negotiateVersionBody(allocator: std.mem.Allocator, body: []const u8) !Version {
    const parsed = try std.json.parseFromSlice(models.SystemVersion, allocator, body, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();

    const max_version = parsed.value.ApiVersion orelse return VersionError.MissingApiVersion;
    const min_version = parsed.value.MinAPIVersion orelse return VersionError.MissingApiVersion;

    const server: SupportedVersions = .{
        .max_supported_version = try Version.parse_version(max_version),
        .min_supported_version = try Version.parse_version(min_version),
    };

    return suppored_versions.negotiate(server);
}

pub fn getVersion(client: *http.Client, connection: *http.Client.Connection, uri: std.Uri) !Version {
    var req = blk: {
        errdefer client.connection_pool.release(connection, client.io);

        break :blk try client.request(.GET, uri, .{ .connection = connection, .redirect_behavior = .unhandled, .headers = .{ .accept_encoding = .{ .override = "identity" } } });
    };
    defer req.deinit();

    try req.sendBodiless();

    var resp = try req.receiveHead(&.{});

    const status = resp.head.status;
    const encoding = resp.head.content_encoding;

    var transfer_buff: [1024]u8 = undefined;
    const reader = resp.reader(&transfer_buff);

    if (status != .ok) {
        return error.UnexpectedHttpStatus;
    }

    if (encoding != .identity) {
        return error.UnsupportedContentEncoding;
    }

    const body = reader.allocRemaining(client.allocator, .limited(64 * 1024)) catch |err| switch (err) {
        error.ReadFailed => return resp.bodyErr() orelse err,
        else => return err,
    };
    defer client.allocator.free(body);

    return negotiateVersionBody(client.allocator, body);
}

test "test_supported_versions" {
    const allowed_version = Version{
        .major = 1,
        .minor = 50,
    };
    const not_allowed_version = Version{ .major = 0, .minor = 15 };

    try std.testing.expectEqual(true, suppored_versions.isSupported(allowed_version));
    try std.testing.expectEqual(false, suppored_versions.isSupported(not_allowed_version));
}

test "check_version" {
    const allocator = std.testing.allocator;
    const v1 = Version{
        .major = 1,
        .minor = 2,
    };

    const v1_string_check = "1.2";
    const v1_string = try v1.to_string(allocator);
    defer allocator.free(v1_string);

    try std.testing.expectEqualStrings(v1_string_check, v1_string);
    try std.testing.expectError(VersionError.MissingDotDelimiter, Version.parse_version("123"));
    try std.testing.expectError(VersionError.WrongMajor, Version.parse_version("a.15"));
}
