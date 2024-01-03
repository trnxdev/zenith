const std = @import("std");
const Cursor = @import("cursor.zig");
const builtin = @import("builtin");
const Tab = @import("tab.zig");
const Input = @import("input.zig");
const Style = @import("styles.zig");
const unicode = @import("unicode.zig");
const Action = @import("action.zig").Action;

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
pub const Actions = std.ArrayList(Action);

pub fn undo(allocator: std.mem.Allocator, line: *Line, cursor: *Cursor, saved: *bool, actions: *Actions, external: anytype) !modify_response {
    if (actions.items.len == 0) {
        return .none;
    }

    const execute_action = actions.items[actions.items.len - 1];
    actions.items.len -= 1;

    return switch (execute_action) {
        .insert_char => |i| {
            defer allocator.free(i.c);

            cursor.x = i.x + 1;
            cursor.y = i.y;
            var customline = line;
            if (@TypeOf(external) == *Tab) {
                customline = &external.lines.items[cursor.y];
            }
            var response: modify_response = undefined;

            for (i.c) |_| {
                response = try modify_line(
                    allocator,
                    customline,
                    cursor,
                    saved,
                    actions,
                    .{ .key = .backspace },
                    external,
                );
                if (actions.getLast() == .del_char) {
                    Action_deinit(allocator, actions.pop());
                }
            }

            return response;
        },
        .del_char => |d| {
            defer allocator.free(d.c);

            cursor.x = d.x;
            cursor.y = d.y;

            var customline = line;
            if (@TypeOf(external) == *Tab) {
                customline = &external.lines.items[cursor.y];
            }

            var response: modify_response = undefined;

            for (d.c) |ds| {
                response = try modify_line(
                    allocator,
                    customline,
                    cursor,
                    saved,
                    actions,
                    .{ .key = .{ .char = ds } },
                    external,
                );
                if (actions.getLast() == .insert_char) {
                    Action_deinit(allocator, actions.pop());
                }
            }

            return response;
        },
    };
}

pub fn modify_line(
    allocator: std.mem.Allocator,
    line: *Line,
    cursor: *Cursor,
    saved: *bool,
    actions: *Actions,
    input: Input,
    external: anytype,
) anyerror!modify_response {
    if (input.isHotBind(.Ctrl, 'z')) { // Undo, TODO: Redo
        return try undo(allocator, line, cursor, saved, actions, external);
    }

    switch (input.key) {
        .escape => return .exit,
        .enter => return .none,
        .backspace => {
            if (!cursor.move_bl(1, line.items.len, .Left))
                return .none;

            saved.* = false;

            if (input.modifiers.isCtrl()) {
                const old = cursor.x;
                cursor.ctrl_move(line, .Left);
                const now = cursor.x;
                std.debug.assert(now <= old);

                const deleted_slice = try allocator.dupe(Char, line.items[now .. old + 1]);
                errdefer allocator.free(deleted_slice);

                try actions.append(.{ .del_char = .{ .x = cursor.x, .y = cursor.y, .c = deleted_slice } });

                for (0..old - now + 1) |_| {
                    _ = line.orderedRemove(cursor.x);
                }

                return .none;
            }

            const del_alloc = try allocator.dupe(Char, &[_]Char{line.items[cursor.x]});
            errdefer allocator.free(del_alloc);

            try actions.append(.{ .del_char = .{ .x = cursor.x, .y = cursor.y, .c = del_alloc } });
            _ = line.orderedRemove(cursor.x);
            return .none;
        },
        .char => |c| {
            const in_alloc = try allocator.dupe(Char, &[_]Char{c});
            errdefer allocator.free(in_alloc);

            try actions.append(.{ .insert_char = .{ .x = cursor.x, .y = cursor.y, .c = in_alloc } });
            try line.insert(allocator, cursor.x, c);
            saved.* = false;
            cursor.x += 1;
        },
        .tab => {
            const space = ' ';
            const in_alloc = try allocator.dupe(Char, &[_]Char{space});
            errdefer allocator.free(in_alloc);

            try actions.append(.{ .insert_char = .{ .x = cursor.x, .y = cursor.y, .c = in_alloc } });

            for (0..4) |_| {
                try line.insert(allocator, cursor.x, space);
                cursor.move(1, line.items.len, .Right);
            }
        },
        .arrow => |a| {
            if (a == .Up or a == .Down)
                return .none;

            if (input.modifiers.isCtrl()) {
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

pub fn Action_deinit(allocator: std.mem.Allocator, ac: Action) void {
    allocator.free(switch (ac) {
        .del_char => |d| d.c,
        .insert_char => |i| i.c,
    });
}

pub fn Actions_deinit(actions: *Actions) void {
    while (actions.popOrNull()) |ac| {
        Action_deinit(actions.allocator, ac);
    }

    actions.deinit();
}

/// Caller frees the memory
pub fn text_prompt(allocator: std.mem.Allocator, text: []const u8) !?[]Char {
    var line = Line{};
    defer line.deinit(allocator);

    var actions = Actions.init(allocator);
    defer Actions_deinit(&actions);

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
        const input = try Input.parseStdin();

        if (input.key == .enter) {
            break :o;
        }

        switch (try modify_line(allocator, &line, &cursor, &empty_bool, &actions, input, null)) {
            .exit => return null,
            .none => {},
            .focus => unreachable,
        }
    }

    return try line.toOwnedSlice(allocator);
}
