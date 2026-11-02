//! One section of the piece: how long it lasts and what each vibrating body plays in it.
//! A body left `null` is silent for the whole section.

const std = @import("std");
const lines = @import("./lines.zig");
const Scores = @import("./scores.zig");

const Section = @This();

pub const Guitar = struct {
    root: ?lines.String = null,
};

pub const Drum = struct {
    kick: ?lines.Hit = null,
    snare: ?lines.Hit = null,
};

/// Length of this section in beats; every part written in it must last exactly this long.
extent: f64,

base: Guitar = .{},
melody: Guitar = .{},
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

test {
    std.testing.refAllDecls(@This());
}
