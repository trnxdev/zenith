const std = @import("std");
const builtin = @import("builtin");

const stdin_fd = std.io.getStdIn().handle;
const system = switch (builtin.os.tag) {
    .linux => std.os.linux,
    else => std.c,
};

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const old = try std.os.tcgetattr(stdin_fd);
    var new = old;

    new.lflag &= ~(system.ICANON | system.ECHO | system.ISIG);
    new.iflag &= ~(system.IXON);

    try std.os.tcsetattr(stdin_fd, std.os.TCSA.FLUSH, new);
    defer std.os.tcsetattr(stdin_fd, std.os.TCSA.FLUSH, old) catch {};

    while (true) {
        var buf: [8]u8 = undefined;
        const read = try std.io.getStdIn().reader().read(&buf);
        const joined = try std.fmt.allocPrint(allocator, "{s} ({d})", .{ buf[0..read], buf });
        defer allocator.free(joined);

        try std.fs.cwd().writeFile("key.txt", joined);

        if (read == 1 and buf[0] == std.ascii.control_code.esc)
            return;
    }
}
