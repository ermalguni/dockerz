const std = @import("std");
const model = @import("../model.zig");

pub const Diagnostic = struct {
    buffer: [1024]u8 = undefined,
    len: usize = 0,

    pub fn text(self: *const Diagnostic) []const u8 {
        return self.buffer[0..self.len];
    }

    fn set(
        self: *Diagnostic,
        comptime fmt: []const u8,
        args: anytype,
    ) void {
        const message = std.fmt.bufPrint(
            &self.buffer,
            fmt,
            args,
        ) catch self.buffer[0..];

        self.len = message.len;
    }
};

pub fn lookup(
    environment: []const model.EnvironmentEntry,
    name: []const u8,
) ?[]const u8 {
    for (environment) |entry| {
        if (std.mem.eql(u8, entry.name, name))
            return entry.value;
    }

    return null;
}

pub fn expand(
    allocator: std.mem.Allocator,
    input: []const u8,
    environment: []const model.EnvironmentEntry,
    diagnostic: ?*Diagnostic,
) ![]const u8 {
    if (diagnostic) |d| d.len = 0;

    var output: std.ArrayList(u8) = .empty;
    errdefer output.deinit(allocator);

    try expandInto(
        allocator,
        input,
        environment,
        diagnostic,
        &output,
        0,
    );

    return output.toOwnedSlice(allocator);
}

fn nameStart(character: u8) bool {
    return std.ascii.isAlphabetic(character) or character == '_';
}

fn nameChar(character: u8) bool {
    return nameStart(character) or std.ascii.isDigit(character);
}

fn append(
    allocator: std.mem.Allocator,
    output: *std.ArrayList(u8),
    value: []const u8,
) !void {
    if (value.len > 1024 * 1024 -| output.items.len)
        return error.InterpolationTooLarge;

    try output.appendSlice(allocator, value);
}

fn expandInto(
    allocator: std.mem.Allocator,
    input: []const u8,
    environment: []const model.EnvironmentEntry,
    diagnostic: ?*Diagnostic,
    output: *std.ArrayList(u8),
    depth: usize,
) anyerror!void {
    if (depth > 32) return error.InterpolationTooDeep;

    var i: usize = 0;

    while (i < input.len) {
        if (input[i] != '$') {
            const start = i;

            while (i < input.len and input[i] != '$') : (i += 1) {}

            try append(allocator, output, input[start..i]);
            continue;
        }

        i += 1;

        if (i < input.len and input[i] == '$') {
            try append(allocator, output, "$");
            i += 1;
            continue;
        }

        const braced = i < input.len and input[i] == '{';
        if (braced) i += 1;

        if (i == input.len or !nameStart(input[i])) {
            if (!braced) {
                try append(allocator, output, "$");
                continue;
            }

            if (diagnostic) |d| {
                d.set(
                    "invalid variable expression near byte {d}; use $$ for a literal dollar",
                    .{i},
                );
            }

            return error.InvalidInterpolation;
        }

        const start = i;
        while (i < input.len and nameChar(input[i])) : (i += 1) {}

        const name = input[start..i];
        const value = lookup(environment, name);

        if (!braced) {
            if (value == null) {
                std.log.warn(
                    "Compose variable '{s}' is unset; substituting an empty string",
                    .{name},
                );
            }

            try append(allocator, output, value orelse "");
            continue;
        }

        if (i == input.len) return error.InvalidInterpolation;

        if (input[i] == '}') {
            if (value == null) {
                std.log.warn(
                    "Compose variable '{s}' is unset; substituting an empty string",
                    .{name},
                );
            }

            try append(allocator, output, value orelse "");
            i += 1;
            continue;
        }

        const colon = input[i] == ':';
        if (colon) i += 1;

        if (i == input.len or
            std.mem.indexOfScalar(u8, "-?+", input[i]) == null)
        {
            return error.InvalidInterpolation;
        }

        const operator = input[i];
        i += 1;

        const word_start = i;
        var nesting: usize = 0;

        while (i < input.len) : (i += 1) {
            if (input[i] == '$' and i + 1 < input.len) {
                if (input[i + 1] == '$') {
                    if (i + 2 < input.len and input[i + 2] == '{') {
                        nesting += 1;
                        i += 2;
                    } else {
                        i += 1;
                    }

                    continue;
                }

                if (input[i + 1] == '{') {
                    nesting += 1;
                    i += 1;
                    continue;
                }
            }

            if (input[i] == '}') {
                if (nesting == 0) break;
                nesting -= 1;
            }
        }

        if (i == input.len) return error.InvalidInterpolation;

        const word = input[word_start..i];
        i += 1;

        const present = value != null and
            (!colon or value.?.len != 0);

        switch (operator) {
            '-' => if (present) {
                try append(allocator, output, value.?);
            } else {
                try expandInto(
                    allocator,
                    word,
                    environment,
                    diagnostic,
                    output,
                    depth + 1,
                );
            },
            '+' => if (present) {
                try expandInto(
                    allocator,
                    word,
                    environment,
                    diagnostic,
                    output,
                    depth + 1,
                );
            },
            '?' => if (present) {
                try append(allocator, output, value.?);
            } else {
                var message: std.ArrayList(u8) = .empty;
                defer message.deinit(allocator);

                try expandInto(
                    allocator,
                    word,
                    environment,
                    diagnostic,
                    &message,
                    depth + 1,
                );

                if (diagnostic) |d| {
                    d.set(
                        "required variable {s}: {s}",
                        .{
                            name,
                            if (message.items.len == 0)
                                "a value must be supplied explicitly"
                            else
                                message.items,
                        },
                    );
                }

                return error.RequiredVariable;
            },
            else => unreachable,
        }
    }
}

/// Splits arguments without executing a shell or expanding variables.
pub fn splitCommand(
    allocator: std.mem.Allocator,
    input: []const u8,
) ![]const []const u8 {
    var words: std.ArrayList([]const u8) = .empty;

    errdefer {
        for (words.items) |word| allocator.free(word);
        words.deinit(allocator);
    }

    var word: std.ArrayList(u8) = .empty;
    defer word.deinit(allocator);

    var quote: enum { none, single, double } = .none;
    var started = false;
    var i: usize = 0;

    while (i < input.len) : (i += 1) {
        const character = input[i];

        if (character == 0) return error.InvalidCommand;

        if (quote == .none and std.ascii.isWhitespace(character)) {
            if (started) {
                try words.ensureUnusedCapacity(allocator, 1);
                words.appendAssumeCapacity(
                    try allocator.dupe(u8, word.items),
                );

                word.clearRetainingCapacity();
                started = false;
            }

            continue;
        }

        if (quote != .double and character == '\'') {
            quote = if (quote == .single) .none else .single;
            started = true;
            continue;
        }

        if (quote != .single and character == '"') {
            quote = if (quote == .double) .none else .double;
            started = true;
            continue;
        }

        if (quote != .single and character == '\\') {
            if (i + 1 == input.len)
                return error.UnterminatedCommandEscape;

            const next = input[i + 1];

            if (quote == .none or
                std.mem.indexOfScalar(u8, "$`\"\\\n", next) != null)
            {
                i += 1;

                if (next != '\n') {
                    try word.append(allocator, next);
                    started = true;
                }

                continue;
            }
        }

        try word.append(allocator, character);
        started = true;
    }

    if (quote != .none) return error.UnterminatedCommandQuote;

    if (started) {
        try words.ensureUnusedCapacity(allocator, 1);
        words.appendAssumeCapacity(
            try allocator.dupe(u8, word.items),
        );
    }

    return words.toOwnedSlice(allocator);
}
