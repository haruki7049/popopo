const std = @import("std");
const meters = @import("meters");
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

/// Writes `bars` bars of the synthesizer stabbing `chord` on the offbeat of every beat. `chord` is
/// one chord that is not placed in time, which is broadcast over every stab.
fn offbeatStab(allocator: std.mem.Allocator, bars: usize, chord: lines.Chord) !lines.Stab {
    const s = sheets.Gen(lines);

    // The backbeat at double speed lasts two beats and sounds at 0.5 and 1.5; twice of it fills a
    // bar with 0.5, 1.5, 2.5 and 3.5.
    const double_speed_backbeat: lines.Timing = try lines.speed(allocator, s.Timing.Backbeat, 2.0);
    const offbeat: lines.Timing = try double_speed_backbeat.repeat(allocator, 2);

    // One bar, pairing its timings with the one shared volume and the one shared chord.
    const hit_bar: lines.Hit = try offbeat.zip(allocator, s.Volume.Default);
    const stab_bar: lines.Stab = try hit_bar.zip(allocator, chord);

    return stab_bar.repeat(allocator, bars);
}

/// The snare of seven bars of four on the floor: the backbeat, with one more snare on the offbeat
/// of the third beat of the fourth bar.
fn introductionSnare(allocator: std.mem.Allocator) !lines.Hit {
    const s = sheets.Gen(lines);

    const snare_bar: lines.Hit = try s.Timing.Backbeat.zip(allocator, s.Volume.Default);

    // The backbeat, and the extra snare at 2.5 beats from the start of the bar.
    const extra_timing: lines.Timing = .{
        .columns = .{ .timing = &.{
            .{ .bar = 0, .beat = 1.0 },
            .{ .bar = 0, .beat = 2.5 },
            .{ .bar = 0, .beat = 3.0 },
        } },
        .extent = 4.0,
    };
    const extra_bar: lines.Hit = try extra_timing.zip(allocator, s.Volume.Default);

    return lines.Hit.join(allocator, &.{
        try snare_bar.repeat(allocator, 3),
        extra_bar,
        try snare_bar.repeat(allocator, 3),
    });
}

/// Seven bars of four on the floor, followed by a one bar drum fill, with the synthesizer stabbing
/// the offbeat all along.
fn introduction(allocator: std.mem.Allocator) ![]const Section {
    const s = sheets.Gen(lines);

    const drum = try fourOnTheFlour(allocator, 7);
    const snare = try introductionSnare(allocator);
    const drum_out = try fourOnTheFlourOut1(allocator, 1);

    return allocator.dupe(Section, &.{
        .{
            .extent = drum.kick.extent,
            .drum = .{
                .kick = drum.kick,
                .snare = snare,
                .hihat = drum.hihat,
            },
            .synth = .{
                .stab = try offbeatStab(allocator, 7, s.Chord.A3C4E4),
            },
        },
        .{
            .extent = drum_out.kick.extent,
            .drum = .{
                .kick = drum_out.kick,
                .snare = drum_out.snare,
                .hihat = drum_out.hihat,
            },
            .synth = .{
                .stab = try offbeatStab(allocator, 1, s.Chord.A3C4E4),
            },
        },
    });
}

test "the snare of the introduction has one more hit on the offbeat of the third beat of the fourth bar" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // 120 BPM, 44100 Hz: a beat is 22050 frames.
    const ctx: meters.Context = .{ .bpm = 120, .sample_rate = 44100 };
    const snare = try introductionSnare(allocator);
    try std.testing.expectEqual(@as(f64, 28.0), snare.extent);

    const notes = try snare.resolve(allocator, ctx);
    // Two hits in each of the six other bars, and three in the fourth.
    try std.testing.expectEqual(@as(usize, 15), notes.len);

    // The fourth bar starts at beat 12: its hits are at beats 13, 14.5 and 15.
    const frames = [_]usize{ 13 * 22050, 29 * 11025, 15 * 22050 };
    for (notes[6..9], frames) |note, frame| try std.testing.expectEqual(frame, note.timing);
}

test {
    std.testing.refAllDecls(@This());
}
