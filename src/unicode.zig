const std = @import("std");
const globals = @import("globals.zig");

const decode_error =
    anyerror; // std.unicode.utf8Encode
pub inline fn decode(c: globals.Char) decode_error![]const u8 {
    var buf: [8]u8 = undefined;
    const read = try std.unicode.utf8Encode(c, &buf);
    return buf[0..read];
}

const to_utf8_alloc_error =
    std.mem.Allocator.Error // ArrayListUnmanaged.appendSlice, ArrayListUnmanaged.toOwnedSlice
|| decode_error; // decode
pub fn toUtf8Alloc(allocator: std.mem.Allocator, query: []const globals.Char) to_utf8_alloc_error![]u8 {
    var line = std.ArrayListUnmanaged(u8){};
    defer line.deinit(allocator);

    for (query) |unicode_char| {
        try line.appendSlice(allocator, try decode(unicode_char));
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

pub fn toSplittedUtf8(
    allocator: std.mem.Allocator,
    input: []const u8,
) !std.ArrayList([]const u8) {
    var out = std.ArrayList([]const u8).init(allocator);
    errdefer out.deinit();

    var split = std.mem.splitScalar(u8, input, '\n');

    while (split.next()) |s| {
        try out.append(s);
    }

    return out;
}

// zig fmt: off
const to_unicode_list_error =
    std.mem.Allocator.Error // ArrayListUnmanaged.append
||  anyerror; // std.unicode.Utf8View.init
// zig fmt: on
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

pub fn isDigit(c: globals.Char) bool {
    return switch (c) {
        '0'...'9' => true,
        else => false,
    };
}

pub fn isAlphanumeric(c: globals.Char) bool {
    return switch (c) {
        '0'...'9' => true,
        'a'...'z', 'A'...'Z' => true, // I'm sure there are more since it's unicode, TODO
        else => false,
    };
}
