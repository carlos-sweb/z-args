const std = @import("std");
const zargs = @import("zargs");
const Builder = zargs.Builder;

fn makeParser(allocator: std.mem.Allocator) !Builder.Parser {
    var p = Builder.Parser.init(allocator);
    errdefer p.deinit();
    try p.addFlag(.{ .name = "verbose", .short = 'v', .long = "verbose", .help = "Verbose mode" });
    try p.addFlag(.{ .name = "a", .short = 'a', .long = "add", .help = "A flag" });
    try p.addFlag(.{ .name = "b", .short = 'b', .long = "bold", .help = "B flag" });
    try p.addFlag(.{ .name = "c", .short = 'c', .long = "cool", .help = "C flag" });
    try p.addFlag(.{ .name = "quiet", .short = 'q', .long = "quiet", .help = "Quiet mode" });
    try p.addOption(.{ .name = "output", .short = 'o', .long = "output", .help = "Output file" });
    return p;
}

test "registration + parse: short and long, = and separate value" {
    const allocator = std.testing.allocator;
    var p = try makeParser(allocator);
    defer p.deinit();

    const args = [_][:0]const u8{ "-v", "--output=out.txt", "input.txt" };
    var result = try p.parse(allocator, &args, null);
    defer result.deinit(allocator);

    try std.testing.expect(result.flag("verbose"));
    try std.testing.expectEqualStrings("out.txt", result.option("output").?);
    try std.testing.expectEqualStrings("input.txt", result.positionals.items[0]);

    var p2 = try makeParser(allocator);
    defer p2.deinit();
    const args2 = [_][:0]const u8{ "--verbose", "--output", "out.txt" };
    var result2 = try p2.parse(allocator, &args2, null);
    defer result2.deinit(allocator);
    try std.testing.expect(result2.flag("verbose"));
    try std.testing.expectEqualStrings("out.txt", result2.option("output").?);
}

test "short-option bundle, all flags" {
    const allocator = std.testing.allocator;
    var p = try makeParser(allocator);
    defer p.deinit();

    const args = [_][:0]const u8{"-abc"};
    var result = try p.parse(allocator, &args, null);
    defer result.deinit(allocator);

    try std.testing.expect(result.flag("a"));
    try std.testing.expect(result.flag("b"));
    try std.testing.expect(result.flag("c"));
}

test "bundle ending in a value option: attached remainder" {
    const allocator = std.testing.allocator;
    var p = try makeParser(allocator);
    defer p.deinit();

    const args = [_][:0]const u8{"-vofile.txt"};
    var result = try p.parse(allocator, &args, null);
    defer result.deinit(allocator);

    try std.testing.expect(result.flag("verbose"));
    try std.testing.expectEqualStrings("file.txt", result.option("output").?);
}

test "bundle ending in a value option: next-token fallback (deliberate divergence from Crystal)" {
    const allocator = std.testing.allocator;
    var p = try makeParser(allocator);
    defer p.deinit();

    const args = [_][:0]const u8{ "-vo", "file.txt" };
    var result = try p.parse(allocator, &args, null);
    defer result.deinit(allocator);

    try std.testing.expect(result.flag("verbose"));
    try std.testing.expectEqualStrings("file.txt", result.option("output").?);
}

test "bundle with an unrecognized char fails the whole token" {
    const allocator = std.testing.allocator;
    var p = try makeParser(allocator);
    defer p.deinit();

    const args = [_][:0]const u8{"-vz"};
    var diag: Builder.Diagnostics = .{};
    try std.testing.expectError(error.UnknownOption, p.parse(allocator, &args, &diag));
    try std.testing.expectEqualStrings("-vz", diag.raw.?);
}

test "unknown long option" {
    const allocator = std.testing.allocator;
    var p = try makeParser(allocator);
    defer p.deinit();

    const args = [_][:0]const u8{"--nope"};
    var diag: Builder.Diagnostics = .{};
    try std.testing.expectError(error.UnknownOption, p.parse(allocator, &args, &diag));
    try std.testing.expectEqualStrings("nope", diag.long.?);
}

test "long flag given =value when it takes none" {
    const allocator = std.testing.allocator;
    var p = try makeParser(allocator);
    defer p.deinit();

    const args = [_][:0]const u8{"--verbose=x"};
    var diag: Builder.Diagnostics = .{};
    try std.testing.expectError(error.UnexpectedValue, p.parse(allocator, &args, &diag));
    try std.testing.expectEqualStrings("verbose", diag.long.?);
}

test "missing value at end of argv: standalone short and long" {
    const allocator = std.testing.allocator;
    var p = try makeParser(allocator);
    defer p.deinit();
    const args = [_][:0]const u8{"-o"};
    var diag: Builder.Diagnostics = .{};
    try std.testing.expectError(error.MissingValue, p.parse(allocator, &args, &diag));
    try std.testing.expectEqual(@as(?u8, 'o'), diag.short);

    var p2 = try makeParser(allocator);
    defer p2.deinit();
    const args2 = [_][:0]const u8{"--output"};
    var diag2: Builder.Diagnostics = .{};
    try std.testing.expectError(error.MissingValue, p2.parse(allocator, &args2, &diag2));
    try std.testing.expectEqualStrings("output", diag2.long.?);
}

test "-- terminator and positionals" {
    const allocator = std.testing.allocator;
    var p = try makeParser(allocator);
    defer p.deinit();

    const args = [_][:0]const u8{ "--", "-v", "pos" };
    var result = try p.parse(allocator, &args, null);
    defer result.deinit(allocator);

    try std.testing.expect(!result.flag("verbose"));
    try std.testing.expectEqualStrings("-v", result.positionals.items[0]);
    try std.testing.expectEqualStrings("pos", result.positionals.items[1]);
}

test "requires: violated and satisfied" {
    const allocator = std.testing.allocator;

    var p = try makeParser(allocator);
    defer p.deinit();
    try p.requires("output", "verbose");

    const bad_args = [_][:0]const u8{"--output=out.txt"};
    var diag: Builder.Diagnostics = .{};
    try std.testing.expectError(error.MissingRequirement, p.parse(allocator, &bad_args, &diag));
    try std.testing.expectEqualStrings("output", diag.name.?);

    const good_args = [_][:0]const u8{ "--output=out.txt", "--verbose" };
    var result = try p.parse(allocator, &good_args, null);
    defer result.deinit(allocator);
    try std.testing.expect(result.flag("verbose"));
}

test "conflicts: both given" {
    const allocator = std.testing.allocator;

    var p = try makeParser(allocator);
    defer p.deinit();
    try p.conflicts("quiet", "verbose");

    const args = [_][:0]const u8{ "--quiet", "--verbose" };
    var diag: Builder.Diagnostics = .{};
    try std.testing.expectError(error.ConflictingOptions, p.parse(allocator, &args, &diag));
    try std.testing.expectEqualStrings("quiet", diag.name.?);
}

test "usageAlloc includes banner and registered help text" {
    const allocator = std.testing.allocator;
    var p = try makeParser(allocator);
    defer p.deinit();
    p.setBanner("Usage: myapp [options]");

    const usage = try p.usageAlloc(allocator);
    defer allocator.free(usage);

    try std.testing.expect(std.mem.indexOf(u8, usage, "Usage: myapp [options]") != null);
    try std.testing.expect(std.mem.indexOf(u8, usage, "-v, --verbose") != null);
    try std.testing.expect(std.mem.indexOf(u8, usage, "Verbose mode") != null);
    try std.testing.expect(std.mem.indexOf(u8, usage, "-o VALUE, --output=VALUE") != null);
}
