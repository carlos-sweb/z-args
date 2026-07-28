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

pub const OptionKind = enum { flag, value };

pub const OptionSpec = struct {
    short: ?u8 = null,
    long: ?[]const u8 = null,
    kind: OptionKind = .flag,
};

pub const Token = union(enum) {
    flag: struct { short: ?u8, long: ?[]const u8 },
    option: struct { short: ?u8, long: ?[]const u8, value: []const u8 },
    positional: []const u8,
    /// Neither `short` nor `long` is ever both-null; whichever form the
    /// caller actually typed is the one that's populated.
    unknown_option: struct { short: ?u8, long: ?[]const u8 },
    missing_value: struct { short: ?u8, long: ?[]const u8 },
    unexpected_value: struct { short: ?u8, long: ?[]const u8, value: []const u8 },
    end,
};

pub const Parser = struct {
    args: []const [:0]const u8,
    specs: []const OptionSpec,
    arg_index: usize = 0,
    /// >0 means mid short-option bundle, positioned at this byte offset
    /// into `args[arg_index]`.
    char_index: usize = 0,
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

    fn advanceBundleChar(self: *Parser, tok: []const u8) void {
        self.char_index += 1;
        if (self.char_index >= tok.len) {
            self.char_index = 0;
            self.arg_index += 1;
        }
    }

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
