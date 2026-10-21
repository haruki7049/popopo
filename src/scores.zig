const std = @import("std");
const sheets = @import("sheets");
const build_options = @import("build_options");

pub const lines = @import("./scores/lines.zig");
pub const Section = @import("./scores/section.zig");
pub const Scores = @import("./scores/scores.zig");

const Part = @TypeOf(build_options.music_part);

/// Composes the music part selected with `-Dmusic-part=<name>`, or every part one after another
/// when none is selected.
pub fn compose(allocator: std.mem.Allocator) !Scores {
    if (!build_options.all_parts)
        return Section.concat(allocator, try sections(allocator, build_options.music_part));

    var all: std.ArrayList(Section) = .empty;
    inline for (@typeInfo(Part).@"enum".fields) |field| {
        const part: Part = @enumFromInt(field.value);
        try all.appendSlice(allocator, try sections(allocator, part));
    }

    return Section.concat(allocator, all.items);
}

fn sections(allocator: std.mem.Allocator, part: Part) ![]const Section {
    return switch (part) {
        .introduction => introduction(allocator),
        .a => a(allocator),
    };
}

fn a(allocator: std.mem.Allocator) ![]const Section {
    const a_sheet = sheets.a.Gen(lines);
    const basics_sheets = sheets.basics.Gen(lines);

    const kick = try basics_sheets.Drum.EightBeat0.Kicks.repeat(allocator, 2);
    const snare = try basics_sheets.Drum.EightBeat0.Snares.repeat(allocator, 2);
    const base_root = try basics_sheets.Base.WithoutThird.repeat(allocator, 4);
    const melody_root = try a_sheet.Melody.MainPhrase.repeat(allocator, 1);

    return allocator.dupe(Section, &.{
        .{ .extent = 16.0, .drum = .{ .kick = kick, .snare = snare }, .base = .{ .root = base_root }, .melody = .{ .root = melody_root } },
    });
}

fn introduction(allocator: std.mem.Allocator) ![]const Section {
    const intro_sheets = sheets.introduction.Gen(lines);
    const basics_sheets = sheets.basics.Gen(lines);

    const kick = try basics_sheets.Drum.EightBeat0.Kicks.repeat(allocator, 2);
    const snare = try basics_sheets.Drum.EightBeat0.Snares.repeat(allocator, 2);
    const base_root = try basics_sheets.Base.WithoutThird.repeat(allocator, 4);
    const melody_root = try intro_sheets.Melody.TooooToTo.repeat(allocator, 2);

    const short_kick = try basics_sheets.Drum.EightBeat0.Kicks.repeat(allocator, 1);
    const short_snare = try basics_sheets.Drum.EightBeat0.Snares.repeat(allocator, 1);

    return allocator.dupe(Section, &.{
        .{ .extent = 16.0, .drum = .{ .kick = kick } },
        .{ .extent = 16.0, .drum = .{ .kick = kick, .snare = snare } },
        .{ .extent = 16.0, .drum = .{ .kick = kick, .snare = snare }, .base = .{ .root = base_root } },
        .{ .extent = 16.0, .drum = .{ .kick = kick, .snare = snare }, .base = .{ .root = base_root }, .melody = .{ .root = melody_root } },
        .{ .extent = 8.0, .drum = .{ .kick = short_kick } },
        .{ .extent = 8.0, .drum = .{ .kick = short_kick, .snare = short_snare } },
    });
}

test {
    std.testing.refAllDecls(@This());
}
