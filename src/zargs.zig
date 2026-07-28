//! `z-args`: a ladder of complexity for command-line argument parsing --
//! import only the tier your CLI actually needs. `Simple` (POSIX/GNU-style
//! flag tokenizer), `Builder` (imperative registration + auto-help +
//! cross-flag validation), and `Declarative` (struct-as-source-of-truth,
//! comptime reflection) are the three parsing-complexity rungs;
//! `Commands` (subcommand tree) is the orthogonal fourth axis, composing
//! over `Builder` or `Declarative` as a leaf.
pub const Simple = @import("simple.zig");
pub const Builder = @import("builder.zig");
pub const Declarative = @import("declarative.zig");
pub const Commands = @import("commands.zig");
pub const collectProcessArgs = @import("process.zig").collect;
