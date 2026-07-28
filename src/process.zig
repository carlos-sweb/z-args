//! The one piece of the `Simple` tier that touches an allocator: glue from
//! a real process's `std.process.Args.Iterator` to the `[]const [:0]const
//! u8` slice `simple.Parser` operates on. Closes the exact gap `z-run`'s
//! `src/main.zig` hand-rolls today (`args_it.skip()` for argv[0], then a
//! manual loop) -- everything else in this tier stays allocator-free.
const std = @import("std");

/// Materializes the remaining args (skipping argv[0]) into an owned slice.
/// Caller frees with the same allocator.
pub fn collect(allocator: std.mem.Allocator, it: *std.process.Args.Iterator) ![][:0]const u8 {
    _ = it.skip();
    var list: std.ArrayList([:0]const u8) = .empty;
    errdefer list.deinit(allocator);
    while (it.next()) |a| try list.append(allocator, a);
    return list.toOwnedSlice(allocator);
}
