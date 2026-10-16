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

    /// Score of a drum: kick, snare or crash.
    pub const Hits = meters.Layer(.{
        .timing = primitives.Timing,
        .duration = primitives.Duration,
        .volume = primitives.Volume,
    });
};

pub const Scores = struct {
    const Self = @This();

    pub const Guitar = struct {
        /// The root string of each guitar.
        root: lines.Guitar,
    };

    guitar: Self.Guitar,
};

pub fn compose(allocator: std.mem.Allocator) !Scores {
    const twice = try sheets.SingleSound.concat(allocator, sheets.SingleSound);

    return .{
        .guitar = .{
            .root = twice,
        },
    };
}

test {
    std.testing.refAllDecls(@This());
}
