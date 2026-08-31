const std = @import("std");

pub const VersionError = error{ MissingDotDelimiter, WrongFormat, WrongMajor, WrongMinor };

pub const Version = struct {
    major: u8,
    minor: u8,

    // return the string version like "1.55"
    pub fn to_string(self: Version, allocator: std.mem.Allocator) ![]const u8 {
        return try std.fmt.allocPrint(allocator, "{d}.{d}", .{ self.major, self.minor });
    }

    // takes a version string and generates the Version struct
    pub fn parse_version(version: []const u8) VersionError!Version {
        _ = std.mem.findScalar(u8, version, '.') orelse return VersionError.MissingDotDelimiter;

        var iterator = std.mem.splitScalar(u8, version, '.');

        const major_str = iterator.next() orelse return VersionError.WrongMajor;
        const minor_str = iterator.next() orelse return VersionError.WrongMinor;

        const major = std.fmt.parseInt(u8, major_str, 10) catch return VersionError.WrongMajor;
        const minor = std.fmt.parseInt(u8, minor_str, 10) catch return VersionError.WrongMinor;

        return .{
            .major = major,
            .minor = minor,
        };
    }
};

pub const SupportedVersions = struct {
    min_supported_version: Version,
    max_supported_version: Version,

    pub fn isSupported(self: SupportedVersions, version: Version) bool {
        if (version.major <= self.max_supported_version.major and
            version.minor <= self.max_supported_version.minor and
            version.major >= self.min_supported_version.major and
            version.minor >= self.min_supported_version.minor)
        {
            return true;
        }

        return false;
    }
};

pub var suppored_versions: SupportedVersions = .{
    .max_supported_version = .{ .major = 1, .minor = 55 },

    .min_supported_version = .{ .major = 1, .minor = 40 },
};

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
