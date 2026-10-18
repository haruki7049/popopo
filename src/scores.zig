const std = @import("std");
const sheets = @import("./sheets.zig").Gen(lines);

pub const lines = @import("./scores/lines.zig");
pub const Section = @import("./scores/section.zig");
pub const Scores = @import("./scores/scores.zig");

pub fn compose(allocator: std.mem.Allocator) !Scores {
    const guitar = try sheets.SingleSound.repeat(allocator, 2);
    const kick = try sheets.Drums.EightBeat.Kicks.repeat(allocator, 4);
    const snare = try sheets.Drums.EightBeat.Snares.repeat(allocator, 4);

    return Section.concat(allocator, &.{
        .{ .extent = 16.0, .guitar = .{ .root = guitar } },
        .{ .extent = 16.0, .guitar = .{ .root = guitar }, .drum = .{ .kick = kick, .snare = snare } },
    });
}

test {
    std.testing.refAllDecls(@This());
}
