const std = @import("std");
const Style = @import("styles.zig");

pub const Value = struct {
    scrolling: enum {
        Line,
        Tab,
    } = .Line,
    //begin_scroll: enum {
    //    Middle,
    //    MiddleEnd,
    //    End,
    //} = .MiddleEnd,
};

pub const custom_path_env = "ZENITH_CONFIG_PATH";
pub const parse_default_result = std.json.Parsed(Value);
/// Caller frees the memory
/// If {custom_path_env} env variable exists, it will not try to create the file.
/// Reverts to path.join(env("HOME"), ".zenith.json")
pub fn parseDefault(allocator: std.mem.Allocator) !parse_default_result {
    var custom_path: bool = true;

    const home_json = std.process.getEnvVarOwned(allocator, custom_path_env) catch |e| brk: {
        custom_path = false;

        switch (e) {
            std.process.GetEnvVarOwnedError.EnvironmentVariableNotFound => {
                break :brk try std.fs.path.join(allocator, &.{
                    std.posix.getenv("HOME") orelse return error.HomeEnvNotFound,
                    ".zenith.json",
                });
            },
            else => return e,
        }
    };
    defer allocator.free(home_json);

    var just_created: bool = false;
    const config_file = std.fs.openFileAbsolute(home_json, .{}) catch |e| brk: {
        if (e != std.fs.File.OpenError.FileNotFound)
            return e;

        if (custom_path)
            return error.CustomConfigFileCouldNotBeOpened;

        const f = try std.fs.createFileAbsolute(home_json, .{
            .read = true,
            .exclusive = true,
        });

        just_created = true;
        try f.writer().writeAll("{}");
        break :brk f;
    };
    defer config_file.close();

    const content = if (just_created) "{}" else try config_file.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer if (!just_created) allocator.free(content);

    return try std.json.parseFromSlice(Value, allocator, content, .{});
}
