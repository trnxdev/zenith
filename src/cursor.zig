const globals = @import("globals.zig");
const sub_1_ignore_overflow = globals.sub_1_ignore_overflow;

x: Unit,
y: Unit,

pub const Unit = usize;

pub fn can_move(self: @This(), lines: usize, line_len: usize, direction: globals.Direction) bool {
    return switch (direction) {
        .Up => self.y != 0,
        .Down => self.y + 1 < lines,
        .Left => self.x != 0,
        .Right => self.x < line_len,
    };
}

pub fn move(self: *@This(), lines: usize, line_len: usize, direction: globals.Direction) void {
    _ = self.move_bl(lines, line_len, direction);
}

pub fn move_bl(self: *@This(), lines: usize, line_len: usize, direction: globals.Direction) bool {
    if (!self.can_move(lines, line_len, direction)) {
        return false;
    }

    switch (direction) {
        .Left => self.x -= 1,
        .Right => self.x += 1,
        .Up => self.y -= 1,
        .Down => self.y += 1,
    }

    return true;
}

pub fn write_unsafe(self: *@This(), writer: anytype) !void {
    try writer.print("\x1b[{};{}H", .{ self.y + 1, self.x + 1 });
}

pub fn ctrl_move(self: *@This(), line: *globals.Line, direction: globals.Direction) void {
    if (line.items.len == 0) {
        return;
    }

    if (isCtrlSpecial(line.items[sub_1_ignore_overflow(self.x)])) {
        o: while (isCtrlSpecial(line.items[sub_1_ignore_overflow(self.x)])) {
            if (!self.can_move(1, line.items.len, direction)) {
                break :o;
            }

            self.move(1, line.items.len, direction);
        }
    } else {
        o: while (!isCtrlSpecial(line.items[sub_1_ignore_overflow(self.x)])) {
            if (!self.can_move(1, line.items.len, direction)) {
                break :o;
            }

            self.move(1, line.items.len, direction);
        }
    }

    return;
}

// TODO: Better Name(?)
pub fn isCtrlSpecial(c: globals.Char) bool {
    return switch (c) {
        '.' => true,
        '(', ')' => true,
        '{', '}' => true,
        '[', ']' => true,
        ',' => true,
        ' ' => true,
        else => false,
    };
}
