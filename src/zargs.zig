//! `z-args`: a ladder of complexity for command-line argument parsing --
//! import only the tier your CLI actually needs. `Simple` (POSIX/GNU-style
//! flag tokenizer), `Builder` (imperative registration + auto-help +
//! cross-flag validation), and `Declarative` (struct-as-source-of-truth,
//! comptime reflection) are the three parsing-complexity rungs;
//! `Commands` (subcommand tree) is the orthogonal fourth axis, composing
//! over `Builder` or `Declarative` as a leaf.
//!
//! Requires Zig 0.17.0. Run `zig build docs` to generate this reference.
//! Parsers consume arguments without the executable name. Strings borrow
//! their input storage; keep it alive while using parsed results.

/// Allocation-free POSIX/GNU option tokenizer.
pub const Simple = @import("simple.zig");
/// Runtime option registration, usage text, and dependency/conflict checks.
pub const Builder = @import("builder.zig");
/// Typed parsing from a struct of `Flag` and `Positional` fields.
pub const Declarative = @import("declarative.zig");
/// Static command trees with callbacks that can use any parsing tier.
pub const Commands = @import("commands.zig");
/// Collect process arguments after skipping the executable name.
/// Free the returned slice with the supplied allocator; strings are borrowed
/// from the process iterator. May return `error.OutOfMemory`.
pub const collectProcessArgs = @import("process.zig").collect;
