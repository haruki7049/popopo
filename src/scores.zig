const std = @import("std");
const meters = @import("meters");
const configs = @import("./configs.zig");
const primitives = @import("./primitives.zig");
const sheets = @import("./sheets.zig").Gen(lines);

pub const lines = struct {
    /// Score of one guitar string.
    pub const Guitar = meters.Layer(.{
        .duration = primitives.Duration,
        .mute = primitives.Mute,
        .pitch = primitives.Pitch,
        .timing = primitives.Timing,
        .volume = primitives.Volume,
    });
};

pub const Scores = struct {
    /// The root string of each guitar.
    guitar_root: lines.Guitar,
};

pub fn compose(
    // allocator: std.mem.Allocator,
) !Scores {
    return .{
        .guitar_root = sheets.SingleSound,
    };
}

test {
    std.testing.refAllDecls(@This());
}
