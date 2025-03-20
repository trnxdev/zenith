const std = @import("std");
const globals = @import("globals.zig");
const Cursor = @import("cursor.zig");
const Tab = @import("tab.zig");
const Style = @import("styles.zig");
const Input = @import("input.zig");
const Box = @import("box.zig");
const unicode = @import("unicode.zig");
const Boxes = @import("boxes.zig");
const highlight = @import("highlight.zig");

lines: globals.Lines,
filename: ?[]u8,
filepath: ?[]u8, // Absolute
cursor: *Cursor,
index: usize,
saved: bool,
allocator: std.mem.Allocator,
actions: globals.Actions,
terminal_prompt: ?[]globals.Char,
overwrite_bottom: ?[]u8,
editor: *globals.Editor,

pub fn create(allocator: std.mem.Allocator, index: usize, editor: *globals.Editor) !*@This() {
    const tab = try allocator.create(@This());
    errdefer tab.deinit();

    const lines = globals.Lines.init(allocator);
    errdefer lines.deinit();

    const cursor = try allocator.create(Cursor);
    errdefer cursor.deinit();

    cursor.* = .{
        .x = 0,
        .y = 0,
    };

    tab.* = .{
        .allocator = allocator,
        .saved = false,
        .cursor = cursor,
        .filename = null,
        .filepath = null,
        .lines = lines,
        .index = index,
        .terminal_prompt = null,
        .overwrite_bottom = null,
        .actions = globals.Actions.init(allocator),
        .editor = editor,
    };

    return tab;
}

pub fn open_from_file(allocator: std.mem.Allocator, index: usize, path: []u8, editor: *globals.Editor) !*@This() {
    const tab = try Tab.create(allocator, index, editor);
    errdefer tab.deinit();

    const file: std.fs.File = try if (std.fs.path.isAbsolute(path)) std.fs.createFileAbsolute(
        path,
        .{ .truncate = false, .read = true },
    ) else std.fs.cwd().createFile(
        path,
        .{ .truncate = false, .read = true },
    );
    defer file.close();

    const reader = file.reader();

    while (try reader.readUntilDelimiterOrEofAlloc(allocator, '\n', std.math.maxInt(usize))) |line| {
        defer allocator.free(line);
        try tab.lines.append(try unicode.toUnicodeList(allocator, line));
    }

    if (tab.lines.items.len == 0)
        try tab.lines.append(globals.Line{});

    // I wish there was std.fs.File.realpathAlloc
    var fpat: [std.fs.max_path_bytes]u8 = undefined;
    const fd_path = try std.os.getFdPath(file.handle, &fpat);
    tab.filepath = try allocator.dupe(u8, fd_path);
    errdefer allocator.free(tab.filepath.?);

    const last_slash = std.mem.lastIndexOfScalar(u8, tab.filepath.?, std.fs.path.sep) orelse unreachable;
    tab.filename = try allocator.dupe(u8, tab.filepath.?[last_slash + 1 ..]);
    errdefer allocator.free(tab.filename.?);

    tab.saved = true;
    return tab;
}

pub fn deinit(self: *@This()) void {
    self.allocator.destroy(self.cursor);
    globals.Actions_deinit(&self.actions);

    for (self.lines.items) |*line| {
        line.deinit(self.allocator);
    }
    self.lines.deinit();

    if (self.overwrite_bottom) |overwrite_bottom| {
        self.allocator.free(overwrite_bottom);
    }

    if (self.filename) |filename| {
        std.debug.assert(self.filepath != null);
        self.allocator.free(filename);
        self.allocator.free(self.filepath.?);
    }

    if (self.terminal_prompt) |terminal_prompt| {
        self.allocator.free(terminal_prompt);
    }

    self.allocator.destroy(self);
}

pub fn draw(self: *@This(), tabs: globals.Tabs, writer: anytype) !void {
    var buffered = std.io.bufferedWriter(writer);
    defer buffered.flush() catch @panic("There was an error flushing the stdout buffer!");

    const stdout = buffered.writer();
    try stdout.writeAll(Style.Value(.ClearScreen) ++ Style.Value(.ResetCursor));

    const size = try globals.getTerminalSize();

    if (size.cols <= 16 or size.rows <= 4) {
        try stdout.writeAll("Tab cannot be rendered, please resize your terminal.");
        return;
    }

    for (tabs.items, 0..) |display_tab, j| {
        if (display_tab.index == self.index) {
            try stdout.writeByte('~');
        }
        try stdout.writeAll(display_tab.readable_filename());

        if (!display_tab.saved) {
            try stdout.writeByte('*');
        }

        if (j != tabs.items.len - 1) {
            try stdout.writeAll(" | ");
        }
    }

    var lines: usize = 0;

    lines += 1;
    try stdout.writeByte('\n');

    const usable_rows = size.rows - 2;
    const usable_cols = size.cols;

    var line_start = self.cursor.y;

    if (line_start >= 1) {
        line_start -= line_start;
    }

    if (self.cursor.y >= @divFloor(usable_rows, 2)) {
        line_start = self.cursor.y - @divFloor(usable_rows, 2);
    }

    const line_end: usize = @min(self.lines_len(), line_start + usable_rows);

    const corrected_y = self.cursor.y + 2 - line_start;
    var corrected_x = self.cursor.x + 1;

    var start_line_txt: usize = 0;
    callculate_scrolling(&start_line_txt, &corrected_x, usable_cols);

    for (self.lines.items[line_start..line_end], line_start + 1..) |line, i| {
        const reserved_num_space = globals.num_strlen(self.lines_len()) + 3;
        const this_digit_len = globals.num_strlen(i);

        if (i - 1 == self.cursor.y) {
            corrected_x += reserved_num_space;
            try stdout.writeAll(Style.Value(.DarkGreenL));
        } else {
            try stdout.writeAll(Style.Value(.Gray));
        }

        if (this_digit_len < reserved_num_space - 3) {
            try stdout.writeByteNTimes(' ', reserved_num_space - 3 - this_digit_len);
        }

        try stdout.print("{d}", .{i});
        try stdout.writeAll(" | ");
        try stdout.writeAll(Style.Value(.Reset));

        var first_ignore: bool = false;

        const this_scroll = v: {
            if (self.editor.config.scrolling == .Line) {
                if (i - 1 == self.cursor.y) {
                    break :v start_line_txt;
                }

                break :v 0;
            }

            break :v start_line_txt;
        };

        if (this_scroll > 0) {
            try stdout.writeAll(Style.Value(.WhiteBG));
            try stdout.writeByte('<');
            try stdout.writeAll(Style.Value(.Reset));
            first_ignore = true;
        }

        if (this_scroll < line.items.len) {
            const highlighted = try highlight.scan(self.allocator, line.items[this_scroll..]);
            defer self.allocator.free(highlighted);

            var z: usize = 0;

            inner: for (highlighted) |e| {
                switch (e) {
                    .b => |c| {
                        z += 1;

                        if (first_ignore and z == 1) {
                            continue :inner;
                        }

                        if (z > usable_cols - reserved_num_space - 3) {
                            try stdout.writeAll(Style.Value(.Reset));
                            try stdout.writeAll(Style.Value(.WhiteBG));
                            try stdout.writeByte('>');
                            try stdout.writeAll(Style.Value(.Reset));
                            break :inner;
                        }

                        try stdout.writeAll(try unicode.encode(c));
                    },
                    inline .col => |c| {
                        try stdout.writeAll(Style.Value(c));
                    },
                }
            }
        }

        lines += 1;
        try stdout.writeByte('\n');
    }

    while (lines != size.rows - 1) : (lines += 1) {
        try stdout.writeByte('\n');
    }

    // Bottom Bar
    try stdout.writeAll(Style.Value(.WhiteBG));

    if (self.overwrite_bottom) |ob| {
        if (ob.len < size.cols) {
            try stdout.writeAll(ob);
            try stdout.writeByteNTimes(' ', size.cols - ob.len);
        }
    } else {
        const readable_path = try self.readable_filepath();
        defer self.allocator.free(readable_path);

        const left = try std.fmt.allocPrint(
            self.allocator,
            "{s} - {s}",
            .{ readable_path, self.readable_saved() },
        );
        defer self.allocator.free(left);

        const right = try std.fmt.allocPrint(
            self.allocator,
            "Line: {d}, Char: {d}",
            .{ self.cursor.y + 1, self.cursor.x },
        );
        defer self.allocator.free(right);

        if (left.len < size.cols) {
            try stdout.writeAll(left);

            const free_space: i64 = @intCast(size.cols - left.len);
            const spaces: i64 = @intCast(free_space - globals.i64_from(right.len));

            if (spaces >= 0) {
                try stdout.writeByteNTimes(' ', globals.usize_from(spaces));
                try stdout.writeAll(right);
            } else {
                try stdout.writeByteNTimes(' ', globals.usize_from(free_space));
            }
        } else {
            try stdout.writeByteNTimes(' ', globals.usize_from(size.cols));
        }
    }
    try stdout.writeAll(Style.Value(.Reset));
    try stdout.print("\x1b[{};{}H", .{ corrected_y, corrected_x });
}

pub inline fn lines_len(self: @This()) usize {
    return self.lines.items.len;
}

pub inline fn current_line(self: Tab) *globals.Line {
    std.debug.assert(self.cursor.y <= self.lines.items.len);
    return &self.lines.items[self.cursor.y];
}

pub fn save(self: *@This()) !globals.modify_response {
    if (self.filename == null) {
        std.debug.assert(self.filepath == null);

        const file_path_maybe_absolute = (try globals.text_prompt(self.allocator, "Enter file name: ")) orelse return .none;
        defer self.allocator.free(file_path_maybe_absolute);

        self.filepath = try unicode.toUtf8Alloc(self.allocator, file_path_maybe_absolute);
        errdefer if (self.filepath) |f| self.allocator.free(f);

        if (!std.fs.path.isAbsolute(self.filepath.?)) {
            const cwd = try std.process.getCwdAlloc(self.allocator);
            defer self.allocator.free(cwd);

            const old = self.filepath orelse unreachable;
            defer self.allocator.free(old);

            self.filepath = null;
            self.filepath = try std.fs.path.join(self.allocator, &.{ cwd, old });
        }

        const last_slash = std.mem.lastIndexOfScalar(u8, self.filepath.?, std.fs.path.sep) orelse unreachable;
        self.filename = try self.allocator.dupe(u8, self.filepath.?[last_slash + 1 ..]);
    }

    const f = try std.fs.createFileAbsolute(self.filepath.?, .{});
    defer f.close();

    var buffered_file = std.io.bufferedWriter(f.writer());
    defer buffered_file.flush() catch {};

    for (self.lines.items, 0..) |line, i| {
        for (line.items) |c| {
            try buffered_file.writer().writeAll(try unicode.encode(c));
        }

        if (i != self.lines.items.len - 1) {
            try buffered_file.writer().writeByte('\n');
        }
    }

    self.saved = true;
    return .none;
}

pub fn find(self: *@This(), tabs: *globals.Tabs) !globals.modify_response {
    const find_input = (try globals.text_prompt(self.allocator, "What do you want to find: ")) orelse return .none;
    defer self.allocator.free(find_input);

    const utf8_input = try unicode.toUtf8Alloc(self.allocator, find_input);
    defer self.allocator.free(utf8_input);

    self.overwrite_bottom = try std.fmt.allocPrint(self.allocator, "Searching for: {s}", .{utf8_input});
    defer if (self.overwrite_bottom) |ob| {
        self.overwrite_bottom = null;
        self.allocator.free(ob);
    } else unreachable;

    var found: bool = false;
    var first_run: bool = true;
    const began_from_null: bool = self.cursor.y == 0;

    outer: while (true) {
        defer first_run = false;

        const start_idx = if (first_run) self.cursor.y else 0;

        wouter: for (self.lines.items[start_idx..], start_idx..) |line, y| {
            self.cursor.y = y;
            self.cursor.x = 0;

            search: while (std.mem.indexOfPos(u21, line.items, self.cursor.x, find_input)) |x_loc| {
                self.cursor.x = x_loc;

                found = true;

                try self.draw(tabs.*, std.io.getStdOut().writer());

                const input = try Input.parseStdin();

                if (input.key == .enter) {
                    if (!self.can_move(.Right)) {
                        break :wouter;
                    } else {
                        self.cursor.x += 1;
                        continue :search;
                    }
                } else if (input.key == .escape)
                    break :outer
                else {
                    if (input.isHotBind(.Ctrl, 'f')) {
                        break :outer; // hmm.. i don't think it's good
                    }

                    return try self.modify(tabs, input);
                }
            }
        }

        if (!found) {
            if (!began_from_null and first_run) {
                self.cursor.y = 0;
                continue :outer;
            }

            const old = self.overwrite_bottom orelse unreachable;
            defer self.allocator.free(old);

            self.overwrite_bottom = null;
            self.overwrite_bottom = try std.fmt.allocPrint(self.allocator, "Nothing has been found for: {s}", .{utf8_input});

            try self.draw(tabs.*, std.io.getStdOut().writer());
            _ = try Input.parseStdin();
            break :outer;
        } else {
            continue :outer;
        }
    }

    return .none;
}

fn callculate_scrolling(start_line: *usize, cor_x: *usize, cols: usize) void {
    while (cor_x.* > @divFloor(cols, 2)) {
        start_line.* += 1;
        cor_x.* -= 1;
    }
}

pub fn modify(self: *@This(), tabs: *globals.Tabs, input: Input) anyerror!globals.modify_response {
    if (input.isHotBind(.Ctrl, 'd')) { // Duplicate Line
        var new_line = globals.Line{};
        errdefer new_line.deinit(self.allocator);

        try new_line.appendSlice(self.allocator, self.current_line().items);
        try self.lines.insert(self.cursor.y, new_line);
        return .none;
    }

    if (input.isHotBind(.Ctrl, 'k')) { // Move to the Tab at the Left
        if (tabs.items.len == 1)
            return .none;

        return .{
            .focus = if (self.index == 0) tabs.items.len - 1 else self.index - 1,
        };
    }

    if (input.isHotBind(.Ctrl, 'l')) { // Move to the Tab at the Right
        if (tabs.items.len == 1)
            return .none;

        return .{
            .focus = if (self.index == tabs.items.len - 1) 0 else self.index + 1,
        };
    }

    if (input.isHotBind(.Ctrl, 'n')) { // Create a new tab
        const empty = try Tab.create(self.allocator, tabs.items.len, self.editor);
        errdefer empty.deinit();

        try empty.lines.append(globals.Line{});
        try tabs.append(empty);
        return .{ .focus = tabs.items.len - 1 };
    }

    if (input.isHotBind(.Ctrl, 's')) { // Save a file
        return try self.save();
    }

    if (input.isHotBind(.Ctrl, 'o')) { // Open a file
        return try Boxes.open_file(self, tabs);
    }

    if (input.isHotBind(.Ctrl, 'p')) { // Open a terminal
        self.terminal_prompt = try Boxes.terminal(self, tabs);
        return .none;
    }

    if (input.isHotBind(.Alt, 'j')) { // Jump to a line
        const line = try globals.text_prompt(self.allocator, "Line: ") orelse return .none;
        defer self.allocator.free(line);

        const line_utf8 = try unicode.toUtf8Alloc(self.allocator, line);
        defer self.allocator.free(line_utf8);

        var num = std.fmt.parseInt(usize, line_utf8, 10) catch |e| {
            switch (e) {
                std.fmt.ParseIntError.InvalidCharacter => return .none,
                else => return e,
            }
        };

        if (num > self.lines_len())
            num = self.lines_len();

        self.cursor.y = globals.sub_1_ignore_overflow(num);
        self.cursor.x = self.current_line().items.len;
        return .none;
    }

    if (input.isHotBind(.Ctrl, 'w')) {
        if (tabs.items.len == 1) {
            return .none;
        }

        if (tabs.items.len > self.index) {
            for (tabs.items[self.index + 1 ..]) |i| {
                i.index -= 1;
            }
        }

        _ = tabs.orderedRemove(self.index);
        defer self.deinit();

        return .{
            .focus = globals.sub_1_ignore_overflow(self.index),
        };
    }

    if (input.isHotBind(.Ctrl, 'f')) {
        return try self.find(tabs);
    }

    switch (input.key) {
        .arrow => |a| {
            if (input.modifiers.hasAlt() and (a == .Up or a == .Down)) {
                if (!self.can_move(a))
                    return .none;

                const replacer = &(switch (a) {
                    .Up => self.lines.items[self.cursor.y - 1],
                    .Down => self.lines.items[self.cursor.y + 1],
                    else => unreachable,
                });

                const tmp = replacer.items;

                replacer.items = self.current_line().items;
                self.current_line().items = tmp;
            }

            switch (a) {
                .Up, .Down => {
                    const previous = self.current_line();

                    if (self.cursor.move_bl(self.lines_len(), self.lines_len(), a)) {
                        if (self.cursor.x == previous.items.len or self.cursor.x > self.current_line().items.len) {
                            self.cursor.x = self.current_line().items.len;
                        }
                    }

                    return .none;
                },
                .Left => {
                    if (!self.can_move(.Left) and self.can_move(.Up)) {
                        self.move(.Up);
                        self.cursor.x = self.current_line().items.len;
                        return .none;
                    }
                },
                .Right => {
                    if (!self.can_move(.Right) and self.can_move(.Down)) {
                        self.move(.Down);
                        self.cursor.x = 0;
                        return .none;
                    }
                },
            }
        },
        .enter => {
            var line = globals.Line{};
            errdefer line.deinit(self.allocator);

            if (self.can_move(.Right)) {
                try line.appendSlice(self.allocator, self.current_line().items[self.cursor.x..self.current_line().items.len]);
                self.current_line().items.len = self.cursor.x;
            }

            try self.lines.insert(self.cursor.y + 1, line);

            self.saved = false;
            self.cursor.x = 0;
            self.move(.Down);
            return .none;
        },
        .backspace => {
            if (!self.can_move(.Left) and self.can_move(.Up)) {
                self.saved = false;
                var removed = self.lines.orderedRemove(self.cursor.y);
                defer removed.deinit(self.allocator);
                self.cursor.y -= 1;
                self.cursor.x = self.current_line().items.len;
                try self.current_line().appendSlice(self.allocator, removed.items);
                return .none;
            }
        },
        else => {},
    }

    return try globals.modify_line(self.allocator, self.current_line(), self.cursor, &self.saved, &self.actions, input, self);
}

// Some small little functions to make it easier
pub fn can_move(self: *@This(), direction: globals.Direction) bool {
    return self.cursor.can_move(self.lines_len(), self.current_line().items.len, direction);
}

pub fn move(self: *@This(), direction: globals.Direction) void {
    return self.cursor.move(self.lines_len(), self.current_line().items.len, direction);
}

pub fn move_bl(self: *@This(), direction: globals.Direction) bool {
    return self.cursor.move_bl(self.lines_len(), self.current_line().items.len, direction);
}

// Functions to make paths readable
pub inline fn readable_filename(self: Tab) []const u8 {
    return self.filename orelse globals.no_filename;
}

pub inline fn readable_filepath(self: Tab) ![]const u8 {
    return if (self.filepath) |filepath|
        readable_filepath_raw(self.allocator, filepath)
    else
        self.allocator.dupe(u8, globals.no_filepath);
}

pub inline fn readable_saved(self: Tab) []const u8 {
    return if (self.saved) "Saved" else "Unsaved";
}

pub fn readable_filepath_raw(allocator: std.mem.Allocator, filepath: []u8) ![]u8 {
    const cwd = try std.process.getCwdAlloc(allocator);
    defer allocator.free(cwd);

    const f = try std.fs.path.relative(allocator, cwd, filepath);
    defer allocator.free(f);

    return try std.fmt.allocPrint(allocator, "${c}{s}", .{ std.fs.path.sep, f });
}

pub fn readable_filepath_cwd(allocator: std.mem.Allocator, filepath: []const u8) ![]u8 {
    const cwd = try std.process.getCwdAlloc(allocator);
    defer allocator.free(cwd);

    return try std.fs.path.join(allocator, &.{ cwd, filepath });
}
