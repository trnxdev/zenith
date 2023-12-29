pub const Enum = enum {
    Reset,
    HideCursor,
    ShowCursor,
    Yellow,
    DarkGreen,
    DarkGreenL,
    Blue,
    Purple,
    Green,
    Cyan,
    DarkOrange,
    LightGreen,
    Gray,
    GrayBG,
    WhiteBG,
    Black,
    ClearScreen,
    ResetCursor,
};

pub inline fn Value(style_enum: Enum) []const u8 {
    return switch (style_enum) {
        .Blue => "\x1b[34m",
        .Purple => "\x1b[95m",
        .Gray => "\x1b[90m",
        .GrayBG => "\x1b[48;5;240m",
        .WhiteBG => "\x1b[48;5;15m",
        .Black => "\x1b[30m",
        // VScode inspired
        .Green => "\x1B[38;2;181;206;168m",
        .Cyan => "\x1B[38;2;173;226;242m",
        .DarkGreen => "\x1B[38;5;28m",
        .DarkGreenL => "\x1B[38;2;75;196;176m",
        .DarkOrange => "\x1B[38;5;208m",
        .Yellow => "\x1B[38;5;226m",
        .LightGreen => "\x1b[32m",
        // General Purpose
        .Reset => "\x1b[0m",
        .HideCursor => "\x1b[?25l",
        .ShowCursor => "\x1b[?25h",
        .ClearScreen => "\x1b[2J",
        .ResetCursor => "\x1b[H",
    };
}
