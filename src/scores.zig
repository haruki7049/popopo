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
    pub const Hit = meters.Layer(.{
        .timing = primitives.Timing,
        .volume = primitives.Volume,
    });
};

pub const Scores = struct {
    const Self = @This();

    pub const Guitar = struct {
        /// The root string of each guitar.
        root: lines.Guitar,
    };

    pub const Drum = struct {
        /// kick drum
        kick: lines.Hit,

        /// snare drum
        snare: lines.Hit,
    };

    guitar: Self.Guitar,
    drum: Self.Drum,
};

pub fn compose(allocator: std.mem.Allocator) !Scores {
    return .{
        .guitar = try guitar(allocator),
        .drum = try drum(allocator),
    };
}

fn guitar(allocator: std.mem.Allocator) !Scores.Guitar {
    const root = try sheets.SingleSound.repeat(allocator, 2);

    return .{ .root = root };
}

fn drum(allocator: std.mem.Allocator) !Scores.Drum {
    const kick = try sheets.Drums.EightBeat.Kicks.repeat(allocator, 4);
    const snare = try sheets.Drums.EightBeat.Snares.repeat(allocator, 4);

    return .{
        .kick = kick,
        .snare = snare,
    };
}

test {
    std.testing.refAllDecls(@This());
}
