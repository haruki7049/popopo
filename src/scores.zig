const std = @import("std");
const sheets = @import("./sheets.zig").Gen(lines);

pub const lines = @import("./scores/lines.zig");
pub const Section = @import("./scores/section.zig");
pub const Scores = @import("./scores/scores.zig");

pub fn compose(allocator: std.mem.Allocator) !Scores {
    const kick = try sheets.Drums.EightBeat0.Kicks.repeat(allocator, 2);
    const snare = try sheets.Drums.EightBeat0.Snares.repeat(allocator, 2);

    return Section.concat(allocator, &.{
        .{ .extent = 16.0, .drum = .{ .kick = kick } },
        .{ .extent = 16.0, .drum = .{ .kick = kick, .snare = snare } },
    });
}

test {
    std.testing.refAllDecls(@This());
}
