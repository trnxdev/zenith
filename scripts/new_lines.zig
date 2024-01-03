const std = @import("std");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var new_lines = std.ArrayList(u8).init(allocator);
    defer new_lines.deinit();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const num: u64 = if (args.len < 2) 100000 else try std.fmt.parseInt(u64, args[1], 10);
    try new_lines.appendNTimes('\n', num);

    try std.fs.cwd().writeFile("new_lines.txt", new_lines.items);
}
