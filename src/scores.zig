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
    inline for (std.enums.values(Part)) |part| {
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
    const s = sheets.Gen(lines);

    // One bar of each, pairing its timings with the one shared volume.
    const kick_bar: lines.Hit = try s.Timing.Half.zip(allocator, s.Volume.Default);
    const snare_bar: lines.Hit = try s.Timing.Backbeat.zip(allocator, s.Volume.Default);
    const double_speed_four_fourth: lines.Timing = try lines.speed(allocator, s.Timing.FourFourth, 2.0);
    const four_eighth: lines.Timing = try double_speed_four_fourth.repeat(allocator, 2);
    const hihat_bar: lines.Hit = try four_eighth.zip(allocator, s.Volume.Default);

    return .{
        .kick = try kick_bar.repeat(allocator, bars),
        .snare = try snare_bar.repeat(allocator, bars),
        .hihat = try hihat_bar.repeat(allocator, bars),
    };
}

const FourOnTheFlour = struct {
    kick: lines.Hit,
    snare: lines.Hit,
    hihat: lines.Hit,
};

fn fourOnTheFlour(allocator: std.mem.Allocator, bars: usize) !FourOnTheFlour {
    const s = sheets.Gen(lines);

    // One bar of each, pairing its timings with the one shared volume.
    const kick_bar: lines.Hit = try s.Timing.FourFourth.zip(allocator, s.Volume.Default);
    const snare_bar: lines.Hit = try s.Timing.Backbeat.zip(allocator, s.Volume.Default);
    const fourth_speed_four_gallop: lines.Timing = try lines.speed(allocator, s.Timing.Gallop, 4.0);
    const four_gallop: lines.Timing = try fourth_speed_four_gallop.repeat(allocator, 4);
    const hihat_bar: lines.Hit = try four_gallop.zip(allocator, s.Volume.Default);

    return .{
        .kick = try kick_bar.repeat(allocator, bars),
        .snare = try snare_bar.repeat(allocator, bars),
        .hihat = try hihat_bar.repeat(allocator, bars),
    };
}

const FourOnTheFlourOut1 = struct {
    kick: lines.Hit,
    snare: lines.Hit,
    hihat: lines.Hit,
};

fn fourOnTheFlourOut1(allocator: std.mem.Allocator, bars: usize) !FourOnTheFlourOut1 {
    const s = sheets.Gen(lines);

    // One bar of each, pairing its timings with the one shared volume.
    const kick_bar: lines.Hit = try s.Timing.FourFourth.zip(allocator, s.Volume.Default);
    const fourth_speed_four_gallop: lines.Timing = try lines.speed(allocator, s.Timing.Gallop, 4.0);
    const fourth_speed_third_fourth: lines.Timing = try lines.speed(allocator, s.Timing.ThirdFourth, 4.0);

    const three_gallop: lines.Timing = try fourth_speed_four_gallop.repeat(allocator, 3);
    const four_gallop: lines.Timing = try fourth_speed_four_gallop.repeat(allocator, 4);
    const snare_gallop: lines.Timing = try fourth_speed_third_fourth.concat(allocator, three_gallop);

    const snare_bar: lines.Hit = try snare_gallop.zip(allocator, s.Volume.Default);
    const hihat_bar: lines.Hit = try four_gallop.zip(allocator, s.Volume.Default);

    return .{
        .kick = try kick_bar.repeat(allocator, bars),
        .snare = try snare_bar.repeat(allocator, bars),
        .hihat = try hihat_bar.repeat(allocator, bars),
    };
}

/// Seven bars of an eight beat, followed by a one bar drum fill.
fn introduction(allocator: std.mem.Allocator) ![]const Section {
    const drum = try fourOnTheFlour(allocator, 7);
    const drum_out = try fourOnTheFlourOut1(allocator, 1);

    return allocator.dupe(Section, &.{
        .{
            .extent = drum.kick.extent,
            .drum = .{
                .kick = drum.kick,
                .snare = drum.snare,
                .hihat = drum.hihat,
            },
        },
        .{
            .extent = drum_out.kick.extent,
            .drum = .{
                .kick = drum_out.kick,
                .snare = drum_out.snare,
                .hihat = drum_out.hihat,
            },
        },
    });
}

test {
    std.testing.refAllDecls(@This());
}
