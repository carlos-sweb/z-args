const std = @import("std");
const zargs = @import("zargs");
const Simple = zargs.Simple;
const Parser = Simple.Parser;
const Token = Simple.Token;
const OptionSpec = Simple.OptionSpec;

// Same shape as the ground-truth getopt_long(3) reference program used to
// derive this tier's behavior.
const specs = [_]OptionSpec{
    .{ .short = 'v', .long = "verbose", .kind = .flag },
    .{ .short = 'a', .long = "add", .kind = .flag },
    .{ .short = 'b', .long = "bold", .kind = .flag },
    .{ .short = 'c', .long = "cool", .kind = .flag },
    .{ .short = 'o', .long = "output", .kind = .value },
};

fn expectOptStr(expected: ?[]const u8, actual: ?[]const u8) !void {
    if (expected == null or actual == null) {
        try std.testing.expectEqual(expected, actual);
        return;
    }
    try std.testing.expectEqualStrings(expected.?, actual.?);
}

fn expectFlag(token: Token, short: ?u8, long: ?[]const u8) !void {
    switch (token) {
        .flag => |f| {
            try std.testing.expectEqual(short, f.short);
            try expectOptStr(long, f.long);
        },
        else => return error.TestUnexpectedResult,
    }
}

fn expectOption(token: Token, short: ?u8, long: ?[]const u8, value: []const u8) !void {
    switch (token) {
        .option => |o| {
            try std.testing.expectEqual(short, o.short);
            try expectOptStr(long, o.long);
            try std.testing.expectEqualStrings(value, o.value);
        },
        else => return error.TestUnexpectedResult,
    }
}

fn expectPositional(token: Token, text: []const u8) !void {
    switch (token) {
        .positional => |p| try std.testing.expectEqualStrings(text, p),
        else => return error.TestUnexpectedResult,
    }
}

fn expectUnknown(token: Token, short: ?u8, long: ?[]const u8) !void {
    switch (token) {
        .unknown_option => |u| {
            try std.testing.expectEqual(short, u.short);
            try expectOptStr(long, u.long);
        },
        else => return error.TestUnexpectedResult,
    }
}

fn expectMissingValue(token: Token, short: ?u8, long: ?[]const u8) !void {
    switch (token) {
        .missing_value => |m| {
            try std.testing.expectEqual(short, m.short);
            try expectOptStr(long, m.long);
        },
        else => return error.TestUnexpectedResult,
    }
}

fn expectUnexpectedValue(token: Token, short: ?u8, long: ?[]const u8, value: []const u8) !void {
    switch (token) {
        .unexpected_value => |u| {
            try std.testing.expectEqual(short, u.short);
            try expectOptStr(long, u.long);
            try std.testing.expectEqualStrings(value, u.value);
        },
        else => return error.TestUnexpectedResult,
    }
}

fn expectEnd(token: Token) !void {
    try std.testing.expect(token == .end);
}

test "standalone short flag" {
    const args = [_][:0]const u8{"-v"};
    var p = Parser.init(&args, &specs);
    try expectFlag(p.next(), 'v', "verbose");
    try expectEnd(p.next());
}

test "bundled short flags, all no-value" {
    const args = [_][:0]const u8{"-abc"};
    var p = Parser.init(&args, &specs);
    try expectFlag(p.next(), 'a', "add");
    try expectFlag(p.next(), 'b', "bold");
    try expectFlag(p.next(), 'c', "cool");
    try expectEnd(p.next());
}

test "short option, attached value" {
    const args = [_][:0]const u8{"-ofile.txt"};
    var p = Parser.init(&args, &specs);
    try expectOption(p.next(), 'o', "output", "file.txt");
    try expectEnd(p.next());
}

test "short option, separate value" {
    const args = [_][:0]const u8{ "-o", "file.txt" };
    var p = Parser.init(&args, &specs);
    try expectOption(p.next(), 'o', "output", "file.txt");
    try expectEnd(p.next());
}

test "bundle ending in a value-option with separate value" {
    const args = [_][:0]const u8{ "-vo", "file.txt" };
    var p = Parser.init(&args, &specs);
    try expectFlag(p.next(), 'v', "verbose");
    try expectOption(p.next(), 'o', "output", "file.txt");
    try expectEnd(p.next());
}

test "bundle where a value-option's remainder is the value" {
    const args = [_][:0]const u8{"-vofile.txt"};
    var p = Parser.init(&args, &specs);
    try expectFlag(p.next(), 'v', "verbose");
    try expectOption(p.next(), 'o', "output", "file.txt");
    try expectEnd(p.next());
}

test "long flag" {
    const args = [_][:0]const u8{"--verbose"};
    var p = Parser.init(&args, &specs);
    try expectFlag(p.next(), 'v', "verbose");
    try expectEnd(p.next());
}

test "long option, = value" {
    const args = [_][:0]const u8{"--output=file.txt"};
    var p = Parser.init(&args, &specs);
    try expectOption(p.next(), 'o', "output", "file.txt");
    try expectEnd(p.next());
}

test "long option, separate value" {
    const args = [_][:0]const u8{ "--output", "file.txt" };
    var p = Parser.init(&args, &specs);
    try expectOption(p.next(), 'o', "output", "file.txt");
    try expectEnd(p.next());
}

test "long flag given =value when it takes none" {
    const args = [_][:0]const u8{"--verbose=x"};
    var p = Parser.init(&args, &specs);
    try expectUnexpectedValue(p.next(), 'v', "verbose", "x");
    try expectEnd(p.next());
}

test "-- terminator: subsequent flag-shaped tokens become positionals" {
    const args = [_][:0]const u8{ "--", "-v", "pos" };
    var p = Parser.init(&args, &specs);
    try expectPositional(p.next(), "-v");
    try expectPositional(p.next(), "pos");
    try expectEnd(p.next());
}

test "bare - is a positional, never an option" {
    const args = [_][:0]const u8{ "-", "pos2" };
    var p = Parser.init(&args, &specs);
    try expectPositional(p.next(), "-");
    try expectPositional(p.next(), "pos2");
    try expectEnd(p.next());
}

test "interspersed positionals and options preserve original order" {
    const args = [_][:0]const u8{ "pos1", "-v", "pos2" };
    var p = Parser.init(&args, &specs);
    try expectPositional(p.next(), "pos1");
    try expectFlag(p.next(), 'v', "verbose");
    try expectPositional(p.next(), "pos2");
    try expectEnd(p.next());
}

test "unknown short option, then parsing continues" {
    const args = [_][:0]const u8{"-vzb"};
    var p = Parser.init(&args, &specs);
    try expectFlag(p.next(), 'v', "verbose");
    try expectUnknown(p.next(), 'z', null);
    try expectFlag(p.next(), 'b', "bold");
    try expectEnd(p.next());
}

test "unknown long option" {
    const args = [_][:0]const u8{"--nope"};
    var p = Parser.init(&args, &specs);
    try expectUnknown(p.next(), null, "nope");
    try expectEnd(p.next());
}

test "missing value at end of argv: short" {
    const args = [_][:0]const u8{"-o"};
    var p = Parser.init(&args, &specs);
    try expectMissingValue(p.next(), 'o', "output");
    try expectEnd(p.next());
}

test "missing value at end of argv: short, mid-bundle" {
    const args = [_][:0]const u8{"-vo"};
    var p = Parser.init(&args, &specs);
    try expectFlag(p.next(), 'v', "verbose");
    try expectMissingValue(p.next(), 'o', "output");
    try expectEnd(p.next());
}

test "missing value at end of argv: long" {
    const args = [_][:0]const u8{"--output"};
    var p = Parser.init(&args, &specs);
    try expectMissingValue(p.next(), 'o', "output");
    try expectEnd(p.next());
}

test "empty argv yields immediate, idempotent end" {
    const args = [_][:0]const u8{};
    var p = Parser.init(&args, &specs);
    try expectEnd(p.next());
    try expectEnd(p.next());
}

test "the next argv token is consumed as a value unconditionally, even if it looks like a flag" {
    const args = [_][:0]const u8{ "-o", "-v" };
    var p = Parser.init(&args, &specs);
    try expectOption(p.next(), 'o', "output", "-v");
    try expectEnd(p.next());
}
