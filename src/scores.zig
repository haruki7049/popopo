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
    };
}

/// The drum parts of an eight beat.
const EightBeat = struct {
    kick: lines.Hit,
    snare: lines.Hit,
    hihat: lines.Hit,
};

/// Writes `bars` bars of an eight beat: the kick sounds on the first and third beats, the snare on
/// the second and fourth beats, and the closed hi-hat on every eighth note. All parts last `bars`
/// bars, so `kick.extent` is the length of the section they are written in.
fn eightBeat(allocator: std.mem.Allocator, bars: usize) !EightBeat {
    const basics = sheets.basics.Gen(lines);

    // One bar of each, pairing its timings with the one shared volume.
    const kick_bar = try basics.Timing.Half.zip(allocator, basics.Volume.Default);
    const snare_bar = try basics.Timing.Backbeat.zip(allocator, basics.Volume.Default);
    const hihat_bar = try basics.Timing.Eighth.zip(allocator, basics.Volume.Default);

    return .{
        .kick = try kick_bar.repeat(allocator, bars),
        .snare = try snare_bar.repeat(allocator, bars),
        .hihat = try hihat_bar.repeat(allocator, bars),
    };
}

const EightBeatWithoutHiHat = struct {
    kick: lines.Hit,
    snare: lines.Hit,
};

fn eightBeatWithoutHiHat(allocator: std.mem.Allocator, bars: usize) !EightBeatWithoutHiHat {
    const basics = sheets.basics.Gen(lines);

    // One bar of each, pairing its timings with the one shared volume.
    const kick_bar = try basics.Timing.Gallop.zip(allocator, basics.Volume.Default);
    const snare_bar = try basics.Timing.Backbeat.zip(allocator, basics.Volume.Default);

    return .{
        .kick = try kick_bar.repeat(allocator, bars),
        .snare = try snare_bar.repeat(allocator, bars),
    };
}

/// Four bars of an eight beat.
fn introduction(allocator: std.mem.Allocator) ![]const Section {
    const drumFirst = try eightBeatWithoutHiHat(allocator, 2);
    const drumSecond = try eightBeat(allocator, 2);

    return allocator.dupe(Section, &.{
        .{
            .extent = drumFirst.kick.extent,
            .drum = .{ .kick = drumFirst.kick, .snare = drumFirst.snare },
        },
        .{
            .extent = drumSecond.kick.extent,
            .drum = .{ .kick = drumSecond.kick, .snare = drumSecond.snare, .hihat = drumSecond.hihat },
        },
    });
}

test {
    std.testing.refAllDecls(@This());
}
