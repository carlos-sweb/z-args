//! `z-args`: a ladder of complexity for command-line argument parsing --
//! import only the tier your CLI actually needs. `Simple` (POSIX/GNU-style
//! flag tokenizer) is the first rung; `Builder`/`Declarative`/`Commands`
//! are future tiers, added here the same way once they exist.
pub const Simple = @import("simple.zig");
pub const collectProcessArgs = @import("process.zig").collect;
