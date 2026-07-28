const std = @import("std");
const zargs = @import("zargs");
const Commands = zargs.Commands;
const Builder = zargs.Builder;
const Declarative = zargs.Declarative;

var last_action: []const u8 = "";
var last_args_len: usize = 0;

fn resetProbe() void {
    last_action = "";
    last_args_len = 0;
}

fn statusAction(allocator: std.mem.Allocator, args: []const [:0]const u8) anyerror!void {
    _ = allocator;
    last_action = "status";
    last_args_len = args.len;
}

fn rootAction(allocator: std.mem.Allocator, args: []const [:0]const u8) anyerror!void {
    _ = allocator;
    last_action = "root";
    last_args_len = args.len;
}

fn removeAction(allocator: std.mem.Allocator, args: []const [:0]const u8) anyerror!void {
    _ = allocator;
    last_action = "remote.remove";
    last_args_len = args.len;
}

const AddCli = struct {
    name: Declarative.Positional([]const u8, .{}),
    url: Declarative.Positional([]const u8, .{}),
};

fn addAction(allocator: std.mem.Allocator, args: []const [:0]const u8) anyerror!void {
    const cli = try Declarative.parseStruct(AddCli, allocator, args, null);
    last_action = "remote.add";
    last_args_len = args.len;
    std.testing.expectEqualStrings("origin", cli.name.value) catch unreachable;
    std.testing.expectEqualStrings("https://example.com", cli.url.value) catch unreachable;
}

fn cleanAction(allocator: std.mem.Allocator, args: []const [:0]const u8) anyerror!void {
    var parser = Builder.Parser.init(allocator);
    defer parser.deinit();
    try parser.addFlag(.{ .name = "force", .short = 'f', .long = "force" });
    var result = try parser.parse(allocator, args, null);
    defer result.deinit(allocator);
    last_action = "clean";
    last_args_len = args.len;
    std.testing.expect(result.flag("force")) catch unreachable;
}

const remote_children = [_]Commands.Command{
    .{ .name = "add", .help = "Add a remote", .action = addAction },
    .{ .name = "remove", .alias = "rm", .help = "Remove a remote", .action = removeAction },
};

const root = Commands.Command{
    .name = "myapp",
    .action = rootAction,
    .children = &[_]Commands.Command{
        .{ .name = "status", .alias = "st", .help = "Show status", .action = statusAction },
        .{ .name = "remote", .help = "Manage remotes", .children = &remote_children },
        .{ .name = "clean", .help = "Clean workspace", .action = cleanAction },
    },
};

test "two-level routing by name" {
    resetProbe();
    const args = [_][:0]const u8{"status"};
    try Commands.dispatch(root, std.testing.allocator, &args);
    try std.testing.expectEqualStrings("status", last_action);
    try std.testing.expectEqual(@as(usize, 0), last_args_len);
}

test "three-level routing, remaining args passed to the leaf" {
    resetProbe();
    const args = [_][:0]const u8{ "remote", "add", "origin", "https://example.com" };
    try Commands.dispatch(root, std.testing.allocator, &args);
    try std.testing.expectEqualStrings("remote.add", last_action);
    try std.testing.expectEqual(@as(usize, 2), last_args_len);
}

test "alias matching" {
    resetProbe();
    const args = [_][:0]const u8{ "remote", "rm" };
    try Commands.dispatch(root, std.testing.allocator, &args);
    try std.testing.expectEqualStrings("remote.remove", last_action);

    resetProbe();
    const args2 = [_][:0]const u8{"st"};
    try Commands.dispatch(root, std.testing.allocator, &args2);
    try std.testing.expectEqualStrings("status", last_action);
}

test "no match at root -> MissingSubcommand when no action" {
    const branch_only = Commands.Command{
        .name = "myapp",
        .children = &[_]Commands.Command{
            .{ .name = "status", .action = statusAction },
        },
    };
    const args = [_][:0]const u8{"bogus"};
    try std.testing.expectError(error.MissingSubcommand, Commands.dispatch(branch_only, std.testing.allocator, &args));
}

test "branch node with children but no action errors on unmatched child" {
    const args = [_][:0]const u8{ "remote", "bogus" };
    try std.testing.expectError(error.MissingSubcommand, Commands.dispatch(root, std.testing.allocator, &args));
}

test "a flag-looking first token skips subcommand matching, routes to root's own action" {
    resetProbe();
    const args = [_][:0]const u8{"--verbose"};
    try Commands.dispatch(root, std.testing.allocator, &args);
    try std.testing.expectEqualStrings("root", last_action);
    try std.testing.expectEqual(@as(usize, 1), last_args_len);
}

test "empty args routes to root's own action" {
    resetProbe();
    const args = [_][:0]const u8{};
    try Commands.dispatch(root, std.testing.allocator, &args);
    try std.testing.expectEqualStrings("root", last_action);
}

test "leaf composes over Builder" {
    resetProbe();
    const args = [_][:0]const u8{ "clean", "--force" };
    try Commands.dispatch(root, std.testing.allocator, &args);
    try std.testing.expectEqualStrings("clean", last_action);
}

test "usageAlloc lists immediate children only" {
    const usage = try Commands.usageAlloc(root, std.testing.allocator, "Usage: myapp <command>");
    defer std.testing.allocator.free(usage);
    try std.testing.expect(std.mem.indexOf(u8, usage, "Usage: myapp <command>") != null);
    try std.testing.expect(std.mem.indexOf(u8, usage, "status, st") != null);
    try std.testing.expect(std.mem.indexOf(u8, usage, "Show status") != null);
    try std.testing.expect(std.mem.indexOf(u8, usage, "Manage remotes") != null);
    // Grandchildren ("add"/"remove") are not listed at this level.
    try std.testing.expect(std.mem.indexOf(u8, usage, "Add a remote") == null);
}
