const std = @import("std");

const stdin_fd = std.io.getStdIn().handle;

pub fn main() !void {
    const old = try std.os.tcgetattr(stdin_fd);
    var new = old;

    new.lflag &= ~(std.c.ICANON | std.c.ECHO | std.c.ISIG);
    new.iflag &= ~std.c.IXON;

    try std.os.tcsetattr(stdin_fd, std.os.TCSA.FLUSH, new);
    defer std.os.tcsetattr(stdin_fd, std.os.TCSA.FLUSH, old) catch {};

    while (true) {
        var buf: [8]u8 = undefined;
        const read = try std.io.getStdIn().reader().read(&buf);
        const joined = try std.fmt.allocPrint(std.heap.page_allocator, "{s} ({d})", .{ buf[0..read], buf });
        defer std.heap.page_allocator.free(joined);

        try std.fs.cwd().writeFile("key.txt", joined);

        if (buf[0] == std.ascii.control_code.esc) {
            return;
        }
    }
}
