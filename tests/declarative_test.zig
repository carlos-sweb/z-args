const std = @import("std");
const zargs = @import("zargs");
const Declarative = zargs.Declarative;

const Mode = enum { fast, slow };

const Cli = struct {
    verbose: Declarative.Flag(bool, .{ .short = 'v', .long = "verbose", .help = "Verbose mode", .default = false }),
    color: Declarative.Flag(bool, .{ .short = 'c', .long = "color", .help = "Color output", .default = true }),
    retries: Declarative.Flag(u32, .{ .short = 'r', .help = "Retry count", .default = 3 }),
    rate: Declarative.Flag(f64, .{ .long = "rate", .default = 1.5 }),
    mode: Declarative.Flag(Mode, .{ .long = "mode", .default = .fast }),
    output: Declarative.Flag([]const u8, .{ .short = 'o', .long = "output", .help = "Output file" }),
    input: Declarative.Positional([]const u8, .{ .help = "Input file" }),
    extra: Declarative.Positional([]const []const u8, .{}),
};

test "defaults applied, required flag/positional filled from short/long/=/separate value" {
    const allocator = std.testing.allocator;
    const args = [_][:0]const u8{ "-v", "--output=out.txt", "input.txt" };
    const result = try Declarative.parseStruct(Cli, allocator, &args, null);
    defer allocator.free(result.extra.value);

    try std.testing.expect(result.verbose.value);
    try std.testing.expect(result.color.value); // default true, untouched
    try std.testing.expectEqual(@as(u32, 3), result.retries.value);
    try std.testing.expectEqual(@as(f64, 1.5), result.rate.value);
    try std.testing.expectEqual(Mode.fast, result.mode.value);
    try std.testing.expectEqualStrings("out.txt", result.output.value);
    try std.testing.expectEqualStrings("input.txt", result.input.value);
    try std.testing.expectEqual(@as(usize, 0), result.extra.value.len);
}

test "required flag omitted -> MissingRequiredFlag with field diagnostics" {
    const allocator = std.testing.allocator;
    const args = [_][:0]const u8{"input.txt"};
    var diag: Declarative.Diagnostics = .{};
    try std.testing.expectError(error.MissingRequiredFlag, Declarative.parseStruct(Cli, allocator, &args, &diag));
    try std.testing.expectEqualStrings("output", diag.field.?);
}

test "required positional omitted -> MissingRequiredPositional" {
    const allocator = std.testing.allocator;
    const args = [_][:0]const u8{"--output=out.txt"};
    var diag: Declarative.Diagnostics = .{};
    try std.testing.expectError(error.MissingRequiredPositional, Declarative.parseStruct(Cli, allocator, &args, &diag));
    try std.testing.expectEqualStrings("input", diag.field.?);
}

test "bool negation: --no-x flips a default-true bool; --no-x on a default-false bool is unknown" {
    const allocator = std.testing.allocator;
    const args = [_][:0]const u8{ "--no-color", "--output=out.txt", "input.txt" };
    const result = try Declarative.parseStruct(Cli, allocator, &args, null);
    defer allocator.free(result.extra.value);
    try std.testing.expect(!result.color.value);

    const bad_args = [_][:0]const u8{ "--no-verbose", "--output=out.txt", "input.txt" };
    var diag: Declarative.Diagnostics = .{};
    try std.testing.expectError(error.UnknownOption, Declarative.parseStruct(Cli, allocator, &bad_args, &diag));
    try std.testing.expectEqualStrings("no-verbose", diag.long.?);
}

test "integer/float/enum coercion: success and InvalidValue" {
    const allocator = std.testing.allocator;
    const args = [_][:0]const u8{ "-r", "7", "--rate", "2.25", "--mode", "slow", "--output=out.txt", "input.txt" };
    const result = try Declarative.parseStruct(Cli, allocator, &args, null);
    defer allocator.free(result.extra.value);
    try std.testing.expectEqual(@as(u32, 7), result.retries.value);
    try std.testing.expectEqual(@as(f64, 2.25), result.rate.value);
    try std.testing.expectEqual(Mode.slow, result.mode.value);

    const bad_int = [_][:0]const u8{ "-r", "not-a-number", "--output=out.txt", "input.txt" };
    var diag: Declarative.Diagnostics = .{};
    try std.testing.expectError(error.InvalidValue, Declarative.parseStruct(Cli, allocator, &bad_int, &diag));
    try std.testing.expectEqualStrings("retries", diag.field.?);

    const bad_enum = [_][:0]const u8{ "--mode", "sideways", "--output=out.txt", "input.txt" };
    try std.testing.expectError(error.InvalidValue, Declarative.parseStruct(Cli, allocator, &bad_enum, null));
}

test "positional order and -- terminator" {
    const allocator = std.testing.allocator;
    const args = [_][:0]const u8{ "--output=out.txt", "--", "-v", "input.txt" };
    const result = try Declarative.parseStruct(Cli, allocator, &args, null);
    defer allocator.free(result.extra.value);
    try std.testing.expect(!result.verbose.value); // "-v" after "--" is positional, not a flag
    try std.testing.expectEqualStrings("-v", result.input.value);
    try std.testing.expectEqualStrings("input.txt", result.extra.value[0]);
}

test "rest-collector gathers overflow positionals, freed cleanly" {
    const allocator = std.testing.allocator;
    const args = [_][:0]const u8{ "--output=out.txt", "input.txt", "extra1", "extra2" };
    const result = try Declarative.parseStruct(Cli, allocator, &args, null);
    defer allocator.free(result.extra.value);
    try std.testing.expectEqual(@as(usize, 2), result.extra.value.len);
    try std.testing.expectEqualStrings("extra1", result.extra.value[0]);
    try std.testing.expectEqualStrings("extra2", result.extra.value[1]);
}

const NoRestCli = struct {
    output: Declarative.Flag([]const u8, .{ .short = 'o', .long = "output" }),
    input: Declarative.Positional([]const u8, .{}),
};

test "extra positional with no rest-collector field -> TooManyPositionals" {
    const allocator = std.testing.allocator;
    const args = [_][:0]const u8{ "--output=out.txt", "input.txt", "extra" };
    try std.testing.expectError(error.TooManyPositionals, Declarative.parseStruct(NoRestCli, allocator, &args, null));
}

const BundleCli = struct {
    a: Declarative.Flag(bool, .{ .short = 'a', .default = false }),
    b: Declarative.Flag(bool, .{ .short = 'b', .default = false }),
    c: Declarative.Flag(bool, .{ .short = 'c', .default = false }),
    out: Declarative.Flag([]const u8, .{ .short = 'o', .default = "a.out" }),
};

test "short-option bundle: all flags, and atomicity on an unrecognized char" {
    const allocator = std.testing.allocator;
    const args = [_][:0]const u8{"-abc"};
    const result = try Declarative.parseStruct(BundleCli, allocator, &args, null);
    try std.testing.expect(result.a.value and result.b.value and result.c.value);

    const bundle_value = [_][:0]const u8{"-aofile.txt"};
    const result2 = try Declarative.parseStruct(BundleCli, allocator, &bundle_value, null);
    try std.testing.expect(result2.a.value);
    try std.testing.expectEqualStrings("file.txt", result2.out.value);

    const bad = [_][:0]const u8{"-az"};
    var diag: Declarative.Diagnostics = .{};
    try std.testing.expectError(error.UnknownOption, Declarative.parseStruct(BundleCli, allocator, &bad, &diag));
    try std.testing.expectEqualStrings("-az", diag.raw.?);
}

test "usageAlloc includes banner, help text, and required annotation" {
    const allocator = std.testing.allocator;
    const usage = try Declarative.usageAlloc(Cli, allocator, "Usage: myapp [options] <input>");
    defer allocator.free(usage);

    try std.testing.expect(std.mem.indexOf(u8, usage, "Usage: myapp [options] <input>") != null);
    try std.testing.expect(std.mem.indexOf(u8, usage, "-v, --verbose") != null);
    try std.testing.expect(std.mem.indexOf(u8, usage, "Verbose mode") != null);
    try std.testing.expect(std.mem.indexOf(u8, usage, "-o, --output") != null);
    try std.testing.expect(std.mem.indexOf(u8, usage, "(required)") != null);
}
