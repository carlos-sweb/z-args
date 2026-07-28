//! `Simple` tier: a POSIX/GNU `getopt_long`-style flag tokenizer. No types,
//! no auto-generated help, no cross-flag validation -- just the minimal
//! contract a Unix CLI is expected to honor (see Nim's `std/parseopt` for
//! the reference "mature ecosystem" shape this tier targets).
//!
//! `Parser` makes zero allocations and does zero I/O: it only slices into
//! the caller's `args`, matching this tier's "cheapest rung" cost model.
//! `next()` is infallible and never stops the walk on a bad flag, mirroring
//! real `getopt()`'s behavior of reporting one bad option per call and
//! continuing -- ground-truthed against a real `getopt_long(3)` reference
//! program (bundling, attached-vs-separate values, `=`-long-options,
//! missing-value, unknown-option, `--`, bare `-`, and the surprising
//! "next token is consumed as a value unconditionally" case all confirmed
//! to match libc's behavior byte-for-byte before this was written).
//!
//! Deliberately non-permuting (unlike GNU `getopt`'s default): positionals
//! are returned interleaved in their original argv order, never reordered
//! after the options. Permutation is a heavier, higher-tier nicety.
const std = @import("std");

/// Whether an option is a presence/absence flag, or consumes a value (the
/// rest of its short-option bundle, a `--long=value`, or the next argv
/// token).
pub const OptionKind = enum { flag, value };

/// Registers one option's short and/or long spelling and whether it takes
/// a value. Set both `short` and `long` to accept either spelling for the
/// same option; leave the other `null` if it has only one form.
pub const OptionSpec = struct {
    /// e.g. `'v'` for `-v`.
    short: ?u8 = null,
    /// e.g. `"verbose"` for `--verbose`.
    long: ?[]const u8 = null,
    kind: OptionKind = .flag,
};

/// One parsed unit of `argv`, returned one at a time by `Parser.next()`.
/// Error conditions (`.unknown_option`, `.missing_value`,
/// `.unexpected_value`) are variants here rather than a Zig error union:
/// real `getopt()`-style parsing reports one bad option per call and keeps
/// going rather than aborting the whole parse, and this mirrors that.
pub const Token = union(enum) {
    /// A registered `.kind = .flag` option was present (e.g. `-v`).
    flag: struct { short: ?u8, long: ?[]const u8 },
    /// A registered `.kind = .value` option was present, with its value
    /// (attached to a short bundle, `=`-joined to a long option, or taken
    /// unconditionally from the next argv token).
    option: struct { short: ?u8, long: ?[]const u8, value: []const u8 },
    /// A bare, non-flag argument -- or any token once `--` has been seen.
    positional: []const u8,
    /// A short or long option wasn't found in `specs`. Neither `short`
    /// nor `long` is ever both-null; whichever form the caller actually
    /// typed is the one that's populated.
    unknown_option: struct { short: ?u8, long: ?[]const u8 },
    /// A `.kind = .value` option had no attached/`=` value and `argv` was
    /// exhausted before a following token could supply one.
    missing_value: struct { short: ?u8, long: ?[]const u8 },
    /// A `.kind = .flag` long option was given `--flag=value` -- flags
    /// never take a value.
    unexpected_value: struct { short: ?u8, long: ?[]const u8, value: []const u8 },
    /// No more args. Returned forever once reached, so it's always safe
    /// to keep calling `next()`.
    end,
};

pub const Parser = struct {
    /// The `argv` slice being walked -- `argv[0]` (the program name)
    /// excluded, see `process.collect`.
    args: []const [:0]const u8,
    /// The options this parser recognizes; anything else short/long
    /// becomes `.unknown_option`.
    specs: []const OptionSpec,
    arg_index: usize = 0,
    /// >0 means mid short-option bundle, positioned at this byte offset
    /// into `args[arg_index]`.
    char_index: usize = 0,
    /// Set once a bare `--` is seen; every remaining token becomes a
    /// `.positional` from then on, even ones that look like flags.
    positional_only: bool = false,

    pub fn init(args: []const [:0]const u8, specs: []const OptionSpec) Parser {
        return .{ .args = args, .specs = specs };
    }

    /// Keeps returning `.end` forever once the args are exhausted.
    pub fn next(self: *Parser) Token {
        if (self.char_index > 0) return self.nextFromBundle();
        if (self.arg_index >= self.args.len) return .end;

        const tok: []const u8 = self.args[self.arg_index];

        if (self.positional_only) {
            self.arg_index += 1;
            return .{ .positional = tok };
        }

        if (std.mem.eql(u8, tok, "--")) {
            self.positional_only = true;
            self.arg_index += 1;
            return self.next();
        }

        if (tok.len < 2 or tok[0] != '-') {
            self.arg_index += 1;
            return .{ .positional = tok };
        }

        if (tok[1] == '-') {
            self.arg_index += 1;
            return self.parseLong(tok[2..]);
        }

        self.char_index = 1;
        return self.nextFromBundle();
    }

    /// Resolves one character of a short-option bundle (`-abc`) at
    /// `args[arg_index][char_index]`. A `.flag` char just advances one
    /// position; a `.value` char consumes either the rest of the current
    /// token (`-ofile.txt`) or, if none remains, the whole next argv
    /// token (`-o file.txt`) -- either way it ends the bundle.
    fn nextFromBundle(self: *Parser) Token {
        const tok: []const u8 = self.args[self.arg_index];
        const c = tok[self.char_index];
        const spec = self.findShort(c);

        if (spec == null) {
            self.advanceBundleChar(tok);
            return .{ .unknown_option = .{ .short = c, .long = null } };
        }

        switch (spec.?.kind) {
            .flag => {
                self.advanceBundleChar(tok);
                return .{ .flag = .{ .short = c, .long = spec.?.long } };
            },
            .value => {
                const rest = tok[self.char_index + 1 ..];
                self.arg_index += 1;
                self.char_index = 0;
                if (rest.len > 0) {
                    return .{ .option = .{ .short = c, .long = spec.?.long, .value = rest } };
                }
                if (self.arg_index >= self.args.len) {
                    return .{ .missing_value = .{ .short = c, .long = spec.?.long } };
                }
                const value = self.args[self.arg_index];
                self.arg_index += 1;
                return .{ .option = .{ .short = c, .long = spec.?.long, .value = value } };
            },
        }
    }

    /// Moves past one flag/unknown char in the current bundle, rolling
    /// over to the next argv token once the bundle is exhausted.
    fn advanceBundleChar(self: *Parser, tok: []const u8) void {
        self.char_index += 1;
        if (self.char_index >= tok.len) {
            self.char_index = 0;
            self.arg_index += 1;
        }
    }

    /// Resolves a `--name` or `--name=value` token (`rest` is everything
    /// after the leading `--`).
    fn parseLong(self: *Parser, rest: []const u8) Token {
        var name = rest;
        var value: ?[]const u8 = null;
        if (std.mem.indexOfScalar(u8, rest, '=')) |eq| {
            name = rest[0..eq];
            value = rest[eq + 1 ..];
        }

        const spec = self.findLong(name) orelse return .{ .unknown_option = .{ .short = null, .long = name } };

        switch (spec.kind) {
            .flag => {
                if (value) |v| return .{ .unexpected_value = .{ .short = spec.short, .long = name, .value = v } };
                return .{ .flag = .{ .short = spec.short, .long = name } };
            },
            .value => {
                if (value) |v| return .{ .option = .{ .short = spec.short, .long = name, .value = v } };
                if (self.arg_index >= self.args.len) return .{ .missing_value = .{ .short = spec.short, .long = name } };
                const v = self.args[self.arg_index];
                self.arg_index += 1;
                return .{ .option = .{ .short = spec.short, .long = name, .value = v } };
            },
        }
    }

    fn findShort(self: *Parser, c: u8) ?OptionSpec {
        for (self.specs) |spec| {
            if (spec.short == c) return spec;
        }
        return null;
    }

    fn findLong(self: *Parser, name: []const u8) ?OptionSpec {
        for (self.specs) |spec| {
            if (spec.long) |l| {
                if (std.mem.eql(u8, l, name)) return spec;
            }
        }
        return null;
    }
};
