const std = @import("std");
const builtin = @import("builtin");
const Style = @import("styles.zig");
const Cursor = @import("cursor.zig");
const unicode = @import("unicode.zig");
const globals = @import("globals.zig");
const Tab = @import("tab.zig");
const Input = @import("input.zig");
const Config = @import("conf.zig");

var null_editor: globals.Editor = .{};
const editor: *globals.Editor = &null_editor;

pub fn resize(_: c_int) callconv(.C) void {
    if (editor.init) {
        if (editor.drawing.tryLock()) {
            defer editor.drawing.unlock();
            editor.tabs.items[editor.focused].draw(editor.tabs.*, std.io.getStdOut().writer()) catch {};
        }
    }
}

pub fn main() !void {
    var gpa = if (globals.Debug) std.heap.GeneralPurposeAllocator(.{}){} else void{};
    const allocator = if (globals.Debug) gpa.allocator() else std.heap.c_allocator;
    defer _ = if (globals.Debug) gpa.deinit();

    var old: globals.system.termios = undefined;

    if (globals.system.tcgetattr(globals.stdin_fd, &old) == -1)
        return error.TcGetAttrFailed;

    var new = old;

    new.lflag = .{
        .ICANON = false,
        .ECHO = false,
        .ISIG = false,
    };

    new.iflag = .{
        .IXON = false,
    };

    if (globals.system.tcsetattr(globals.stdin_fd, globals.system.TCSA.FLUSH, &new) == -1)
        return error.TcSetAttrFailed;

    defer _ = globals.system.tcsetattr(globals.stdin_fd, globals.system.TCSA.FLUSH, &old);
    defer std.io.getStdOut().writeAll(Style.Value(.ClearScreen) ++ Style.Value(.ResetCursor)) catch {};

    var tabs = globals.Tabs.init(allocator);
    defer tabs.deinit();
    defer for (tabs.items) |stab| stab.deinit();

    const config: ?Config.parse_default_result = Config.parseDefault(allocator) catch |e| brk: {
        switch (e) {
            error.CustomConfigFileCouldNotBeOpened => {
                try std.io.getStdOut().writeAll(Style.Value(.ClearScreen));
                try std.io.getStdOut().writeAll("The config was not found\npress enter to continue.");
                _ = try std.io.getStdIn().reader().readByte();
                break :brk null;
            },
            else => return e,
        }
    };
    defer if (config) |c| c.deinit();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var draw = std.Thread.Mutex{};
    editor.* = .{
        .tabs = &tabs,
        .drawing = &draw,
        .config = if (config) |c| c.value else Config.Value{},
        .init = true,
        .focused = 0,
    };

    var tab = if (args.len >= 2) v: {
        const file_path = args[1];
        break :v try Tab.open_from_file(allocator, 0, file_path, editor);
    } else brk: {
        const inside_tab = try Tab.create(allocator, 0, editor);
        try inside_tab.lines.append(globals.Line{}); // A tab requires atleast one line
        break :brk inside_tab;
    };
    try tabs.append(tab);

    // This does some handling for edge cases
    std.posix.sigaction(globals.system.SIG.WINCH, &globals.system.Sigaction{
        .handler = .{ .handler = &resize },
        .mask = globals.system.empty_sigset,
        .flags = 0,
    }, null);

    o: while (true) {
        editor.drawing.lock();
        try tab.draw(tabs, std.io.getStdOut().writer());
        editor.drawing.unlock();

        const input = try Input.parseStdin();

        editor.drawing.lock();
        defer editor.drawing.unlock();

        switch (try tab.modify(&tabs, input)) {
            .none => continue :o,
            .exit => break :o,
            .focus => |i| {
                editor.focused = i;
                tab = tabs.items[i];
            },
        }
    }
}
