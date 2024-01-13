const std = @import("std");
const globals = @import("globals.zig");
const unicode = @import("unicode.zig");

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

pub fn isHotBind(self: @This(), comptime mod: Modifiers, char: globals.Char) bool {
    comptime {
        if (mod == .None)
            @compileError("Are you for real?");
    }

    return self.modifiers.is(mod) and self.key == .char and self.key.char == char;
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
    CtrlAlt,
    None,

    pub inline fn is(self: @This(), comptime mod: Modifiers) bool {
        return self == mod;
    }

    pub inline fn hasCtrl(self: @This()) bool {
        return self.is(.Ctrl) or self.is(.CtrlAlt);
    }

    pub inline fn hasAlt(self: @This()) bool {
        return self.is(.Alt) or self.is(.CtrlAlt);
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

const control_code = std.ascii.control_code;

const parse_stdin_error = std.os.ReadError || parse_error;
pub inline fn parseStdin() parse_stdin_error!@This() {
    var buf: [8]u8 = undefined;
    const read = try std.io.getStdIn().reader().read(&buf);
    return parse(buf[0..read]);
}

const parse_error = unicode.decode_error;
pub fn parse(buf: []const u8) parse_error!@This() {
    return switch (buf[0]) {
        // Esc + (Alt, Ctrl or Normal-(Arrow)) +  Alt-(Ctrl-() or ())
        control_code.esc => if (buf.len == 1)
            Input.new(.None, .escape)
        else {
            // (Alt, Ctrl or Normal-(Arrow))
            return Arrows.get(buf[1..]) orelse {
                // Alt-(Ctrl-() or ())
                // In case, it's ctrl + alt, it's formatted like: [Alt][Ctrl Sequence]
                var char = try parse(buf[1..]);
                char.modifiers = if (char.modifiers.hasCtrl()) .CtrlAlt else .Alt;
                return char;
            };
        },
        // General
        control_code.del => Input.new(.None, .backspace),
        control_code.ht => Input.new(.None, .tab),
        control_code.lf => Input.new(.None, .enter),
        // Ctrl-()
        control_code.bs => Input.new(.Ctrl, .backspace),
        control_code.vt => Input.newChar(.Ctrl, 'k'),
        control_code.ff => Input.newChar(.Ctrl, 'l'),
        control_code.so => Input.newChar(.Ctrl, 'n'),
        control_code.si => Input.newChar(.Ctrl, 'o'),
        control_code.etx => Input.newChar(.Ctrl, 'c'),
        control_code.dc3 => Input.newChar(.Ctrl, 's'),
        control_code.dle => Input.newChar(.Ctrl, 'p'),
        control_code.etb => Input.newChar(.Ctrl, 'w'),
        control_code.sub => Input.newChar(.Ctrl, 'z'),
        control_code.eot => Input.newChar(.Ctrl, 'd'),
        control_code.ack => Input.newChar(.Ctrl, 'f'),
        // Default
        else => Input.newChar(.None, try unicode.decode(buf)),
    };
}

// They do not include Escape Sequence at the start! ("\x1b")
// TODO: Get rid of this
const Arrows = std.ComptimeStringMap(Input, .{
    // Regular Arrows
    .{ "[A", Input.newArrow(.None, .Up) },
    .{ "[B", Input.newArrow(.None, .Down) },
    .{ "[C", Input.newArrow(.None, .Right) },
    .{ "[D", Input.newArrow(.None, .Left) },
    // Ctrl-Alt Arrows
    .{ "[1;7A", Input.newArrow(.CtrlAlt, .Up) },
    .{ "[1;7B", Input.newArrow(.CtrlAlt, .Down) },
    .{ "[1;7C", Input.newArrow(.CtrlAlt, .Right) },
    .{ "[1;7D", Input.newArrow(.CtrlAlt, .Left) },
    // Ctrl Arrows
    .{ "[1;5A", Input.newArrow(.Ctrl, .Up) },
    .{ "[1;5B", Input.newArrow(.Ctrl, .Down) },
    .{ "[1;5C", Input.newArrow(.Ctrl, .Right) },
    .{ "[1;5D", Input.newArrow(.Ctrl, .Left) },
    // Alt Arrows
    .{ "[1;3A", Input.newArrow(.Alt, .Up) },
    .{ "[1;3B", Input.newArrow(.Alt, .Down) },
    .{ "[1;3C", Input.newArrow(.Alt, .Right) },
    .{ "[1;3D", Input.newArrow(.Alt, .Left) },
});

inline fn str(comptime control: comptime_int) []const u8 {
    comptime return &[_]u8{control};
}

inline fn str_fill(comptime control: comptime_int, comptime fill: []const u8) []const u8 {
    var filled = [_]u8{0} ** (fill.len + 1);

    filled[0] = control;
    std.mem.copyForwards(u8, filled[1..], fill);

    return &filled;
}
