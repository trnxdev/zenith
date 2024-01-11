const std = @import("std");
const globals = @import("globals.zig");

const Input = @This();

modifiers: Modifiers = .None,
key: Key,

pub inline fn new(comptime mod: Modifiers, comptime key: Key) @This() {
    comptime return .{ .modifiers = mod, .key = key };
}

pub inline fn newArrow(comptime mod: Modifiers, comptime arrow: globals.Direction) @This() {
    comptime return .{ .modifiers = mod, .key = .{ .arrow = arrow } };
}

pub inline fn newChar(comptime mod: Modifiers, char: globals.Char) @This() {
    return .{ .modifiers = mod, .key = .{ .char = char } };
}

// TODO: make this better
pub fn isHotBind(self: @This(), comptime mod: Modifiers, char: globals.Char) bool {
    comptime {
        if (mod == .None) {
            @compileError("Are you for real?");
        }
    }

    return switch (mod) {
        .Ctrl => self.modifiers.isCtrl() and self.key == .char and self.key.char == char,
        .Alt => self.modifiers.isAlt() and self.key == .char and self.key.char == char,
        .None => @compileError("Are you for real?"),
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

pub const Modifiers = enum {
    Ctrl,
    Alt,
    None,

    pub inline fn isCtrl(self: @This()) bool {
        return self == .Ctrl;
    }

    pub inline fn isAlt(self: @This()) bool {
        return self == .Alt;
    }
};

// zig fmt: off
const utf8_decode_error =
    std.unicode.Utf8DecodeError
||  error { CharNotFound };
// zig fmt: on
fn utf8Decode(bytes: []const u8) utf8_decode_error!u21 {
    return switch (bytes.len) {
        1 => @as(u21, bytes[0]),
        2 => std.unicode.utf8Decode2(bytes),
        3 => std.unicode.utf8Decode3(bytes),
        4 => std.unicode.utf8Decode4(bytes),
        else => return utf8_decode_error.CharNotFound,
    };
}

pub fn parseStdin() !@This() {
    var buf: [8]u8 = undefined;
    const read = try std.io.getStdIn().reader().read(&buf);
    return Inputs.get(buf[0..read]) orelse Input.newChar(.None, try std.unicode.utf8Decode(buf[0..read]));
}

// zig fmt: off
const Inputs = std.ComptimeStringMap(@This(), .{
    .{ str(std.ascii.control_code.esc), Input.new(.None, .escape    ) },
    .{ str(std.ascii.control_code.del), Input.new(.None, .backspace ) },
    .{ str(std.ascii.control_code.ht),  Input.new(.None, .tab       ) },
    .{ str(std.ascii.control_code.lf),  Input.new(.None, .enter     ) },
    // Alt-()
    .{ str_fill(std.ascii.control_code.esc, &.{'j'}), Input.newChar(.Alt, 'j') },
    // Ctrl-()
    .{ str(std.ascii.control_code.bs),  Input.new(.Ctrl, .backspace) },
    .{ str(std.ascii.control_code.vt),  Input.newChar(.Ctrl, 'k')   },
    .{ str(std.ascii.control_code.ff),  Input.newChar(.Ctrl, 'l')   },
    .{ str(std.ascii.control_code.so),  Input.newChar(.Ctrl, 'n')   },
    .{ str(std.ascii.control_code.si),  Input.newChar(.Ctrl, 'o')   },
    .{ str(std.ascii.control_code.etx), Input.newChar(.Ctrl, 'c')   },
    .{ str(std.ascii.control_code.dc3), Input.newChar(.Ctrl, 's')   },
    .{ str(std.ascii.control_code.dle), Input.newChar(.Ctrl, 'p')   },
    .{ str(std.ascii.control_code.etb), Input.newChar(.Ctrl, 'w')   },
    .{ str(std.ascii.control_code.sub), Input.newChar(.Ctrl, 'z')   },
    .{ str(std.ascii.control_code.eot), Input.newChar(.Ctrl, 'd')   },
    .{ str(std.ascii.control_code.ack), Input.newChar(.Ctrl, 'f')   },
    // Arrows
    .{ "\x1b[A", Input.newArrow(.None, .Up)    },
    .{ "\x1b[B", Input.newArrow(.None, .Down)  },
    .{ "\x1b[C", Input.newArrow(.None, .Right) },
    .{ "\x1b[D", Input.newArrow(.None, .Left)  },
    // Ctrl-Arrows
    .{ "\x1b[1;5A", Input.newArrow(.Ctrl, .Up )    },
    .{ "\x1b[1;5B", Input.newArrow(.Ctrl, .Down )  },
    .{ "\x1b[1;5C", Input.newArrow(.Ctrl, .Right ) },
    .{ "\x1b[1;5D", Input.newArrow(.Ctrl, .Left )  },
    // Alt-Arrows
    .{ "\x1b[1;3A", Input.newArrow(.Alt, .Up)    },
    .{ "\x1b[1;3B", Input.newArrow(.Alt, .Down)  },
    .{ "\x1b[1;3C", Input.newArrow(.Alt, .Right) },
    .{ "\x1b[1;3D", Input.newArrow(.Alt, .Left)  },
});
// zig fmt: on

inline fn str(comptime control: comptime_int) []const u8 {
    comptime return &[_]u8{control};
}

inline fn str_fill(comptime control: comptime_int, comptime fill: []const u8) []const u8 {
    var filled = [_]u8{0} ** (fill.len + 1);

    filled[0] = control;
    std.mem.copyForwards(u8, filled[1..], fill);

    return &filled;
}
