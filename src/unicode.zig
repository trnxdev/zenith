const std = @import("std");
const globals = @import("globals.zig");
const err_assert = globals.err_assert;

pub const encode_error =
    anyerror; // std.unicode.utf8Encode
pub inline fn encode(c: globals.Char) encode_error![]const u8 {
    var buf: [8]u8 = undefined;
    const read = try std.unicode.utf8Encode(c, &buf);
    return buf[0..read];
}

pub const to_utf8_alloc_error =
    std.mem.Allocator.Error // ArrayListUnmanaged.appendSlice, ArrayListUnmanaged.toOwnedSlice
|| encode_error; // decode
pub fn toUtf8Alloc(allocator: std.mem.Allocator, query: []const globals.Char) to_utf8_alloc_error![]u8 {
    var line = std.ArrayListUnmanaged(u8){};
    defer line.deinit(allocator);

    for (query) |unicode_char| {
        try line.appendSlice(allocator, try encode(unicode_char));
    }

    return try line.toOwnedSlice(allocator);
}

const to_unicode_alloc_error =
    std.mem.Allocator.Error // ArrayListUnmanaged.append
|| to_unicode_list_error; // toUnicodeList
pub fn toUnicodeAlloc(
    allocator: std.mem.Allocator,
    query: []const u8,
) to_unicode_alloc_error![]globals.Char {
    var list = try toUnicodeList(allocator, query);
    defer list.deinit(allocator);

    return try list.toOwnedSlice(allocator);
}

const to_splitted_unicode_error =
    to_unicode_alloc_error; // toUnicodeAlloc
pub fn toSplittedUnicode(
    allocator: std.mem.Allocator,
    input: []u8,
) to_splitted_unicode_error!std.ArrayList([]globals.Char) {
    var out = std.ArrayList([]globals.Char).init(allocator);
    errdefer out.deinit();

    var split = std.mem.splitScalar(u8, input, '\n');

    while (split.next()) |s| {
        try out.append(try toUnicodeAlloc(allocator, s));
    }

    return out;
}

const to_splitted_utf8_error =
    std.mem.Allocator.Error; // ArrayList.append
pub fn toSplittedUtf8(
    allocator: std.mem.Allocator,
    input: []const u8,
) to_splitted_utf8_error!std.ArrayList([]const u8) {
    var out = std.ArrayList([]const u8).init(allocator);
    errdefer out.deinit();

    var split = std.mem.splitScalar(u8, input, '\n');

    while (split.next()) |s| {
        try out.append(s);
    }

    return out;
}

const to_unicode_list_error =
    std.mem.Allocator.Error // ArrayListUnmanaged.append
|| anyerror; // std.unicode.Utf8View.init
pub fn toUnicodeList(
    allocator: std.mem.Allocator,
    query: []const u8,
) to_unicode_list_error!globals.Line {
    var line = globals.Line{};
    errdefer line.deinit(allocator);

    const view = try std.unicode.Utf8View.init(query);
    var iter = view.iterator();

    while (iter.nextCodepoint()) |unicode_char| {
        try line.append(allocator, unicode_char);
    }

    return line;
}

pub inline fn isDigit(c: globals.Char) bool {
    return switch (c) {
        inline '0'...'9' => true,
        else => false,
    };
}

// I know I can use ranges (like 'a'...'z', 'A'...'Z') but I don't feel like it
// zig fmt: off
pub inline fn isLetter(c: globals.Char) bool {
    return switch (c) {
        // English, https://en.wikipedia.org/wiki/English_alphabet
        'A', 'a', 'B', 'b', 'C', 'c',
        'D', 'd', 'E', 'e', 'F', 'f',
        'G', 'g', 'H', 'h', 'I', 'i',
        'J', 'j', 'K', 'k', 'L', 'l',
        'M', 'm', 'N', 'n', 'O', 'o',
        'P', 'p', 'Q', 'q', 'R', 'r',
        'S', 's', 'T', 't', 'U', 'u',
        'V', 'v', 'W', 'w', 'X', 'x',
        'Y', 'y', 'Z', 'z' => true,
        // + German, https://en.wikipedia.org/wiki/German_alphabet
        'Ä', 'ä', 'Ö', 'ö', 'Ü', 'ü', 'ß', => true,
        // Cyrillic (Russian), en.wikipedia.org/wiki/Russian_alphabet
        'А', 'а', 'Б', 'б', 'В', 'в',
        'Г', 'г', 'Д', 'д', 'Е', 'е',
        'Ё', 'ё', 'Ж', 'ж', 'З', 'з',
        'И', 'и', 'Й', 'й', 'К', 'к',
        'Л', 'л', 'М', 'м', 'Н', 'н', 
        'О', 'о', 'П', 'п', 'Р', 'р', 
        'С', 'с', 'Т', 'т', 'У', 'у',
        'Ф', 'ф', 'Х', 'х', 'Ц', 'ц',
        'Ч', 'ч', 'Ш', 'ш', 'Щ', 'щ',
        'Ъ', 'ъ', 'Ы', 'ы', 'Ь', 'ь', 
        'Э', 'э', 'Ю', 'ю', 'Я', 'я' => true,
        else => false,
    };
}
// zig fmt: on

pub fn isAlphanumeric(c: globals.Char) bool {
    return isDigit(c) or isLetter(c);
}

pub const decode_error = error{
    Utf8ExpectedContinuation,
    Utf8OverlongEncoding,
    Utf8EncodesSurrogateHalf,
    Utf8CodepointTooLarge,
} || globals.assertion_error;

// Copied from `std.unicode`, to remove assert panics
/// Decodes the UTF-8 codepoint encoded in the given slice of bytes.
/// bytes.len must be equal to utf8ByteSequenceLength(bytes[0]) catch unreachable.
/// If you already know the length at comptime, you can call one of
/// utf8Decode2,utf8Decode3,utf8Decode4 directly instead of this function.
pub noinline fn decode(bytes: []const u8) decode_error!u21 {
    return switch (bytes.len) {
        1 => @as(u21, bytes[0]),
        2 => decode2(bytes),
        3 => decode3(bytes),
        4 => decode4(bytes),
        else => unreachable,
    };
}

inline fn decode2(bytes: []const u8) decode_error!u21 {
    try err_assert(bytes.len == 2);
    try err_assert(bytes[0] & 0b11100000 == 0b11000000);
    var value: u21 = bytes[0] & 0b00011111;

    if (bytes[1] & 0b11000000 != 0b10000000) return decode_error.Utf8ExpectedContinuation;
    value <<= 6;
    value |= bytes[1] & 0b00111111;

    if (value < 0x80) return decode_error.Utf8OverlongEncoding;

    return value;
}

inline fn decode3(bytes: []const u8) decode_error!u21 {
    try err_assert(bytes.len == 3);
    try err_assert(bytes[0] & 0b11110000 == 0b11100000);
    var value: u21 = bytes[0] & 0b00001111;

    if (bytes[1] & 0b11000000 != 0b10000000) return decode_error.Utf8ExpectedContinuation;
    value <<= 6;
    value |= bytes[1] & 0b00111111;

    if (bytes[2] & 0b11000000 != 0b10000000) return decode_error.Utf8ExpectedContinuation;
    value <<= 6;
    value |= bytes[2] & 0b00111111;

    if (value < 0x800) return decode_error.Utf8OverlongEncoding;
    if (0xd800 <= value and value <= 0xdfff) return decode_error.Utf8EncodesSurrogateHalf;

    return value;
}

inline fn decode4(bytes: []const u8) decode_error!u21 {
    try err_assert(bytes.len == 4);
    try err_assert(bytes[0] & 0b11111000 == 0b11110000);
    var value: u21 = bytes[0] & 0b00000111;

    if (bytes[1] & 0b11000000 != 0b10000000) return decode_error.Utf8ExpectedContinuation;
    value <<= 6;
    value |= bytes[1] & 0b00111111;

    if (bytes[2] & 0b11000000 != 0b10000000) return decode_error.Utf8ExpectedContinuation;
    value <<= 6;
    value |= bytes[2] & 0b00111111;

    if (bytes[3] & 0b11000000 != 0b10000000) return decode_error.Utf8ExpectedContinuation;
    value <<= 6;
    value |= bytes[3] & 0b00111111;

    if (value < 0x10000) return decode_error.Utf8OverlongEncoding;
    if (value > 0x10FFFF) return decode_error.Utf8CodepointTooLarge;

    return value;
}
