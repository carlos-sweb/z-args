//! `Declarative` tier: the caller's own struct is the single source of
//! truth, generated at compile time via `@typeInfo` reflection -- no
//! runtime registration step, no stringly-keyed `Result` (see `Builder`).
//! `parseStruct` returns the caller's `T` itself, fully populated and
//! type-checked.
//!
//! Ground-truthed against two real "mature ecosystem" references:
//! Crystal's `admiral.cr` (source read directly: `define_flag`/
//! `define_argument`) and Nim's `cligen` (README-documented, compiled
//! examples). One critical, Zig-specific finding decided this tier's whole
//! shape: `cligen`'s core idea -- reflect over a *function's* parameter
//! list -- is not portable to Zig at all. `std.builtin.Type.Fn.Param` has
//! no `name` field (confirmed by reading Zig's own `std/builtin.zig`), so
//! function-signature reflection can't recover parameter names the way
//! `std.builtin.Type.StructField` can. `Declarative` is therefore
//! struct-based only, matching `admiral.cr`'s shape.
//!
//! Zig has no field-attribute mechanism (no `@[short('v')]` the way Rust or
//! Java can annotate a field), so each field's metadata lives inside its
//! own type instead of a separate, driftable "meta" struct: wrap a field's
//! type in `Flag(T, opts)` or `Positional(T, opts)`.
//!
//! **Ground-truthed rules:**
//! - Long name auto-derives from the Zig field name (underscore -> hyphen,
//!   e.g. `dry_run` -> `--dry-run`) unless `opts.long` is given, matching
//!   `admiral.cr`'s `gsub(/_/, "-")`. Short is never auto-derived (always
//!   explicit `opts.short`), also matching `admiral.cr`.
//! - `opts.default == null` means required, for both `Flag` and
//!   `Positional` -- the same rule both `admiral.cr` and `cligen` use.
//! - A bool `Flag` whose `opts.default == true` accepts `--no-<long>` to
//!   flip it back to `false`, ground-truthed from `admiral.cr`'s
//!   `values_from_spec`'s `default == true && flag == falsey_flag` check.
//!   A bool defaulting to `false` (the common case) has no negation form.
//! - `Positional` fields are matched in struct declaration order.
//!   Required positionals must not come after optional ones, matching
//!   `admiral.cr`'s documented restriction -- enforced here as a
//!   `@compileError`, not just a doc comment.
//! - A `Positional([]const []const u8, opts)` field is a rest-collector
//!   (ground-truthed from `cligen`'s trailing non-defaulted `seq[T]`
//!   parameter): it absorbs every positional left after the fixed ones,
//!   must be the last `Positional` field, and is never itself required
//!   (an empty collection is always valid). Its resulting slice is
//!   **caller-owned** -- free it with `allocator.free(result.field.value)`.
//!
//! **Deliberate divergence from `admiral.cr`**: an extra positional token
//! with no rest-collector field declared is `error.TooManyPositionals`.
//! Real `admiral.cr` silently drops overflow into an always-present
//! `rest`, even when nothing reads it -- but silently dropping a value
//! would contradict this tier's own premise that the struct is the single
//! source of truth.
const std = @import("std");

const FieldKind = enum { flag, positional };

/// Per-`Flag` metadata, typed against the flag's own value type `T` so
/// `default` can't be given a value of the wrong type.
pub fn FlagOpts(comptime T: type) type {
    return struct {
        short: ?u8 = null,
        long: ?[]const u8 = null,
        help: []const u8 = "",
        /// `null` means the flag is required.
        default: ?T = null,
    };
}

/// Wraps a struct field as a named `-short`/`--long` option. `T` is the
/// field's real value type -- `result.name.value` after `parseStruct`.
pub fn Flag(comptime T: type, comptime opts: FlagOpts(T)) type {
    return struct {
        pub const zargs_field_kind: FieldKind = .flag;
        pub const Inner = T;
        pub const zargs_opts = opts;
        value: T,
    };
}

/// Per-`Positional` metadata. See `Flag`'s `default`.
pub fn PositionalOpts(comptime T: type) type {
    return struct {
        help: []const u8 = "",
        default: ?T = null,
    };
}

/// Wraps a struct field as a positional argument, matched in declaration
/// order among a struct's `Positional` fields. `T = []const []const u8`
/// is special-cased as the rest-collector -- see the file doc comment.
pub fn Positional(comptime T: type, comptime opts: PositionalOpts(T)) type {
    return struct {
        pub const zargs_field_kind: FieldKind = .positional;
        pub const Inner = T;
        pub const zargs_opts = opts;
        value: T,
    };
}

/// Populated on error with whichever field/token was the problem.
pub const Diagnostics = struct {
    field: ?[]const u8 = null,
    short: ?u8 = null,
    long: ?[]const u8 = null,
    raw: ?[]const u8 = null,
};

pub const Error = error{
    UnknownOption,
    MissingValue,
    UnexpectedValue,
    InvalidValue,
    MissingRequiredFlag,
    MissingRequiredPositional,
    TooManyPositionals,
    OutOfMemory,
};

fn isRestCollector(comptime T: type) bool {
    return T == []const []const u8;
}

/// Underscore -> hyphen, e.g. `dry_run` -> `dry-run`.
fn kebabName(comptime name: []const u8) []const u8 {
    const result = comptime blk: {
        var buf: [name.len]u8 = undefined;
        for (name, 0..) |c, i| {
            buf[i] = if (c == '_') '-' else c;
        }
        break :blk buf;
    };
    return &result;
}

fn longNameOf(comptime field: std.builtin.Type.StructField) []const u8 {
    return field.type.zargs_opts.long orelse comptime kebabName(field.name);
}

/// Checked at comptime, once per `T`, from `parseStruct`: every field must
/// be `Flag`/`Positional`-wrapped, at most one rest-collector and it must
/// be last among `Positional` fields, and no required positional may
/// follow an optional one.
fn validateStruct(comptime T: type) void {
    const fields = @typeInfo(T).@"struct".fields;
    comptime var seen_optional_positional = false;
    comptime var rest_seen = false;
    inline for (fields) |field| {
        const is_container = switch (@typeInfo(field.type)) {
            .@"struct", .@"enum", .@"union", .@"opaque" => true,
            else => false,
        };
        if (!is_container or !@hasDecl(field.type, "zargs_field_kind")) {
            @compileError("z-args Declarative: field '" ++ field.name ++ "' of " ++ @typeName(T) ++ " must be wrapped in Declarative.Flag(...) or Declarative.Positional(...)");
        }
        if (field.type.zargs_field_kind == .positional) {
            if (rest_seen) {
                @compileError("z-args Declarative: the rest-collector positional must be the last Positional field (found '" ++ field.name ++ "' after it)");
            }
            if (comptime isRestCollector(field.type.Inner)) {
                rest_seen = true;
            } else if (field.type.zargs_opts.default != null) {
                seen_optional_positional = true;
            } else if (seen_optional_positional) {
                @compileError("z-args Declarative: required positional '" ++ field.name ++ "' cannot come after an optional positional");
            }
        }
    }
}

fn coerceValue(comptime T: type, raw: []const u8) Error!T {
    return switch (@typeInfo(T)) {
        .int => std.fmt.parseInt(T, raw, 10) catch return Error.InvalidValue,
        .float => std.fmt.parseFloat(T, raw) catch return Error.InvalidValue,
        .@"enum" => std.meta.stringToEnum(T, raw) orelse return Error.InvalidValue,
        else => if (T == []const u8) raw else @compileError("z-args Declarative: unsupported field type " ++ @typeName(T)),
    };
}

/// Runs the whole parse in one call (same contract as `Builder.Parser.parse`)
/// and returns the caller's own `T`, fully populated.
pub fn parseStruct(comptime T: type, allocator: std.mem.Allocator, args: []const [:0]const u8, diagnostics: ?*Diagnostics) Error!T {
    comptime validateStruct(T);
    const fields = @typeInfo(T).@"struct".fields;

    const positional_field_indices = comptime blk: {
        var idxs: [fields.len]usize = undefined;
        var count: usize = 0;
        for (fields, 0..) |field, i| {
            if (field.type.zargs_field_kind == .positional) {
                idxs[count] = i;
                count += 1;
            }
        }
        var out: [count]usize = undefined;
        for (0..count) |k| out[k] = idxs[k];
        break :blk out;
    };

    var result: T = undefined;
    var given = [_]bool{false} ** fields.len;
    var rest_list: std.ArrayList([]const u8) = .empty;
    errdefer rest_list.deinit(allocator);

    var positional_only = false;
    var next_positional: usize = 0;
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const tok = args[i];

        if (!positional_only and std.mem.eql(u8, tok, "--")) {
            positional_only = true;
            continue;
        }
        if (positional_only or tok.len < 2 or tok[0] != '-') {
            if (next_positional >= positional_field_indices.len) return Error.TooManyPositionals;
            const field_idx = positional_field_indices[next_positional];
            inline for (fields, 0..) |field, idx| {
                if (comptime field.type.zargs_field_kind == .positional) {
                    if (idx == field_idx) {
                        const FT = field.type;
                        if (comptime isRestCollector(FT.Inner)) {
                            rest_list.append(allocator, tok) catch return Error.OutOfMemory;
                            given[idx] = true;
                        } else {
                            const v = coerceValue(FT.Inner, tok) catch |err| {
                                if (diagnostics) |d| d.* = .{ .field = field.name, .raw = tok };
                                return err;
                            };
                            @field(result, field.name) = .{ .value = v };
                            given[idx] = true;
                            next_positional += 1;
                        }
                    }
                }
            }
            continue;
        }

        if (tok[1] == '-') {
            const rest: []const u8 = tok[2..];
            var name: []const u8 = rest;
            var inline_value: ?[]const u8 = null;
            if (std.mem.indexOfScalar(u8, rest, '=')) |eq| {
                name = rest[0..eq];
                inline_value = rest[eq + 1 ..];
            }

            var matched = false;
            inline for (fields, 0..) |field, idx| {
                const FT = field.type;
                if (comptime FT.zargs_field_kind == .flag) {
                    const long = comptime longNameOf(field);
                    if (std.mem.eql(u8, long, name)) {
                        matched = true;
                        if (FT.Inner == bool) {
                            if (inline_value != null) {
                                if (diagnostics) |d| d.* = .{ .field = field.name, .long = long };
                                return Error.UnexpectedValue;
                            }
                            @field(result, field.name) = .{ .value = true };
                            given[idx] = true;
                        } else {
                            const v = inline_value orelse blk: {
                                if (i + 1 >= args.len) {
                                    if (diagnostics) |d| d.* = .{ .field = field.name, .long = long };
                                    return Error.MissingValue;
                                }
                                i += 1;
                                break :blk args[i];
                            };
                            const coerced = coerceValue(FT.Inner, v) catch |err| {
                                if (diagnostics) |d| d.* = .{ .field = field.name, .long = long, .raw = v };
                                return err;
                            };
                            @field(result, field.name) = .{ .value = coerced };
                            given[idx] = true;
                        }
                    } else if (FT.Inner == bool and FT.zargs_opts.default == true) {
                        var negbuf: [long.len + 3]u8 = undefined;
                        const neg = std.fmt.bufPrint(&negbuf, "no-{s}", .{long}) catch unreachable;
                        if (std.mem.eql(u8, neg, name)) {
                            matched = true;
                            if (inline_value != null) {
                                if (diagnostics) |d| d.* = .{ .field = field.name, .long = long };
                                return Error.UnexpectedValue;
                            }
                            @field(result, field.name) = .{ .value = false };
                            given[idx] = true;
                        }
                    }
                }
            }
            if (!matched) {
                if (diagnostics) |d| d.* = .{ .long = name };
                return Error.UnknownOption;
            }
            continue;
        }

        try applyShortBundle(T, fields, tok, &i, args, &result, &given, diagnostics);
    }

    // Unconditional even when empty: `toOwnedSlice` always leaves `rest_list`
    // in a safe, already-freed `.empty` state, so the `errdefer` above stays
    // a harmless no-op from here on -- unlike a manual `deinit` (which sets
    // the list to `undefined`, not `.empty`, making a later `errdefer`-driven
    // `deinit` a double-free).
    inline for (fields, 0..) |field, idx| {
        if (comptime field.type.zargs_field_kind == .positional and isRestCollector(field.type.Inner)) {
            @field(result, field.name) = .{ .value = rest_list.toOwnedSlice(allocator) catch return Error.OutOfMemory };
            given[idx] = true;
        }
    }

    inline for (fields, 0..) |field, idx| {
        if (!given[idx]) {
            const FT = field.type;
            if (FT.zargs_opts.default) |d| {
                @field(result, field.name) = .{ .value = d };
            } else if (comptime FT.zargs_field_kind == .flag) {
                if (diagnostics) |d| d.* = .{ .field = field.name };
                return Error.MissingRequiredFlag;
            } else {
                if (diagnostics) |d| d.* = .{ .field = field.name };
                return Error.MissingRequiredPositional;
            }
        }
    }

    return result;
}

fn applyShortBundle(
    comptime T: type,
    comptime fields: []const std.builtin.Type.StructField,
    tok: []const u8,
    i: *usize,
    args: []const [:0]const u8,
    result: *T,
    given: []bool,
    diagnostics: ?*Diagnostics,
) Error!void {
    const rest = tok[1..];

    // Validate the whole bundle before applying any of it (same contract
    // as `Builder`): every char up to a value-taking flag must resolve.
    comptime var value_flag_short: ?u8 = null;
    _ = &value_flag_short;
    var stop_index: ?usize = null;
    var idx: usize = 0;
    while (idx < rest.len) : (idx += 1) {
        const c = rest[idx];
        var found = false;
        var is_value = false;
        inline for (fields) |field| {
            const FT = field.type;
            if (comptime FT.zargs_field_kind == .flag) {
                if (FT.zargs_opts.short) |s| {
                    if (s == c) {
                        found = true;
                        is_value = FT.Inner != bool;
                    }
                }
            }
        }
        if (!found) {
            if (diagnostics) |d| d.* = .{ .raw = tok };
            return Error.UnknownOption;
        }
        if (is_value) {
            stop_index = idx;
            break;
        }
    }

    const flag_count = stop_index orelse rest.len;
    var k: usize = 0;
    while (k < flag_count) : (k += 1) {
        const c = rest[k];
        inline for (fields, 0..) |field, fidx| {
            const FT = field.type;
            if (comptime FT.zargs_field_kind == .flag and FT.Inner == bool) {
                if (FT.zargs_opts.short) |s| {
                    if (s == c) {
                        @field(result, field.name) = .{ .value = true };
                        given[fidx] = true;
                    }
                }
            }
        }
    }

    if (stop_index) |si| {
        const c = rest[si];
        const attached = rest[si + 1 ..];
        inline for (fields, 0..) |field, fidx| {
            const FT = field.type;
            if (comptime FT.zargs_field_kind == .flag and FT.Inner != bool) {
                if (FT.zargs_opts.short) |s| {
                    if (s == c) {
                        const value = if (attached.len > 0) attached else blk: {
                            if (i.* + 1 >= args.len) {
                                if (diagnostics) |d| d.* = .{ .field = field.name, .short = c };
                                return Error.MissingValue;
                            }
                            i.* += 1;
                            break :blk args[i.*];
                        };
                        const coerced = coerceValue(FT.Inner, value) catch |err| {
                            if (diagnostics) |d| d.* = .{ .field = field.name, .short = c, .raw = value };
                            return err;
                        };
                        @field(result, field.name) = .{ .value = coerced };
                        given[fidx] = true;
                    }
                }
            }
        }
    }
}

/// Formats a banner + an aligned "flags/positional  description" row per
/// field. Everything needed is already known from `T` at comptime, so
/// unlike `Builder.Parser.usageAlloc` this is a free function -- there is
/// no runtime registration step in this tier.
pub fn usageAlloc(comptime T: type, allocator: std.mem.Allocator, banner: []const u8) ![]u8 {
    comptime validateStruct(T);
    const fields = @typeInfo(T).@"struct".fields;

    var buf: std.ArrayList(u8) = .empty;
    errdefer buf.deinit(allocator);
    if (banner.len > 0) try buf.print(allocator, "{s}\n", .{banner});

    inline for (fields) |field| {
        const FT = field.type;
        var label_buf: std.ArrayList(u8) = .empty;
        defer label_buf.deinit(allocator);

        if (comptime FT.zargs_field_kind == .flag) {
            const long = comptime longNameOf(field);
            if (FT.zargs_opts.short) |s| {
                try label_buf.print(allocator, "-{c}, --{s}", .{ s, long });
            } else {
                try label_buf.print(allocator, "--{s}", .{long});
            }
            if (FT.Inner != bool) try label_buf.appendSlice(allocator, " <value>");
        } else if (comptime isRestCollector(FT.Inner)) {
            try label_buf.print(allocator, "[{s}...]", .{field.name});
        } else {
            try label_buf.print(allocator, "<{s}>", .{field.name});
        }

        var suffix_buf: std.ArrayList(u8) = .empty;
        defer suffix_buf.deinit(allocator);
        if (FT.zargs_opts.default == null and comptime !isRestCollector(FT.Inner)) {
            try suffix_buf.appendSlice(allocator, " (required)");
        }

        try buf.print(allocator, "    {s:<28} {s}{s}\n", .{ label_buf.items, FT.zargs_opts.help, suffix_buf.items });
    }

    return buf.toOwnedSlice(allocator);
}
