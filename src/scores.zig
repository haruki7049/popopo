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
        .b => b(allocator),
    };
}

fn b(allocator: std.mem.Allocator) ![]const Section {
    const b_sheet = sheets.b.Gen(lines);
    const basics_sheets = sheets.basics.Gen(lines);

    const kick_with_rests = try basics_sheets.Drum.EightBeat0.KicksWithRests.repeat(allocator, 2);
    const snare = try basics_sheets.Drum.EightBeat0.Snares.repeat(allocator, 4);
    const base_root = try b_sheet.Base.WithoutThird.repeat(allocator, 4);
    const melody_root = try b_sheet.Melody.MainPhrase.repeat(allocator, 1);
    const melody_root_to_next = try b_sheet.Melody.ToNext.repeat(allocator, 1);

    const kick_to_next = try b_sheet.Drum.EightBeat1.Kicks.repeat(allocator, 4);

    return allocator.dupe(Section, &.{
        .{ .extent = 16.0, .drum = .{ .kick = kick_with_rests, .snare = snare }, .base = .{ .root = base_root }, .melody = .{ .root = melody_root } },
        .{ .extent = 16.0, .drum = .{ .kick = kick_to_next, .snare = snare }, .base = .{ .root = base_root }, .melody = .{ .root = melody_root_to_next } },
    });
}

fn a(allocator: std.mem.Allocator) ![]const Section {
    const a_sheet = sheets.a.Gen(lines);
    const basics_sheets = sheets.basics.Gen(lines);

    const kick_with_rests = try basics_sheets.Drum.EightBeat0.KicksWithRests.repeat(allocator, 2);
    const one_kick = basics_sheets.Drum.EightBeat0.Kicks;
    const one_snare = basics_sheets.Drum.EightBeat0.Snares;
    const snare = try basics_sheets.Drum.EightBeat0.Snares.repeat(allocator, 4);
    const base_root = try basics_sheets.Base.WithoutThird.repeat(allocator, 4);
    const melody_root = try a_sheet.Melody.MainPhrase.repeat(allocator, 1);

    const kick_last = basics_sheets.Drum.EightBeat0.KicksWithRests;
    const snare_last = try basics_sheets.Drum.EightBeat0.Snares.repeat(allocator, 2);
    const base_root_last = try basics_sheets.Base.WithoutThird.repeat(allocator, 2);
    const melody_root_to_next = a_sheet.Melody.ToNext;

    return allocator.dupe(Section, &.{
        .{ .extent = 16.0, .drum = .{ .kick = kick_with_rests, .snare = snare }, .base = .{ .root = base_root }, .melody = .{ .root = melody_root } },
        .{ .extent = 16.0, .drum = .{ .kick = kick_with_rests, .snare = snare }, .base = .{ .root = base_root }, .melody = .{ .root = melody_root } },
        .{ .extent = 8.0, .drum = .{ .kick = kick_last, .snare = snare_last }, .base = .{ .root = base_root_last }, .melody = .{ .root = melody_root_to_next } },
        .{ .extent = 4.0, .drum = .{ .kick = one_kick } },
        .{ .extent = 4.0, .drum = .{ .snare = one_snare } },
    });
}

fn introduction(allocator: std.mem.Allocator) ![]const Section {
    const intro_sheets = sheets.introduction.Gen(lines);
    const basics_sheets = sheets.basics.Gen(lines);

    const kick_with_rests = try basics_sheets.Drum.EightBeat0.KicksWithRests.repeat(allocator, 2);
    const snare = try basics_sheets.Drum.EightBeat0.Snares.repeat(allocator, 4);
    const base_root = try basics_sheets.Base.WithoutThird.repeat(allocator, 4);
    const melody_root = try intro_sheets.Melody.TooooToTo.repeat(allocator, 2);

    const one_kick = try basics_sheets.Drum.EightBeat0.KicksWithRests.repeat(allocator, 1);
    const one_snare = try basics_sheets.Drum.EightBeat0.Snares.repeat(allocator, 2);

    return allocator.dupe(Section, &.{
        .{ .extent = 16.0, .drum = .{ .kick = kick_with_rests } },
        .{ .extent = 16.0, .drum = .{ .kick = kick_with_rests, .snare = snare } },
        .{ .extent = 16.0, .drum = .{ .kick = kick_with_rests, .snare = snare }, .base = .{ .root = base_root } },
        .{ .extent = 16.0, .drum = .{ .kick = kick_with_rests, .snare = snare }, .base = .{ .root = base_root }, .melody = .{ .root = melody_root } },
        .{ .extent = 8.0, .drum = .{ .kick = one_kick } },
        .{ .extent = 8.0, .drum = .{ .kick = one_kick, .snare = one_snare } },
    });
}

test {
    std.testing.refAllDecls(@This());
}
