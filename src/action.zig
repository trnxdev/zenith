const globals = @import("globals.zig");

const CharAction = struct {
    x: usize,
    y: usize,
    c: []globals.Char,
};

pub const Action = union(enum) {
    insert_char: CharAction,
    del_char: CharAction,
};
