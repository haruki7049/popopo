const std = @import("std");
const meters = @import("meters");
const configs = @import("./configs.zig");
const primitives = @import("./primitives.zig");

const lists = struct {
    /// A list of pitches.
    const Pitches = meters.Layer(.{ .pitch = primitives.Pitch });
};

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

const c3 = lists.Pitches.notate(&.{.{ .name = .{ .code = .c, .octave = 3 } }});

pub const Scores = struct {
    /// The root string of each guitar.
    guitar_root: lines.Guitar,
};

const zons = struct {
    const SingleSound: lines.Guitar = @import("./scores/single-sound.zon");
};

pub fn compose(
    // allocator: std.mem.Allocator,
) !Scores {
    return .{
        .guitar_root = zons.SingleSound,
    };
}

test {
    std.testing.refAllDecls(@This());
}
