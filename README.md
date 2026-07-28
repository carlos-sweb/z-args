# z-args

A package of command-line argument parsing modules for Zig — not a monolithic library, but a **ladder of complexity** the user climbs only as far as their CLI actually needs.

## Why it exists

Today Zig's ecosystem basically offers two options for parsing `argv`: something as simple as a manual `switch`, or libraries like `zig-clap`/`zig-args` that already assume a fair amount of complexity. There's no declared middle path. Meanwhile, in C, `arg.h` (suckless) solves the trivial case in a handful of lines — until a flag that depends on another one shows up, and then it falls short. That's exactly the problem `z-args` sets out to solve: **the same "use only what you need" spirit, but with a next rung to climb once simple stops being enough**, instead of jumping straight to a full framework.

## How we got here

Before writing a single line of Zig, this repo started by researching how the most-used languages solve this same problem — C, C++, Python, Java, C#, JavaScript, R, Rust, and also Crystal and Nim, since they share compile-time metaprogramming with Zig. That research is in [`args.md`](./args.md) and is the foundation for everything that follows: it classifies real-world libraries into **8 patterns/styles** (from imperative macros+switch to tree-shaped commands/subcommands), and for each one evaluates **how literally it can be ported to Zig 0.16** given what the language offers (`comptime`, `@typeInfo`, generic parameterized types) and what it doesn't (a preprocessor, token-pasting macros, attributes/annotations on struct fields).

## The proposed ladder

Categories by **functional scope** (what each one solves, not which library's syntax it copies), validated against the only two surveyed ecosystems with a complete ladder within a single language: Nim and Crystal.

| Category | Scope | Reference (mature ecosystem) |
|---|---|---|
| **Simple** | POSIX/GNU `getopt_long`-style short/long flag tokenizer. No types, no auto-generated help, no cross-flag validation. | Nim `std/parseopt` |
| **Builder** | Imperative runtime registration, auto-generated help, cross-flag validation. Results by name, no compile-time type checking. | Crystal `OptionParser` |
| **Declarative** | The language's own struct/function as the source of truth, generated at compile time: type-checked, minimal boilerplate. | Nim `cligen`, Crystal `admiral.cr` |
| **Commands** (orthogonal) | Subcommand tree, composes over Builder or Declarative as a leaf. Not a parsing-complexity rung, a separate axis. | `admiral.cr`, `cobra` |

A single Zig module (`zargs`), not one module per tier — Zig only generates code for what's actually used, so importing `zargs.Simple` doesn't pay the cost of `Builder`/`Declarative`, with no need for separate `build.zig.zon` entries. Matches the convention of the rest of the `z-*` ecosystem: one repo, one root module.

The full detail of each category — justification, the reformulation from the initial research (numbered patterns) into this taxonomy, the `argh` case study (why classification is by scope and not syntax), and Zig 0.16 API sketches — is documented in [`args.md`](./args.md).

## Examples

### `Simple`: parsing the process's real `argv`

The only spot in this tier that touches an allocator — `zargs.collectProcessArgs` materializes the real `std.process.Init` iterator into the slice `Parser` expects:

```shell
$ ./myprogram --verbose --output=out.txt input.txt
```

```zig
const std = @import("std");
const zargs = @import("zargs");
const Simple = zargs.Simple;

const specs = [_]Simple.OptionSpec{
    .{ .short = 'v', .long = "verbose", .kind = .flag },
    .{ .short = 'o', .long = "output", .kind = .value },
};

pub fn main(init: std.process.Init) !u8 {
    var it = std.process.Args.Iterator.init(init.minimal.args);
    const args = try zargs.collectProcessArgs(init.gpa, &it);
    defer init.gpa.free(args);

    var parser = Simple.Parser.init(args, &specs);

    var verbose = false;
    var output: []const u8 = "a.out";
    var input: ?[]const u8 = null;

    while (true) {
        const token = parser.next();
        switch (token) {
            .flag => |f| if (f.short == 'v') {
                verbose = true;
            },
            .option => |o| if (o.short == 'o') {
                output = o.value;
            },
            .positional => |p| input = p,
            .unknown_option => |u| std.debug.print("unknown option: {?c}{s}\n", .{ u.short, u.long orelse "" }),
            .missing_value, .unexpected_value => {}, // the caller decides what to do with each error
            .end => break,
        }
    }

    return 0;
}
```

`Parser` allocates nothing and does no I/O itself: it only slices into whatever `args` it's given. `zargs.collectProcessArgs` is the one piece of glue that does touch an allocator, purely to turn the real process's lazy iterator into that slice.

### `Simple`: parsing a literal `argv` (e.g. for testing flags)

Same `Parser`, but fed a literal slice — no real process needed, which is exactly how this tier's own test suite exercises every case:

```zig
const std = @import("std");
const zargs = @import("zargs");
const Simple = zargs.Simple;

const specs = [_]Simple.OptionSpec{
    .{ .short = 'v', .long = "verbose", .kind = .flag },
    .{ .short = 'o', .long = "output", .kind = .value },
};

pub fn main() !void {
    const args = [_][:0]const u8{ "-v", "--output=out.txt", "input.txt" };
    var parser = Simple.Parser.init(&args, &specs);

    var verbose = false;
    var output: []const u8 = "a.out";
    var input: ?[]const u8 = null;

    while (true) {
        const token = parser.next();
        switch (token) {
            .flag => |f| if (f.short == 'v') {
                verbose = true;
            },
            .option => |o| if (o.short == 'o') {
                output = o.value;
            },
            .positional => |p| input = p,
            .unknown_option => |u| std.debug.print("unknown option: {?c}{s}\n", .{ u.short, u.long orelse "" }),
            .missing_value, .unexpected_value => {}, // the caller decides what to do with each error
            .end => break,
        }
    }
    // verbose == true, output == "out.txt", input == "input.txt"
}
```

A bad flag (`.unknown_option`) doesn't abort the rest of the parse — just like real `getopt()`, each `.next()` call reports one problem at a time and keeps going, leaving the decision to abort or continue in the caller's hands.

### `Builder`: registering options and parsing the process's real `argv`

Unlike `Simple`, `Builder.Parser` runs the whole parse in one call and returns a `Result` queried by name — closer to real Crystal `OptionParser`, this tier's reference:

```shell
$ ./myprogram --verbose --output=out.txt input.txt
```

```zig
const std = @import("std");
const zargs = @import("zargs");
const Builder = zargs.Builder;

pub fn main(init: std.process.Init) !u8 {
    var it = std.process.Args.Iterator.init(init.minimal.args);
    const args = try zargs.collectProcessArgs(init.gpa, &it);
    defer init.gpa.free(args);

    var parser = Builder.Parser.init(init.gpa);
    defer parser.deinit();
    parser.setBanner("Usage: myprogram [options] [file]");
    try parser.addFlag(.{ .name = "verbose", .short = 'v', .long = "verbose", .help = "Verbose mode" });
    try parser.addOption(.{ .name = "output", .short = 'o', .long = "output", .help = "Output file", .value_name = "FILE" });
    try parser.requires("output", "verbose");

    var diag: Builder.Diagnostics = .{};
    var result = parser.parse(init.gpa, args, &diag) catch |err| {
        const usage = try parser.usageAlloc(init.gpa);
        defer init.gpa.free(usage);
        std.debug.print("error: {s}\n\n{s}", .{ @errorName(err), usage });
        return 1;
    };
    defer result.deinit(init.gpa);

    if (result.flag("verbose")) std.debug.print("verbose mode\n", .{});
    if (result.option("output")) |out| std.debug.print("output: {s}\n", .{out});
    for (result.positionals.items) |p| std.debug.print("file: {s}\n", .{p});

    return 0;
}
```

`requires("output", "verbose")` and its counterpart `.conflicts(a, b)` are cross-flag validation, checked once the whole `argv` has been walked — the exact rung `arg.h`-style manual `switch` parsing has nowhere to hook in (see "Why it exists" above). There's no callback-registration mechanism for reporting a bad option, unlike Crystal's `invalid_option`/`missing_option`: `parse()` returning `Builder.Error` and a plain `catch` already gives the same control with less API surface.

### `Builder`: registering options and parsing a literal `argv` (e.g. for testing flags)

```zig
const std = @import("std");
const zargs = @import("zargs");
const Builder = zargs.Builder;

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    var parser = Builder.Parser.init(allocator);
    defer parser.deinit();
    try parser.addFlag(.{ .name = "verbose", .short = 'v', .long = "verbose", .help = "Verbose mode" });
    try parser.addOption(.{ .name = "output", .short = 'o', .long = "output", .help = "Output file" });

    const args = [_][:0]const u8{ "-v", "--output=out.txt", "input.txt" };
    var result = try parser.parse(allocator, &args, null);
    defer result.deinit(allocator);
    // result.flag("verbose") == true
    // result.option("output").? == "out.txt"
    // result.positionals.items[0] == "input.txt"
}
```

Short-option bundles (`-vofile.txt`, or `-vo file.txt`) are validated as a whole before anything in them is applied — an unrecognized character fails the entire token, not just that one flag, unlike `Simple`'s per-character continuation. See `src/builder.zig`'s file docs for the full ground-truthed rationale (including the one place this tier deliberately diverges from real Crystal `OptionParser`'s observed behavior).

### `Declarative`: your own struct is the parser, parsing the process's real `argv`

Unlike `Builder`'s stringly-keyed `Result`, `Declarative.parseStruct` returns the caller's own struct, fully populated and type-checked — each field is wrapped in `Declarative.Flag(T, opts)` or `Declarative.Positional(T, opts)`, which carries its short/long spelling, help text, and default (`null` means required) inside the type itself, since Zig has no field-attribute mechanism to hang that metadata on separately:

```shell
$ ./myprogram --verbose --retries=5 --output=out.txt input.txt
```

```zig
const std = @import("std");
const zargs = @import("zargs");
const Declarative = zargs.Declarative;

const Cli = struct {
    verbose: Declarative.Flag(bool, .{ .short = 'v', .long = "verbose", .help = "Verbose mode", .default = false }),
    retries: Declarative.Flag(u32, .{ .short = 'r', .long = "retries", .help = "Retry count", .default = 3 }),
    output: Declarative.Flag([]const u8, .{ .short = 'o', .long = "output", .help = "Output file" }),
    input: Declarative.Positional([]const u8, .{ .help = "Input file" }),
};

pub fn main(init: std.process.Init) !u8 {
    var it = std.process.Args.Iterator.init(init.minimal.args);
    const args = try zargs.collectProcessArgs(init.gpa, &it);
    defer init.gpa.free(args);

    var diag: Declarative.Diagnostics = .{};
    const cli = Declarative.parseStruct(Cli, init.gpa, args, &diag) catch |err| {
        const usage = try Declarative.usageAlloc(Cli, init.gpa, "Usage: myprogram [options] <input>");
        defer init.gpa.free(usage);
        std.debug.print("error: {s}\n\n{s}", .{ @errorName(err), usage });
        return 1;
    };

    if (cli.verbose.value) std.debug.print("verbose mode\n", .{});
    std.debug.print("retries: {d}\n", .{cli.retries.value});
    std.debug.print("output: {s}\n", .{cli.output.value});
    std.debug.print("input: {s}\n", .{cli.input.value});

    return 0;
}
```

`cli.retries.value` is a real `u32`, not a string to parse yourself — that's this tier's actual payoff over `Builder`. A missing required field (here, `output`) is `error.MissingRequiredFlag`/`error.MissingRequiredPositional`, with `diag.field` naming which one; `Declarative.usageAlloc` needs no runtime registration step to render, since everything is already known from the struct's type at compile time.

### `Declarative`: registering options and parsing a literal `argv` (e.g. for testing flags)

```zig
const std = @import("std");
const zargs = @import("zargs");
const Declarative = zargs.Declarative;

const Cli = struct {
    verbose: Declarative.Flag(bool, .{ .short = 'v', .long = "verbose", .default = false }),
    output: Declarative.Flag([]const u8, .{ .short = 'o', .long = "output" }),
    input: Declarative.Positional([]const u8, .{}),
    extra: Declarative.Positional([]const []const u8, .{}), // rest-collector, see below
};

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const args = [_][:0]const u8{ "-v", "--output=out.txt", "input.txt", "extra1", "extra2" };
    const cli = try Declarative.parseStruct(Cli, allocator, &args, null);
    defer allocator.free(cli.extra.value);
    // cli.verbose.value == true, cli.output.value == "out.txt"
    // cli.input.value == "input.txt", cli.extra.value == &.{ "extra1", "extra2" }
}
```

A `Declarative.Positional([]const []const u8, opts)` field is a rest-collector: it absorbs every positional left over after the fixed ones (here, `extra1`/`extra2` beyond `input`), must be the last `Positional` field in the struct, and its slice is caller-owned — free it the same way as `cli.extra.value` above. Every other misuse (a field not wrapped in `Flag`/`Positional`, a rest-collector that isn't last, a required positional after an optional one) is a `@compileError`, not a runtime surprise — see `src/declarative.zig`'s file docs for the full ground-truthed rationale, including the one place this tier deliberately diverges from real Crystal `admiral.cr`'s observed behavior.

### `Commands`: a subcommand tree, composing over `Builder` and `Declarative` as leaves

Unlike the first three rungs, `Commands` isn't a parsing-complexity tier of its own — it's an orthogonal subcommand tree, declared as a plain static literal, that routes `argv` down to a leaf `action` callback. Each leaf is free to parse its own remaining args with whichever tier fits it best:

```shell
$ ./myapp remote add origin https://example.com
$ ./myapp clean --force
```

```zig
const std = @import("std");
const zargs = @import("zargs");
const Commands = zargs.Commands;
const Builder = zargs.Builder;
const Declarative = zargs.Declarative;

const AddCli = struct {
    name: Declarative.Positional([]const u8, .{ .help = "Remote name" }),
    url: Declarative.Positional([]const u8, .{ .help = "Remote URL" }),
};

fn remoteAdd(allocator: std.mem.Allocator, args: []const [:0]const u8) anyerror!void {
    const cli = try Declarative.parseStruct(AddCli, allocator, args, null);
    std.debug.print("added remote {s} -> {s}\n", .{ cli.name.value, cli.url.value });
}

fn clean(allocator: std.mem.Allocator, args: []const [:0]const u8) anyerror!void {
    var parser = Builder.Parser.init(allocator);
    defer parser.deinit();
    try parser.addFlag(.{ .name = "force", .short = 'f', .long = "force", .help = "Skip confirmation" });
    var result = try parser.parse(allocator, args, null);
    defer result.deinit(allocator);
    std.debug.print("clean (force={})\n", .{result.flag("force")});
}

const root = Commands.Command{
    .name = "myapp",
    .children = &[_]Commands.Command{
        .{
            .name = "remote",
            .help = "Manage remotes",
            .children = &[_]Commands.Command{
                .{ .name = "add", .help = "Add a remote", .action = remoteAdd },
            },
        },
        .{ .name = "clean", .help = "Clean the workspace", .action = clean },
    },
};

pub fn main(init: std.process.Init) !u8 {
    var it = std.process.Args.Iterator.init(init.minimal.args);
    const args = try zargs.collectProcessArgs(init.gpa, &it);
    defer init.gpa.free(args);

    Commands.dispatch(root, init.gpa, args) catch |err| {
        const usage = try Commands.usageAlloc(root, init.gpa, "Usage: myapp <command> [options]");
        defer init.gpa.free(usage);
        std.debug.print("error: {s}\n\n{s}", .{ @errorName(err), usage });
        return 1;
    };

    return 0;
}
```

`remote add` is a two-level route (`remote` is a pure branch, no `action` of its own) resolved with a `Declarative` leaf; `clean` is a one-level route resolved with a `Builder` leaf — real composition over either tier from the same tree, not a unified generic mechanism. `Commands.dispatch` matches `args[0]` against child names/aliases directly (ground-truthed from Crystal `admiral.cr`'s `@argv[0]?` check) rather than scanning past flags to find the next subcommand-shaped token the way Go's `cobra` does — a deliberate, documented divergence; see `src/commands.zig`'s file docs for the full rationale.

### `Commands`: dispatching against a literal `argv` (e.g. for testing a leaf in isolation)

```zig
const std = @import("std");
const zargs = @import("zargs");
const Commands = zargs.Commands;

fn status(allocator: std.mem.Allocator, args: []const [:0]const u8) anyerror!void {
    _ = allocator;
    _ = args;
    std.debug.print("status: clean\n", .{});
}

const root = Commands.Command{
    .name = "myapp",
    .children = &[_]Commands.Command{
        .{ .name = "status", .alias = "st", .help = "Show status", .action = status },
    },
};

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const args = [_][:0]const u8{"st"};
    try Commands.dispatch(root, allocator, &args);
}
```

The tree itself (`root` above) is a plain comptime literal, not a runtime-registered object — there's no `deinit` for it, only for whatever a leaf's own `Builder`/`Declarative` call allocates internally.

## Current status

All four taxonomy rows are implemented and tested. **Simple** (`src/simple.zig`, `src/process.zig`) is a zero-allocation, zero-I/O flag tokenizer ground-truthed against real `getopt_long(3)` (bundling, attached/separate values, `=`-long options, `--`, non-fatal errors that let parsing continue). **Builder** (`src/builder.zig`) is imperative registration + auto-generated usage text + cross-flag validation (`requires`/`conflicts`), ground-truthed against real Crystal `OptionParser` (both its compiled behavior and its stdlib source). **Declarative** (`src/declarative.zig`) is comptime `@typeInfo` reflection over the caller's own struct, ground-truthed against Crystal `admiral.cr`'s source and Nim `cligen`'s documented behavior -- including confirming, by reading Zig's own stdlib, that `cligen`'s function-signature-reflection approach has no Zig equivalent (function parameter names aren't preserved in Zig's type reflection), which is why this tier is struct-based. **Commands** (`src/commands.zig`) is a subcommand tree declared as a static literal, routing `argv[0]` down to a leaf callback that composes over `Builder` or `Declarative`, ground-truthed against Crystal `admiral.cr`'s source and Go `cobra`'s source -- deliberately following `admiral.cr`'s simpler direct-`argv[0]`-match model over `cobra`'s heavier flag-skipping search, documented as such.

## Target

Zig 0.16.0 (stable).
