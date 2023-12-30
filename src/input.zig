const std = @import("std");
const globals = @import("globals.zig");

modifiers: Modifiers = .{},
key: Key,

const HotBind_0 = union(enum) { Ctrl };
pub fn isHotBind(self: @This(), hotbind_0: HotBind_0, char: globals.Char) bool {
    return switch (hotbind_0) {
        .Ctrl => self.modifiers.ctrl and self.key == .char and self.key.char == char,
    };
}

pub const Key = union(enum) {
    escape: void,
    backspace: void,
    tab: void,
    enter: void,
    char: globals.Char,
    arrow: globals.Direction,
};

pub const Modifiers = packed struct {
    ctrl: bool = false,
    alt: bool = false,
};

pub fn parse_stdin() !@This() {
    var buf: [8]u8 = undefined;
    const read = try std.io.getStdIn().reader().read(&buf);
    return Inputs.get(buf[0..read]) orelse @This(){ .key = .{ .char = try std.unicode.utf8Decode(buf[0..read]) } };
}

// No, you can't just make a huge StringHashMap with all @This()s-
// haha
const Inputs = std.ComptimeStringMap(@This(), .{
    .{ str(std.ascii.control_code.etx), .{ .modifiers = .{ .ctrl = true }, .key = .{ .char = 'c' } } },
    .{ str(std.ascii.control_code.esc), .{ .key = .escape } },
    .{ str(std.ascii.control_code.vt), .{ .modifiers = .{ .ctrl = true }, .key = .{ .char = 'k' } } },
    .{ str(std.ascii.control_code.ff), .{ .modifiers = .{ .ctrl = true }, .key = .{ .char = 'l' } } },
    .{ str(std.ascii.control_code.so), .{ .modifiers = .{ .ctrl = true }, .key = .{ .char = 'n' } } },
    .{ str(std.ascii.control_code.del), .{ .key = .backspace } },
    .{ str(std.ascii.control_code.dc3), .{ .modifiers = .{ .ctrl = true }, .key = .{ .char = 's' } } },
    .{ str(std.ascii.control_code.si), .{ .modifiers = .{ .ctrl = true }, .key = .{ .char = 'o' } } },
    .{ str(std.ascii.control_code.dle), .{ .modifiers = .{ .ctrl = true }, .key = .{ .char = 'p' } } },
    .{ str(std.ascii.control_code.etb), .{ .modifiers = .{ .ctrl = true }, .key = .{ .char = 'w' } } },
    .{ str(std.ascii.control_code.bs), .{ .modifiers = .{ .ctrl = true }, .key = .backspace } },
    .{ str(10), .{ .key = .enter } },
    .{ str('\t'), .{ .key = .tab } },
    // Arrows
    .{ "\x1b[A", .{ .key = .{ .arrow = .Up } } },
    .{ "\x1b[B", .{ .key = .{ .arrow = .Down } } },
    .{ "\x1b[C", .{ .key = .{ .arrow = .Right } } },
    .{ "\x1b[D", .{ .key = .{ .arrow = .Left } } },
    // Ctrl-Arrows
    .{ "\x1b[1;5A", .{ .modifiers = .{ .ctrl = true }, .key = .{ .arrow = .Up } } },
    .{ "\x1b[1;5B", .{ .modifiers = .{ .ctrl = true }, .key = .{ .arrow = .Down } } },
    .{ "\x1b[1;5C", .{ .modifiers = .{ .ctrl = true }, .key = .{ .arrow = .Right } } },
    .{ "\x1b[1;5D", .{ .modifiers = .{ .ctrl = true }, .key = .{ .arrow = .Left } } },
    //  .{ &[_]u8{ std.ascii.control_code.esc, '[', 'A' }, .{ .key = .{ .arrow = .Up } } },
});

inline fn str(comptime control: comptime_int) []const u8 {
    comptime return &[_]u8{control};
}
