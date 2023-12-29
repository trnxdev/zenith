const std = @import("std");

const stdin_fd = std.io.getStdIn().handle;

pub fn main() !void {
    const old = try std.os.tcgetattr(stdin_fd);
    var new = old;

    new.lflag &= ~(std.os.linux.ICANON | std.os.linux.ECHO);
    new.iflag &= ~std.os.linux.IXON;

    try std.os.tcsetattr(stdin_fd, std.os.TCSA.FLUSH, new);
    defer std.os.tcsetattr(stdin_fd, std.os.TCSA.FLUSH, old) catch {};

    while (true) {
        var buf: [8]u8 = undefined;
        const read = try std.io.getStdIn().reader().read(&buf);
        try std.fs.cwd().writeFile("key.txt", buf[0..read]);
    }
}
