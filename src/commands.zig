//! `Commands` tier: a subcommand tree. Unlike `Simple`/`Builder`/
//! `Declarative`, this is explicitly *not* a parsing-complexity rung --
//! it's an orthogonal axis that composes over either of them as a leaf.
//!
//! Ground-truthed against two real references:
//! - Crystal's `admiral.cr` (`src/admiral/command/sub_command.cr`,
//!   source read directly): `register_sub_command` maps a name (+
//!   optional `short:` alias) to another full command class; the default
//!   `run` used when nothing matches does exactly
//!   `raise Error.new "Invalid subcommand: #{@argv[0]?}"` -- the match
//!   target is `@argv[0]`, checked directly, no scanning past leading
//!   flags to find a subcommand-shaped token.
//! - Go's `cobra` (`command.go`'s `Find`/`stripFlags`/`argsMinusFirstX`,
//!   source read directly): a materially heavier model -- it scans past
//!   flag tokens (using each node's own registered flags to know how
//!   many tokens to skip) to find the first bare token, then merges
//!   "persistent" flags down the tree.
//!
//! **Deliberate scope decision**: this tier follows `admiral.cr`'s
//! simpler model (`args[0]` is the subcommand candidate, full stop) over
//! `cobra`'s flag-skipping search + persistent-flag inheritance. The
//! latter is real, but requires every branch node to carry its own
//! registered flag set purely to know how to parse past it -- more
//! machinery than this "thin orthogonal layer" rung, or this project's
//! own start-simple ethos, calls for yet.
//!
//! **No unified generic tree over `Declarative` leaves.** `Declarative`
//! is one distinct comptime `type` per CLI struct; a tree spanning
//! heterogeneous `Declarative` leaf types would need an enum-tagged-union
//! dispatch mechanism neither reference actually needed either (`cobra`
//! doesn't unify its flags into one generic type across the tree -- each
//! `*Command` just owns its own `*pflag.FlagSet`). Instead, a `Command`'s
//! leaf is a plain callback (`Action`), free to call `Builder.Parser.parse`
//! or `Declarative.parseStruct` internally -- real composition over either
//! tier without inventing machinery beyond what's ground-truthed.
//!
//! The tree itself is a **statically-declared, comptime-known literal**
//! (see the examples in `README.md`) -- no runtime registration step and
//! no `deinit` for the tree, unlike `admiral.cr`'s per-class inheritance
//! or `cobra`'s `AddCommand` calls (only whatever a leaf `Action`
//! allocates internally needs freeing, exactly like `Builder`/
//! `Declarative` already work).
const std = @import("std");

pub const Action = *const fn (allocator: std.mem.Allocator, args: []const [:0]const u8) anyerror!void;

pub const Command = struct {
    name: []const u8,
    /// A single alternate name for this subcommand, ground-truthed from
    /// `admiral.cr`'s `register_sub_command ..., short: ...`.
    alias: ?[]const u8 = null,
    help: []const u8 = "",
    /// Nested subcommands. A node with children and no `action` is a pure
    /// branch (e.g. `myapp remote` needing `myapp remote add`/`remove`);
    /// a node with an `action` and no children is a leaf; a node with
    /// both (an action that also has its own subcommands, e.g. `myapp
    /// remote` printing a default summary if called bare) is allowed too.
    children: []const Command = &.{},
    action: ?Action = null,
};

pub const Error = error{MissingSubcommand};

/// Walks `args[0]` against `root.children`'s names/aliases, recursing
/// with that one token removed. Stops recursing -- and invokes the
/// current node's `action` with whatever `args` remain -- the moment
/// `args` is empty, `args[0]` looks like a flag (`-`-prefixed, this
/// tier's own addition so a bare `--help`/`-v` at any level never gets
/// compared against child names), or no child matches.
/// `error.MissingSubcommand` if that node has no `action` of its own
/// either.
pub fn dispatch(root: Command, allocator: std.mem.Allocator, args: []const [:0]const u8) anyerror!void {
    if (args.len > 0 and args[0].len > 0 and args[0][0] != '-') {
        for (root.children) |child| {
            const name_matches = std.mem.eql(u8, child.name, args[0]);
            const alias_matches = if (child.alias) |a| std.mem.eql(u8, a, args[0]) else false;
            if (name_matches or alias_matches) {
                return dispatch(child, allocator, args[1..]);
            }
        }
    }
    if (root.action) |action| return action(allocator, args);
    return Error.MissingSubcommand;
}

/// Lists `node`'s immediate children (name [, alias] + help), one per
/// line, under `banner` -- a summary for exactly this level, not the
/// whole tree. Caller-owned, freed by the caller.
pub fn usageAlloc(node: Command, allocator: std.mem.Allocator, banner: []const u8) ![]u8 {
    var buf: std.ArrayList(u8) = .empty;
    errdefer buf.deinit(allocator);
    if (banner.len > 0) try buf.print(allocator, "{s}\n", .{banner});

    for (node.children) |child| {
        var label_buf: std.ArrayList(u8) = .empty;
        defer label_buf.deinit(allocator);
        try label_buf.appendSlice(allocator, child.name);
        if (child.alias) |a| try label_buf.print(allocator, ", {s}", .{a});
        try buf.print(allocator, "    {s:<20} {s}\n", .{ label_buf.items, child.help });
    }

    return buf.toOwnedSlice(allocator);
}
