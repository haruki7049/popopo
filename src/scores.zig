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

/// One section of the piece: how long it lasts and what each vibrating body plays in it.
/// A body left `null` is silent for the whole section.
pub const Section = struct {
    pub const Guitar = struct {
        root: ?lines.Guitar = null,
    };

    pub const Drum = struct {
        kick: ?lines.Hit = null,
        snare: ?lines.Hit = null,
    };

    /// Length of this section in beats; every part written in it must last exactly this long.
    extent: f64,

    guitar: Guitar = .{},
    drum: Drum = .{},

    /// Places `sections` one after another and gives the score of each vibrating body.
    /// Returns `error.MismatchedExtent` when a part does not last as long as its section.
    pub fn concat(allocator: std.mem.Allocator, sections: []const Section) !Scores {
        var result: Scores = undefined;

        // Walks Scores.<group>.<part>, so Section must have the same names as Scores.
        inline for (@typeInfo(Scores).@"struct".fields) |group| {
            inline for (@typeInfo(group.type).@"struct".fields) |part| {
                const L = part.type;
                const parts = try allocator.alloc(L, sections.len);
                for (sections, parts) |section, *slot| {
                    const written = @field(@field(section, group.name), part.name);
                    slot.* = written orelse L.empty(section.extent);
                    if (slot.extent != section.extent) return error.MismatchedExtent;
                }
                @field(@field(result, group.name), part.name) = try L.join(allocator, parts);
            }
        }

        return result;
    }
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
    const solo = try sheets.SingleSound.repeat(allocator, 2);
    const band = try sheets.SingleSound.repeat(allocator, 2);
    const kick = try sheets.Drums.EightBeat.Kicks.repeat(allocator, 4);
    const snare = try sheets.Drums.EightBeat.Snares.repeat(allocator, 4);

    return Section.concat(allocator, &.{
        .{ .extent = 16.0, .guitar = .{ .root = solo } },
        .{ .extent = 16.0, .guitar = .{ .root = band }, .drum = .{ .kick = kick, .snare = snare } },
    });
}

test {
    std.testing.refAllDecls(@This());
}
