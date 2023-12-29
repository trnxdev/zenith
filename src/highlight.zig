// TODO: Make the highlighting better
const std = @import("std");
const Style = @import("styles.zig");
const globals = @import("globals.zig");
const unicode = @import("unicode.zig");

pub const Keywords = std.ComptimeStringMap(Style.Enum, .{
    .{ "fn", .Blue },
    .{ "func", .Blue },
    .{ "fun", .Blue },
    .{ "function", .Blue },
    .{ "def", .Blue },
    // Variable keywords
    .{ "const", .Blue },
    .{ "var", .Blue },
    .{ "let", .Blue },
    // Comptime
    .{ "comptime", .Blue },
    // Type keywords
    .{ "struct", .Blue },
    .{ "enum", .Blue },
    .{ "union", .Blue },
    .{ "type", .Blue },
    .{ "interface", .Blue },
    .{ "impl", .Blue },
    .{ "trait", .Blue },
    .{ "class", .Blue },
    .{ "abstract", .Blue },
    .{ "final", .Blue },
    .{ "override", .Blue },
    .{ "public", .Blue },
    .{ "private", .Blue },
    .{ "protected", .Blue },
    .{ "internal", .Blue },
    .{ "static", .Blue },
    .{ "extern", .Blue },
    .{ "inline", .Blue },
    .{ "noinline", .Blue },
    .{ "pub", .Blue },
    // Control flow keywords
    .{ "if", .Purple },
    .{ "else", .Purple },
    .{ "for", .Purple },
    .{ "while", .Purple },
    .{ "loop", .Purple },
    .{ "break", .Purple },
    .{ "continue", .Purple },
    .{ "switch", .Purple },
    .{ "return", .Purple },
    .{ "defer", .Purple },
    .{ "unreachable", .Purple },
    // Boolean keywords
    .{ "true", .Blue },
    .{ "false", .Blue },
    // Null keyword
    .{ "null", .Blue },
    .{ "nil", .Blue },
    .{ "undefined", .Blue },
    // Errors
    .{ "error", .Blue },
    .{ "raise", .Purple },
    .{ "throw", .Purple },
    .{ "try", .Purple },
    .{ "catch", .Purple },
    .{ "finally", .Purple },
    // Async
    .{ "async", .Blue },
    .{ "await", .Purple },
});

pub fn advance(file: []const globals.Char, i: *usize) globals.Char {
    if (i.* >= file.len) {
        return 0;
    }
    defer i.* += 1;
    return file[i.*];
}

const CharColored = union(enum) {
    b: globals.Char,
    col: Style.Enum,
};

pub fn scan(allocator: std.mem.Allocator, file: []globals.Char) ![]CharColored {
    var fl = std.ArrayList(CharColored).init(allocator);
    defer fl.deinit();

    var i: usize = 0;

    while (true) {
        if (i >= file.len) {
            break;
        }

        var c = advance(file, &i);

        switch (c) {
            '/' => {
                const start = i - 1;
                if (advance(file, &i) == '/') {
                    var advanced = advance(file, &i);
                    while (advanced != '\n' and advanced != 0) {
                        advanced = advance(file, &i);
                    }
                    try fl.append(.{ .col = .DarkGreen });
                    for (file[start..i]) |_c| {
                        try fl.append(.{ .b = _c });
                    }
                    try fl.append(.{ .col = .Reset });
                    continue;
                } else {
                    for (file[start..i]) |_c| {
                        try fl.append(.{ .b = _c });
                    }
                    i += 1;
                }
            },
            '0'...'9' => {
                const start = i - 1;

                while (unicode.isDigit(peek(file, i))) {
                    c = advance(file, &i);

                    if (c == '.' and unicode.isDigit(peek(file, i))) {
                        c = advance(file, &i);
                    }
                }

                try fl.append(.{ .col = .Green });
                for (file[start..i]) |_c| {
                    try fl.append(.{ .b = _c });
                }
                try fl.append(.{ .col = .Reset });
                continue;
            },
            'a'...'z', 'A'...'Z', '_' => {
                const start = i - 1;

                while (unicode.isAlphanumeric(peek(file, i)) or peek(file, i) == '_') {
                    _ = advance(file, &i);
                }

                const ident_utf8 = try unicode.toUtf8Alloc(allocator, file[start..i]);
                defer allocator.free(ident_utf8);

                if (peek(file, i) == '(') {
                    try fl.append(.{ .col = .Yellow });
                } else if (peek(file, i) == '.' and !pre_char_dot_call(file, i)) {
                    try fl.append(.{ .col = .DarkGreenL });
                } else if (Keywords.get(ident_utf8)) |cl| {
                    try fl.append(.{ .col = cl });
                } else {
                    try fl.append(.{ .col = .Cyan });
                }
                for (file[start..i]) |_c| {
                    try fl.append(.{ .b = _c });
                }
                try fl.append(.{ .col = .Reset });
                continue;
            },
            '"', '\'' => {
                const cr = c;
                const start = i - 1;
                var terminated: bool = true;

                var advanced = advance(file, &i);
                while (advanced != cr and advanced != 0) {
                    advanced = advance(file, &i);
                }

                if (peek(file, i) == 0) {
                    terminated = false;
                }

                try fl.append(.{ .col = .DarkOrange });
                for (file[start..i], 0..) |_c, jm| {
                    _ = jm;
                    try fl.append(.{ .b = _c });
                }
                try fl.append(.{ .col = .Reset });
            },
            else => {
                try fl.append(.{ .b = c });
            },
        }
    }

    return try fl.toOwnedSlice();
}

pub fn peek(file: []const globals.Char, i: usize) globals.Char {
    if (i >= file.len) {
        return 0;
    }
    return file[i];
}

pub fn peekN(file: []const globals.Char, i: usize) globals.Char {
    if (i + 1 >= file.len) {
        return 0;
    }
    return file[i + 1];
}

pub fn pre_char_dot_call(file: []const globals.Char, i: usize) bool {
    var y: usize = i - 1;
    while (isIdent(file[y])) {
        if (y == 0) {
            break;
        }

        y -= 1;
    }

    if (y == 0) {
        return false;
    }
    return file[y] == '.' and !isIdent(file[y - 1]);
}

pub fn isIdent(c: globals.Char) bool {
    return unicode.isAlphanumeric(c) or c == '_';
}
