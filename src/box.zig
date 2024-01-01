const std = @import("std");
const globals = @import("globals.zig");
const Cursor = @import("cursor.zig");
const Style = @import("styles.zig");
const Input = @import("input.zig");
const unicode = @import("unicode.zig");
const Tab = @import("tab.zig");

allocator: std.mem.Allocator,
highlight_selected: bool = false,
input: *globals.Line,
input_cursor: *Cursor,

pub inline fn init(allocator: std.mem.Allocator, highlight_selected: bool) !@This() {
    const l = try allocator.create(globals.Line);
    errdefer allocator.destroy(l); // is it even necessary?
    l.* = globals.Line{};
    errdefer l.deinit(allocator); // beh

    const i = try allocator.create(Cursor);
    errdefer allocator.destroy(i); // bah
    i.* = std.mem.zeroes(Cursor);

    return .{
        .allocator = allocator,
        .highlight_selected = highlight_selected,
        .input = l,
        .input_cursor = i,
    };
}

pub fn deinit(self: *@This()) void {
    self.input.deinit(self.allocator);
    self.allocator.destroy(self.input);
    self.allocator.destroy(self.input_cursor);
    _ = std.io.getStdOut().write(Style.Value(.ShowCursor)) catch @panic("Box could not reset the cursor!");
}

// if this returns focus it's always 0 (focus = enter pressed)
pub fn modify(self: *@This(), input: Input, options: usize, actions: *globals.Actions) !globals.modify_response {
    var empty_bool: bool = false;

    return switch (input.key) {
        .escape => .exit,
        .enter => .{ .focus = 0 },
        .arrow => |a| switch (a) {
            .Up, .Down => |c| v: {
                self.input_cursor.move(options, 0, c);
                break :v .none;
            },
            else => try globals.modify_line(
                self.allocator,
                self.input,
                self.input_cursor,
                &empty_bool,
                actions,
                input,
                struct {},
            ),
        },
        else => try globals.modify_line(
            self.allocator,
            self.input,
            self.input_cursor,
            &empty_bool,
            actions,
            input,
            struct {},
        ),
    };
}

pub fn draw(self: *@This(), options: [][]globals.Char, writer: anytype) !void {
    var buffered = std.io.bufferedWriter(writer);
    defer buffered.flush() catch {};

    const stdout = buffered.writer();
    const size = try globals.getTerminalSize();

    if (size.cols <= 14 * 2 or size.rows <= 6) {
        try stdout.writeAll("Box cannot be rendered, please resize your terminal.");
        return;
    }

    var draw_cursor = std.mem.zeroes(Cursor);
    try draw_cursor.write_unsafe(writer);
    try Centered.draw_top(&draw_cursor, stdout, size.cols);
    draw_cursor.y += 1;
    draw_cursor.x = 0;
    try Centered.draw_left_border(&draw_cursor, stdout);

    const utf8_query = try unicode.toUtf8Alloc(self.allocator, self.input.items);
    defer self.allocator.free(utf8_query);

    draw_cursor.x += try stdout.write(utf8_query);
    try Centered.draw_right_border(&draw_cursor, stdout, size.cols);
    draw_cursor.x = 0;
    draw_cursor.y += 1;
    try Centered.draw_left_border_mw(&draw_cursor, stdout);
    for (0..size.cols - 5) |_| {
        try stdout.writeAll("━");
    }
    try Centered.draw_right_border_mw(&draw_cursor, stdout, size.cols);

    if (options.len != 0) {
        const usable_options_rows = size.rows - 5;
        var line_start = self.input_cursor.y;

        if (line_start >= 1) {
            line_start -= line_start;
        }

        if (self.input_cursor.y >= @divFloor(usable_options_rows, 2)) {
            line_start = self.input_cursor.y - @divFloor(usable_options_rows, 2);
        }

        const line_end = @min(options.len, line_start + usable_options_rows);

        draw_cursor.x = 0;

        for (options[line_start..line_end], line_start..) |option, i| {
            draw_cursor.x = 0;
            draw_cursor.y += 1;
            try Centered.draw_left_border(&draw_cursor, stdout);
            if (self.highlight_selected and i == self.input_cursor.y) {
                try stdout.writeAll(Style.Value(.WhiteBG));
            }
            const utf8_option = try unicode.toUtf8Alloc(self.allocator, option);
            defer self.allocator.free(utf8_option);

            inner: for (utf8_option) |c| {
                if (draw_cursor.x > size.cols - 5) {
                    try stdout.writeAll(Style.Value(.Reset));
                    if (self.highlight_selected and i == self.input_cursor.y) {
                        try stdout.writeAll(Style.Value(.GrayBG));
                    } else {
                        try stdout.writeAll(Style.Value(.WhiteBG));
                    }
                    try stdout.writeByte('>');
                    try stdout.writeAll(Style.Value(.Reset));
                    draw_cursor.x = size.cols - 3;
                    break :inner;
                }

                draw_cursor.x += try stdout.write(&[_]u8{c});
            }

            if (self.highlight_selected and i == self.input_cursor.y) {
                try Centered.draw_right_border_col(&draw_cursor, stdout, size.cols, .WhiteBG);
            } else {
                try Centered.draw_right_border(&draw_cursor, stdout, size.cols);
            }
        }
    }

    draw_cursor.y += 1;
    draw_cursor.x = 0;

    try Centered.draw_bottom(&draw_cursor, stdout, size.cols);
}

const Centered = struct {
    pub fn draw_top(cursor: *Cursor, writer: anytype, w: usize) !void {
        cursor.x += 2;
        try cursor.write_unsafe(writer);
        try writer.writeAll("┏");

        for (0..w - 5) |_| {
            try writer.writeAll("━");
        }

        try writer.writeAll("┓\n");
    }

    pub fn draw_bottom(cursor: *Cursor, writer: anytype, w: usize) !void {
        cursor.x += 2;
        try cursor.write_unsafe(writer);
        try writer.writeAll("┗");

        for (0..w - 5) |_| {
            try writer.writeAll("━");
        }

        try writer.writeAll("┛\n");
    }

    pub fn draw_left_border(cursor: *Cursor, writer: anytype) !void {
        cursor.x += 2;

        try cursor.write_unsafe(writer);
        try writer.writeAll("┃");
    }

    pub fn draw_right_border(cursor: *Cursor, writer: anytype, w: usize) !void {
        const wy = w - cursor.x;
        for (0..wy - 3) |_| {
            try writer.writeAll(" ");
        }
        try writer.writeAll("┃\n");
    }

    pub fn draw_right_border_col(cursor: *Cursor, writer: anytype, w: usize, comptime style: Style.Enum) !void {
        const wy = w - cursor.x;
        try writer.writeAll(Style.Value(style));
        for (0..wy - 3) |_| {
            try writer.writeAll(" ");
        }
        try writer.writeAll(Style.Value(.Reset));
        try writer.writeAll("┃\n");
    }

    pub fn draw_left_border_mw(cursor: *Cursor, writer: anytype) !void {
        cursor.x += 2;
        try cursor.write_unsafe(writer);
        try writer.writeAll("┣");
    }

    pub fn draw_right_border_mw(cursor: *Cursor, writer: anytype, w: usize) !void {
        cursor.x = w - 2;
        try cursor.write_unsafe(writer);
        try writer.writeAll("┫\n");
    }
};
