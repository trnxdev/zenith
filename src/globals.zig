const std = @import("std");
const Cursor = @import("cursor.zig");
const builtin = @import("builtin");
const Tab = @import("tab.zig");
const Input = @import("input.zig");
const Style = @import("styles.zig");
const unicode = @import("unicode.zig");

pub const no_filename = "Unnamed";
pub const no_filepath = "No File Path";
pub const Debug = builtin.mode == .Debug;

pub const Char = u21;
pub const Line = std.ArrayListUnmanaged(Char);
pub const Lines = std.ArrayList(Line);

pub const Direction = enum {
    Up,
    Down,
    Left,
    Right,
};
pub const modify_response = union(enum) {
    exit: void,
    none: void,
    focus: usize,
};
pub const Tabs = std.ArrayList(*Tab);

pub fn modify_line(
    allocator: std.mem.Allocator,
    line: *Line,
    cursor: *Cursor,
    input: Input,
    saved: *bool,
) !modify_response {
    switch (input.key) {
        .escape => return .exit,
        .enter => return .none,
        .backspace => {
            if (!cursor.move_bl(1, line.items.len, .Left))
                return .none;

            saved.* = false;
            _ = line.orderedRemove(cursor.x);
        },
        .char => |c| {
            try line.insert(allocator, cursor.x, c);
            saved.* = false;
            cursor.x += 1;
        },
        .tab => {
            for (0..4) |_| {
                try line.insert(allocator, cursor.x, @intCast(' '));
                cursor.move(1, line.items.len, .Right);
            }
        },
        .arrow => |a| {
            if (a == .Up or a == .Down)
                return .none;

            if (input.modifiers.ctrl) {
                cursor.ctrl_move(line, a);
            } else {
                cursor.move(1, line.items.len, a);
            }
        },
    }

    return .none;
}

pub const stdin_fd = std.io.getStdIn().handle;
pub const os = builtin.os.tag;

const GetTerminalSizeError = error{IoctlFailed};
const TerminalSize = packed struct {
    rows: usize,
    cols: usize,
};
pub fn getTerminalSize() GetTerminalSizeError!TerminalSize {
    var size: std.os.linux.winsize = undefined;
    const res = std.os.linux.ioctl(stdin_fd, std.os.linux.T.IOCGWINSZ, @intFromPtr(&size));

    if (res != 0) {
        return GetTerminalSizeError.IoctlFailed;
    }

    return .{
        .rows = @intCast(size.ws_row),
        .cols = @intCast(size.ws_col),
    };
}

pub inline fn i64_from(x: anytype) i64 {
    return @intCast(x);
}

pub inline fn usize_from(x: anytype) usize {
    return @intCast(x);
}

pub fn sub_1_ignore_overflow(i: anytype) @TypeOf(i) {
    return if (i == 0) 0 else i - 1;
}

pub inline fn num_strlen(nm: anytype) @TypeOf(nm) {
    var num = nm;
    var len: usize = 0;

    while (num != 0) {
        num /= 10;
        len += 1;
    }

    return len;
}

pub fn text_prompt(allocator: std.mem.Allocator, text: []const u8) !?[]Char {
    var line = Line{};
    defer line.deinit(allocator);

    var empty_bool = false; // Unused
    var cursor = std.mem.zeroes(Cursor);

    o: while (true) {
        // Draw
        try std.io.getStdOut().writeAll(Style.Value(.ClearScreen));
        try std.io.getStdOut().writeAll(Style.Value(.ResetCursor));
        try std.io.getStdOut().writeAll(text);

        for (line.items) |c| {
            try std.io.getStdOut().writeAll(try unicode.decode(c));
        }

        try std.io.getStdOut().writer().print("\x1b[{};{}H", .{ cursor.y, cursor.x + text.len + 1 });

        // Input
        const input = try Input.parse_stdin();

        if (input.key == .enter) {
            break :o;
        }

        switch (try modify_line(allocator, &line, &cursor, input, &empty_bool)) {
            .exit => return null,
            .none => {},
            .focus => unreachable,
        }
    }

    return try line.toOwnedSlice(allocator);
}
