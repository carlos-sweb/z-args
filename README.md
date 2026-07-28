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

## Current status

**Simple** is implemented (`src/simple.zig`, `src/process.zig`) — a zero-allocation, zero-I/O flag tokenizer, ground-truthed against real `getopt_long(3)` (bundling, attached/separate values, `=`-long options, `--`, non-fatal errors that let parsing continue). `Builder`, `Declarative`, and `Commands` are still research-only — each awaits its own design session before implementation, so this project doesn't repeat the problem that motivated it in the first place (starting simple and getting stuck with no next rung).

## Target

Zig 0.16.0 (stable).
