const std = @import("std");
const Box = @import("box.zig");
const globals = @import("globals.zig");
const Tab = @import("tab.zig");
const unicode = @import("unicode.zig");
const Style = @import("styles.zig");
const Input = @import("input.zig");

pub fn open_file(tab: *Tab, tabs: *globals.Tabs) !globals.modify_response {
    var box = Box.init(tab.allocator, true);
    defer box.deinit();

    var ignoreMap = std.ArrayList([]u8).init(tab.allocator);
    defer ignoreMap.deinit();
    defer for (ignoreMap.items) |s| tab.allocator.free(s);

    const maybe_vignore: ?[]u8 = std.fs.cwd().readFileAlloc(
        tab.allocator,
        ".vignore",
        std.math.maxInt(usize),
    ) catch |e| v: {
        switch (e) {
            error.FileNotFound => break :v null,
            else => return e,
        }
    };

    if (maybe_vignore) |vignore| {
        defer tab.allocator.free(vignore);
        var tokens = std.mem.splitScalar(u8, vignore, '\n');

        while (tokens.next()) |t| {
            try ignoreMap.append(try tab.allocator.dupe(u8, t));
        }
    }

    var filtered_paths = std.ArrayListUnmanaged([]const u8){};
    defer filtered_paths.deinit(tab.allocator);
    defer for (filtered_paths.items) |e| tab.allocator.free(e);

    // std.fs.cwd().walk requires iterabledir permission, which std.fs.cwd() doesn't have
    var cwd = try std.fs.cwd().openDir(".", .{ .iterate = true });
    defer cwd.close();

    var walker = try cwd.walk(tab.allocator);
    defer walker.deinit();

    walker_loop: while (try ignore_specific_err(&walker)) |e| {
        if (e.kind == .directory)
            continue :walker_loop;

        if (ignoreMap.items.len >= 1) {
            // x/y/z => x
            const origin = std.mem.indexOfScalar(u8, e.path, '/') orelse e.path.len;

            for (ignoreMap.items) |t| {
                if (std.mem.eql(u8, t, e.path[0..origin]))
                    continue :walker_loop;
            }
        }

        try filtered_paths.append(
            tab.allocator,
            try tab.allocator.dupe(u8, e.path),
        );
    }

    var actions = globals.Actions.init(tab.allocator);
    defer globals.Actions_deinit(&actions);

    var first_run: bool = true;

    var older = try filtered_paths.clone(tab.allocator);
    defer older.deinit(tab.allocator);

    o: while (true) {
        defer first_run = false;

        var buffered_overlay = std.io.bufferedWriter(std.io.getStdOut().writer());
        const overlay = buffered_overlay.writer();

        try overlay.writeAll(Style.Value(.ClearScreen));
        try overlay.writeAll(Style.Value(.HideCursor));

        const re_filter = filtered_paths.items.len != 0 and !first_run and box.metadata.last_action == .Key;
        const searched_paths = if (re_filter) v: {
            const utf8_input = try unicode.toUtf8Alloc(tab.allocator, box.input.items);
            defer tab.allocator.free(utf8_input);

            if (utf8_input.len == 0) {
                break :v try filtered_paths.clone(tab.allocator);
            }

            var searched = std.ArrayListUnmanaged([]const u8){};
            errdefer searched.deinit(tab.allocator);

            for (filtered_paths.items) |filetered_path| {
                if (std.mem.containsAtLeast(u8, filetered_path, 1, utf8_input)) {
                    try searched.append(tab.allocator, filetered_path);
                }
            }

            break :v searched;
        } else older;

        defer {
            if (re_filter) {
                older.deinit(tab.allocator);
                older = searched_paths;
            }
        }

        if (box.input_cursor.y > searched_paths.items.len)
            box.input_cursor.y = globals.sub_1_ignore_overflow(searched_paths.items.len);

        try tab.draw(tabs.*, overlay); // Draw the background
        try box.draw(searched_paths.items, overlay);
        try buffered_overlay.flush();

        const input = try Input.parseStdin();

        switch (try box.modify(input, searched_paths.items.len, &actions)) {
            .focus => {
                if (searched_paths.items.len == 0)
                    continue :o;

                const focused = searched_paths.items[box.input_cursor.y];

                const focused_absolute = try Tab.readable_filepath_cwd(tab.allocator, focused);
                defer tab.allocator.free(focused_absolute);

                for (tabs.items) |t| {
                    if (t.filepath) |fp| {
                        if (std.mem.eql(u8, focused_absolute, fp)) {
                            return .{ .focus = t.index };
                        }
                    }
                }

                const new_tab = try Tab.open_from_file(tab.allocator, tabs.items.len, focused_absolute, tab.editor);
                errdefer new_tab.deinit();

                try tabs.append(new_tab);

                return .{
                    .focus = tabs.items.len - 1,
                };
            },
            .none => {},
            .exit => break :o,
        }
    }

    return .none;
}

pub fn terminal(tab: *Tab, tabs: *globals.Tabs) ![]globals.Char {
    var box = Box.init(tab.allocator, false);
    defer box.deinit();

    var buffer = std.ArrayList(u8).init(tab.allocator);
    defer buffer.deinit();

    if (tab.terminal_prompt) |terminal_prompt| {
        try box.input.appendSlice(tab.allocator, terminal_prompt);
        box.input_cursor.x = box.input.items.len;
        tab.allocator.free(terminal_prompt);
    }

    o: while (true) {
        var actions = globals.Actions.init(tab.allocator);
        defer globals.Actions_deinit(&actions);

        j: while (true) {
            var buffered_overlay = std.io.bufferedWriter(std.io.getStdOut().writer());
            const overlay = buffered_overlay.writer();

            try overlay.writeAll(Style.Value(.ClearScreen));

            var splitted = try unicode.toSplittedUtf8(tab.allocator, buffer.items);
            defer splitted.deinit();

            try tab.draw(tabs.*, overlay); // Draw the background
            try box.draw(splitted.items, overlay);
            try buffered_overlay.flush();

            const input = try Input.parseStdin();
            switch (try box.modify(input, buffer.items.len, &actions)) {
                .none => {},
                .exit => break :o,
                .focus => break :j,
            }
        }

        buffer.items.len = 0;

        var argv = std.ArrayList([]u8).init(tab.allocator);
        defer argv.deinit();
        defer for (argv.items) |arg| tab.allocator.free(arg);

        var split = std.mem.splitScalar(globals.Char, box.input.items, ' ');

        while (split.next()) |s| {
            const unicode_s = try unicode.toUtf8Alloc(tab.allocator, s);
            errdefer tab.allocator.free(unicode_s);

            try argv.append(unicode_s);
        }

        var process = std.process.Child.init(argv.items, tab.allocator);
        process.stdout_behavior = .Pipe;
        process.stderr_behavior = .Pipe;
        process.stdin_behavior = .Close;
        try process.spawn();

        var poller = std.io.poll(tab.allocator, enum { stdout, stderr }, .{
            .stdout = process.stdout.?,
            .stderr = process.stderr.?,
        });
        defer poller.deinit();

        const stdout_fifo = poller.fifo(.stdout);
        const stderr_fifo = poller.fifo(.stderr);

        while (try poller.poll()) {
            var buffered_overlay = std.io.bufferedWriter(std.io.getStdOut().writer());
            const overlay = buffered_overlay.writer();

            try overlay.writeAll(Style.Value(.ClearScreen));

            if (stdout_fifo.count >= 1) {
                try stdout_fifo.reader().readAllArrayList(&buffer, 1 << 21);
            }
            if (stderr_fifo.count >= 1) {
                try stderr_fifo.reader().readAllArrayList(&buffer, 1 << 21);
            }

            var splitted = try unicode.toSplittedUtf8(tab.allocator, buffer.items);
            defer splitted.deinit();

            try tab.draw(tabs.*, overlay); // Draw the background
            try box.draw(splitted.items, overlay);
            try buffered_overlay.flush();
        }
    }

    return try box.input.toOwnedSlice(tab.allocator);
}

inline fn ignore_specific_err(walker: *std.fs.Dir.Walker) !?std.fs.Dir.Walker.Entry {
    var o = walker.next();
    while (o == error.AccessDenied) : (o = walker.next()) {}
    return o;
}
