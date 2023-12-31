const globals = @import("globals.zig");

const CharAction = struct {
    x: usize,
    y: usize,
    c: globals.Char,
};

const CharsAction = struct {
    x: usize,
    y: usize,
    c: []globals.Char,
};

pub const Action = union(enum) {
    insert_char: CharAction,
    insert_mul_char: CharsAction,
    del_char: CharAction,
};
