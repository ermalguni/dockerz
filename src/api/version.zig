const std = @import("std");
const models = @import("../generated/models.zig");

const Client = @import("../client.zig").Client;

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
        if (self.min_supported_version.order(self.max_supported_version) == .gt or server.min_supported_version.order(server.max_supported_version) == .gt) {
            return SupportedVersionsError.InvalidVersionRange;
        }

        const lower = if (self.min_supported_version.order(server.min_supported_version) == .gt) self.min_supported_version else server.min_supported_version;
        const upper = if (self.max_supported_version.order(server.max_supported_version) == .lt) self.max_supported_version else server.max_supported_version;

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

pub fn getVersion(client: *Client) !Version {
    var response = try client.request(.{
        .target = GetVersionPath,
        .versioned = false,
        .max_body_bytes = 64 * 1024,
    });
    defer response.deinit();

    const body = try response.body() orelse return error.MissingApiVersion;

    return negotiateVersionBody(client.allocator, body);
}

test "version parser accepts numeric versions" {
    try std.testing.expectEqual(Version{ .major = 0, .minor = 0 }, try Version.parse_version("0.0"));
    try std.testing.expectEqual(Version{ .major = 255, .minor = 255 }, try Version.parse_version("255.255"));
}

test "version parser rejects malformed versions and big version numbers" {
    const cases = [_]struct {
        version_text: []const u8,
        expected: VersionError,
    }{
        .{ .version_text = "", .expected = VersionError.MissingDotDelimiter },
        .{ .version_text = ".55", .expected = VersionError.WrongMajor },
        .{
            .version_text = "1.",
            .expected = VersionError.WrongMinor,
        },
        .{
            .version_text = "1.1.1",
            .expected = VersionError.WrongFormat,
        },
        .{
            .version_text = "+1.10",
            .expected = VersionError.WrongMajor,
        },
        .{
            .version_text = "1.1_1",
            .expected = error.WrongMinor,
        },
        .{
            .version_text = "256.1",
            .expected = error.WrongMajor,
        },
        .{
            .version_text = "1.256",
            .expected = error.WrongMinor,
        },
    };

    for (cases) |case| {
        try std.testing.expectError(case.expected, Version.parse_version(case.version_text));
    }
}

test "version ordering check comparisons" {
    const cases = [_]struct { left: Version, right: Version, expected: std.math.Order }{
        .{ .left = .{ .major = 1, .minor = 8 }, .right = .{ .major = 1, .minor = 15 }, .expected = .lt },
        .{ .left = .{ .major = 1, .minor = 55 }, .right = .{ .major = 1, .minor = 41 }, .expected = .gt },
        .{ .left = .{ .major = 1, .minor = 10 }, .right = .{ .major = 1, .minor = 10 }, .expected = .eq },
        .{
            .left = .{ .major = 2, .minor = 0 },
            .right = .{ .major = 1, .minor = 255 },
            .expected = .gt,
        },
    };

    for (cases) |case| {
        try std.testing.expectEqual(case.expected, case.left.order(case.right));
    }
}

// is used in tests to generate SupportedVersion structs
fn getTestRange(min_version: []const u8, max_version: []const u8) !SupportedVersions {
    return .{
        .min_supported_version = try Version.parse_version(min_version),
        .max_supported_version = try Version.parse_version(max_version),
    };
}

test "test supported version" {
    const supported_range = try getTestRange("1.40", "2.5");

    try std.testing.expect(supported_range.isSupported(try Version.parse_version("1.40")));
    try std.testing.expect(supported_range.isSupported(try Version.parse_version("2.0")));
    try std.testing.expect(supported_range.isSupported(try Version.parse_version("2.5")));
    try std.testing.expect(!supported_range.isSupported(try Version.parse_version("1.39")));
    try std.testing.expect(!supported_range.isSupported(try Version.parse_version("2.51")));
}

test "test version negotiation" {
    const supported_range = try getTestRange("1.40", "1.55");

    const cases = [_]struct {
        min: []const u8,
        max: []const u8,
        expected: []const u8,
    }{ .{ .min = "1.28", .max = "1.49", .expected = "1.49" }, .{ .min = "1.44", .max = "1.60", .expected = "1.55" }, .{
        .min = "1.24",
        .max = "1.40",
        .expected = "1.40",
    }, .{ .min = "1.55", .max = "1.60", .expected = "1.55" } };

    for (cases) |case| {
        try std.testing.expectEqual(try Version.parse_version(case.expected), try supported_range.negotiate(try getTestRange(case.min, case.max)));
    }
}
