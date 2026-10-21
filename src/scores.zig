const std = @import("std");
const sheets = @import("sheets");

pub const lines = @import("./scores/lines.zig");
pub const Section = @import("./scores/section.zig");
pub const Scores = @import("./scores/scores.zig");

pub fn compose(allocator: std.mem.Allocator) !Scores {
    const introduction = sheets.introduction.Gen(lines);

    const kick = try introduction.Drums.EightBeat0.Kicks.repeat(allocator, 2);
    const snare = try introduction.Drums.EightBeat0.Snares.repeat(allocator, 2);
    const base_root = try introduction.Base.WithoutThird.repeat(allocator, 4);

    return Section.concat(allocator, &.{
        .{ .extent = 16.0, .drum = .{ .kick = kick } },
        .{ .extent = 16.0, .drum = .{ .kick = kick, .snare = snare } },
        .{ .extent = 16.0, .drum = .{ .kick = kick, .snare = snare }, .base = .{ .root = base_root } },
    });
}

test {
    std.testing.refAllDecls(@This());
}
