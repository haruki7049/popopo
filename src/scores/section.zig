//! One section of the piece: how long it lasts and what each vibrating body plays in it.
//! A body left `null` is silent for the whole section.

const std = @import("std");
const lines = @import("./lines.zig");
const Scores = @import("./scores.zig");

const Section = @This();

pub const Drum = struct {
    kick: ?lines.Hit = null,
    snare: ?lines.Hit = null,
    hihat: ?lines.Hit = null,
};

pub const Synth = struct {
    stab: ?lines.Stab = null,
};

/// Length of this section in beats; every part written in it must last exactly this long.
extent: f64,

drum: Drum = .{},

synth: Synth = .{},

/// Places `sections` one after another and gives the score of each vibrating body.
/// Returns `error.MismatchedExtent` when a part does not last as long as its section.
pub fn concat(allocator: std.mem.Allocator, sections: []const Section) !Scores {
    var result: Scores = undefined;

    // Walks Scores.<group>.<part>, so Section must have the same names as Scores.
    inline for (@typeInfo(Scores).@"struct".field_names, @typeInfo(Scores).@"struct".field_types) |group_name, Group| {
        inline for (@typeInfo(Group).@"struct".field_names, @typeInfo(Group).@"struct".field_types) |part_name, L| {
            const parts = try allocator.alloc(L, sections.len);
            for (sections, parts) |section, *slot| {
                const written = @field(@field(section, group_name), part_name);
                slot.* = written orelse L.empty(section.extent);
                if (slot.extent != section.extent) return error.MismatchedExtent;
            }
            @field(@field(result, group_name), part_name) = try L.join(allocator, parts);
        }
    }

    return result;
}

test {
    std.testing.refAllDecls(@This());
}
