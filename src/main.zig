const std = @import("std");
const builtin = @import("builtin");
const Style = @import("styles.zig");
const Cursor = @import("cursor.zig");
const unicode = @import("unicode.zig");
const globals = @import("globals.zig");
const Tab = @import("tab.zig");
const Input = @import("input.zig");

comptime {
    if (globals.os != .linux) {
        // Only Linux is Supported
        @compileError("Get better bro, https://archlinux.org");
    }
}

pub fn main() !void {
    var gpa = if (globals.Debug) std.heap.GeneralPurposeAllocator(.{}){} else void{};
    const allocator = if (globals.Debug) gpa.allocator() else std.heap.c_allocator;
    defer _ = if (globals.Debug) gpa.deinit();

    const old = try std.os.tcgetattr(globals.stdin_fd);
    var new = old;

    new.lflag &= ~(std.os.linux.ICANON | std.os.linux.ECHO | std.os.linux.ISIG);
    new.iflag &= ~std.os.linux.IXON;

    try std.os.tcsetattr(globals.stdin_fd, std.os.TCSA.FLUSH, new);
    defer std.os.tcsetattr(globals.stdin_fd, std.os.TCSA.FLUSH, old) catch {};
    defer std.io.getStdOut().writeAll(Style.Value(.ClearScreen) ++ Style.Value(.ResetCursor)) catch {};

    var tabs = globals.Tabs.init(allocator);
    defer tabs.deinit();
    defer for (tabs.items) |stab| stab.deinit();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var tab = if (args.len >= 2) v: {
        const file_path = args[1];
        break :v try Tab.open_from_file(allocator, 0, file_path);
    } else brk: {
        const inside_tab = try Tab.init(allocator, 0);
        try inside_tab.lines.append(globals.Line{}); // A tab requires atleast one line
        break :brk inside_tab;
    };
    try tabs.append(tab);

    o: while (true) {
        try tab.draw(tabs, std.io.getStdOut().writer());

        const input = try Input.parse_stdin();

        switch (try tab.modify(&tabs, input)) {
            .none => continue :o,
            .exit => break :o,
            .focus => |i| {
                tab = tabs.items[i];
            },
        }
    }
}
