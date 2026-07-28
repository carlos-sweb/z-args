//! `Builder` tier: imperative runtime registration, auto-generated usage
//! text, and cross-flag validation (`requires`/`conflicts`) -- ground-
//! truthed against real Crystal `OptionParser` (source read directly from
//! `/usr/share/crystal/src/option_parser.cr`, not assumed), with one
//! deliberate divergence documented below.
//!
//! Unlike `Simple.Parser`, this tier doesn't expose a pull iterator:
//! `Parser.parse()` walks all of `args` in one call and returns a `Result`
//! queryable by name, matching real `OptionParser#parse`'s whole-parse-at-
//! once contract. That's also why this tier doesn't build on top of
//! `Simple.Parser` internally -- their low-level contracts genuinely
//! differ (yield-one-token-and-continue vs validate-then-apply), not just
//! their surface API. `OptionKind` is the one piece reused as-is, since
//! the concept ("does this option consume a value") is identical.
//!
//! Short-option bundles are validated atomically before anything in them
//! is applied (`-vz` with `z` unregistered fails the whole token, matching
//! Crystal's `validate_bundle`/`handle_bundled_short_options`) -- but a
//! bundle's trailing value-taking option with nothing left in the token
//! (`-vo` with no attached value) falls back to the next argv token here,
//! rather than Crystal's silent `""`: ground-truthed straight from
//! `handle_bundled_short_options`'s `arg[(index + 2)..]` (an out-of-bounds
//! Crystal slice returns `""`, not nil -- no next-token lookup happens for
//! a bundled value option, and `missing_option` never fires either, unlike
//! a *standalone* `-o`). That's a plausible oversight in Crystal rather
//! than a deliberate feature; this tier uses `Simple`'s already-shipped
//! next-token-fallback rule instead, so the two tiers don't surprise a
//! caller climbing from one to the other.
//!
//! `requires`/`conflicts` aren't a real `OptionParser` feature -- nothing
//! in its source implements them. They're this taxonomy's own addition to
//! the Builder rung (see `args.md`'s Tier 2 sketch), designed fresh here.
//! Likewise, Crystal's `invalid_option`/`missing_option` overridable
//! callbacks (default: raise) don't need a callback-registration
//! mechanism here at all -- `Error` returned from `.parse()` plus a plain
//! `catch` already gives the caller that same control, with less API
//! surface than Crystal needs for it.
const std = @import("std");
const simple = @import("simple.zig");

pub const OptionKind = simple.OptionKind;

/// `name` is the `Result` lookup key -- independent of how the option is
/// spelled on the command line (`short`/`long`), so callers aren't forced
/// to pick one spelling as canonical for their own code.
pub const Spec = struct {
    name: []const u8,
    /// e.g. `'v'` for `-v`.
    short: ?u8 = null,
    /// e.g. `"verbose"` for `--verbose`.
    long: ?[]const u8 = null,
    kind: OptionKind = .flag,
    /// Shown in `usageAlloc()`'s output.
    help: []const u8 = "",
    /// Shown after the flag in `usageAlloc()`'s output for `.kind = .value`
    /// specs, e.g. `-o VALUE, --output=VALUE`.
    value_name: []const u8 = "VALUE",
};

/// Populated on error by `Parser.parse()` when non-null, naming whichever
/// option/token was the problem.
pub const Diagnostics = struct {
    short: ?u8 = null,
    long: ?[]const u8 = null,
    /// The whole invalid token, for an unrecognized short-option bundle
    /// (which is rejected as a unit, not per character -- see file docs).
    raw: ?[]const u8 = null,
    /// The `Spec.name` at fault for a `.requires`/`.conflicts` violation.
    name: ?[]const u8 = null,
};

pub const Error = error{
    UnknownOption,
    MissingValue,
    UnexpectedValue,
    /// A `.requires` rule was violated.
    MissingRequirement,
    /// A `.conflicts` rule was violated.
    ConflictingOptions,
    OutOfMemory,
};

const Requirement = struct { dependent: []const u8, needs: []const u8 };
const Conflict = struct { a: []const u8, b: []const u8 };

/// The outcome of `Parser.parse()`, queried by `Spec.name`.
pub const Result = struct {
    flags: std.StringHashMapUnmanaged(void) = .empty,
    options: std.StringHashMapUnmanaged([]const u8) = .empty,
    positionals: std.ArrayList([]const u8) = .empty,

    pub fn flag(self: Result, name: []const u8) bool {
        return self.flags.contains(name);
    }

    pub fn option(self: Result, name: []const u8) ?[]const u8 {
        return self.options.get(name);
    }

    fn given(self: Result, name: []const u8) bool {
        return self.flag(name) or self.options.contains(name);
    }

    pub fn deinit(self: *Result, allocator: std.mem.Allocator) void {
        self.flags.deinit(allocator);
        self.options.deinit(allocator);
        self.positionals.deinit(allocator);
    }
};

pub const Parser = struct {
    allocator: std.mem.Allocator,
    banner: []const u8 = "",
    specs: std.ArrayList(Spec) = .empty,
    requirements: std.ArrayList(Requirement) = .empty,
    conflicts_list: std.ArrayList(Conflict) = .empty,

    pub fn init(allocator: std.mem.Allocator) Parser {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Parser) void {
        self.specs.deinit(self.allocator);
        self.requirements.deinit(self.allocator);
        self.conflicts_list.deinit(self.allocator);
    }

    pub fn setBanner(self: *Parser, text: []const u8) void {
        self.banner = text;
    }

    pub fn addFlag(self: *Parser, spec: Spec) !void {
        var s = spec;
        s.kind = .flag;
        try self.specs.append(self.allocator, s);
    }

    pub fn addOption(self: *Parser, spec: Spec) !void {
        var s = spec;
        s.kind = .value;
        try self.specs.append(self.allocator, s);
    }

    /// If `dependent` is given, `needs` must be given too.
    pub fn requires(self: *Parser, dependent: []const u8, needs: []const u8) !void {
        try self.requirements.append(self.allocator, .{ .dependent = dependent, .needs = needs });
    }

    /// `a` and `b` may not both be given.
    pub fn conflicts(self: *Parser, a: []const u8, b: []const u8) !void {
        try self.conflicts_list.append(self.allocator, .{ .a = a, .b = b });
    }

    /// Formats `banner` plus an aligned "flags   description" row per
    /// registered spec. Caller frees the returned slice.
    pub fn usageAlloc(self: *Parser, allocator: std.mem.Allocator) ![]u8 {
        var buf: std.ArrayList(u8) = .empty;
        errdefer buf.deinit(allocator);

        if (self.banner.len > 0) {
            try buf.print(allocator, "{s}\n", .{self.banner});
        }

        for (self.specs.items) |spec| {
            var flags_buf: std.ArrayList(u8) = .empty;
            defer flags_buf.deinit(allocator);

            if (spec.short) |s| {
                if (spec.kind == .value) {
                    try flags_buf.print(allocator, "-{c} {s}", .{ s, spec.value_name });
                } else {
                    try flags_buf.print(allocator, "-{c}", .{s});
                }
                if (spec.long != null) try flags_buf.appendSlice(allocator, ", ");
            }
            if (spec.long) |l| {
                if (spec.kind == .value) {
                    try flags_buf.print(allocator, "--{s}={s}", .{ l, spec.value_name });
                } else {
                    try flags_buf.print(allocator, "--{s}", .{l});
                }
            }
            try buf.print(allocator, "    {s:<28} {s}\n", .{ flags_buf.items, spec.help });
        }

        return buf.toOwnedSlice(allocator);
    }

    /// Runs the whole parse in one call (unlike `Simple.Parser.next()`'s
    /// one-token-per-call model). `diagnostics`, if non-null, is populated
    /// on error with which option/token was the problem.
    pub fn parse(self: *Parser, allocator: std.mem.Allocator, args: []const [:0]const u8, diagnostics: ?*Diagnostics) Error!Result {
        var result: Result = .{};
        errdefer result.deinit(allocator);

        var positional_only = false;
        var i: usize = 0;
        while (i < args.len) : (i += 1) {
            const tok = args[i];

            if (!positional_only and std.mem.eql(u8, tok, "--")) {
                positional_only = true;
                continue;
            }

            if (positional_only or tok.len < 2 or tok[0] != '-') {
                try result.positionals.append(allocator, tok);
                continue;
            }

            if (tok[1] == '-') {
                try self.applyLong(tok[2..], &i, args, &result, allocator, diagnostics);
                continue;
            }

            try self.applyShortBundle(tok, &i, args, &result, allocator, diagnostics);
        }

        try self.checkRules(&result, diagnostics);
        return result;
    }

    /// Resolves a `--name` or `--name=value` token (`rest` is everything
    /// after the leading `--`).
    fn applyLong(self: *Parser, rest: []const u8, i: *usize, args: []const [:0]const u8, result: *Result, allocator: std.mem.Allocator, diagnostics: ?*Diagnostics) Error!void {
        var name = rest;
        var inline_value: ?[]const u8 = null;
        if (std.mem.indexOfScalar(u8, rest, '=')) |eq| {
            name = rest[0..eq];
            inline_value = rest[eq + 1 ..];
        }

        const spec = self.findLong(name) orelse {
            if (diagnostics) |d| d.* = .{ .long = name };
            return Error.UnknownOption;
        };

        switch (spec.kind) {
            .flag => {
                if (inline_value != null) {
                    if (diagnostics) |d| d.* = .{ .short = spec.short, .long = spec.long };
                    return Error.UnexpectedValue;
                }
                try result.flags.put(allocator, spec.name, {});
            },
            .value => {
                const value = inline_value orelse blk: {
                    if (i.* + 1 >= args.len) {
                        if (diagnostics) |d| d.* = .{ .short = spec.short, .long = spec.long };
                        return Error.MissingValue;
                    }
                    i.* += 1;
                    break :blk args[i.*];
                };
                try result.options.put(allocator, spec.name, value);
            },
        }
    }

    /// Validates every character of a short-option bundle (`-abc`) before
    /// applying any of it -- an unrecognized char fails the whole token
    /// (`diagnostics.raw = tok`), matching Crystal's atomic
    /// `validate_bundle`. Validation stops at the first value-taking
    /// option (its remaining chars, or the next argv token, become its
    /// value); anything past that point is never re-interpreted as flags.
    fn applyShortBundle(self: *Parser, tok: []const u8, i: *usize, args: []const [:0]const u8, result: *Result, allocator: std.mem.Allocator, diagnostics: ?*Diagnostics) Error!void {
        const rest = tok[1..];

        var stop_index: ?usize = null;
        var idx: usize = 0;
        while (idx < rest.len) : (idx += 1) {
            const spec = self.findShort(rest[idx]) orelse {
                if (diagnostics) |d| d.* = .{ .raw = tok };
                return Error.UnknownOption;
            };
            if (spec.kind == .value) {
                stop_index = idx;
                break;
            }
        }

        const flag_count = stop_index orelse rest.len;
        var k: usize = 0;
        while (k < flag_count) : (k += 1) {
            const spec = self.findShort(rest[k]).?;
            try result.flags.put(allocator, spec.name, {});
        }

        if (stop_index) |si| {
            const spec = self.findShort(rest[si]).?;
            const attached = rest[si + 1 ..];
            const value = if (attached.len > 0) attached else blk: {
                if (i.* + 1 >= args.len) {
                    if (diagnostics) |d| d.* = .{ .short = spec.short, .long = spec.long };
                    return Error.MissingValue;
                }
                i.* += 1;
                break :blk args[i.*];
            };
            try result.options.put(allocator, spec.name, value);
        }
    }

    fn checkRules(self: *Parser, result: *const Result, diagnostics: ?*Diagnostics) Error!void {
        for (self.requirements.items) |req| {
            if (result.given(req.dependent) and !result.given(req.needs)) {
                if (diagnostics) |d| d.* = .{ .name = req.dependent };
                return Error.MissingRequirement;
            }
        }
        for (self.conflicts_list.items) |c| {
            if (result.given(c.a) and result.given(c.b)) {
                if (diagnostics) |d| d.* = .{ .name = c.a };
                return Error.ConflictingOptions;
            }
        }
    }

    fn findShort(self: *Parser, c: u8) ?Spec {
        for (self.specs.items) |spec| {
            if (spec.short == c) return spec;
        }
        return null;
    }

    fn findLong(self: *Parser, name: []const u8) ?Spec {
        for (self.specs.items) |spec| {
            if (spec.long) |l| {
                if (std.mem.eql(u8, l, name)) return spec;
            }
        }
        return null;
    }
};
