const std = @import("std");
const lightmix = @import("lightmix");
const meters = @import("meters");
const mix = @import("mix");
const perform = @import("perform");

const configs = @import("./configs.zig");
const instruments = @import("./instruments.zig");
const primitives = @import("./primitives.zig");
const scores = @import("./scores.zig");

/// Tempo, meter and sample rate every primitive resolves against.
const context: meters.Context = .{
    .bpm = configs.BPM,
    .sample_rate = configs.SAMPLE_RATE,
    .time_signature = .{
        .numerator = configs.BEATS_PER_BAR,
        .denominator = configs.BEAT_VALUE,
    },
};

pub fn gen(init: std.process.Init) !lightmix.Wave(configs.T) {
    const allocator = init.arena.allocator();
    const samples: []configs.T = try render(allocator);

    return lightmix.Wave(configs.T){
        .samples = samples,
        .allocator = allocator,
        .sample_rate = configs.SAMPLE_RATE,
        .channels = configs.CHANNELS,
    };
}

/// Level of the hi-hat bus; the hi-hat sits behind the kick and the snare.
const HIHAT_GAIN: configs.T = 0.15;

/// Level of the synthesizer bus; a provisional value to be set by ear.
const STAB_GAIN: configs.T = 0.3;

fn render(allocator: std.mem.Allocator) ![]configs.T {
    const written: scores.Scores = try scores.compose(allocator);

    var mixer: mix.Mixer(configs.T) = try .init(allocator, configs.CHANNELS);
    defer mixer.deinit();

    try play(scores.lines.Hit, allocator, written.drum.kick, instruments.kick, mixer.bus(.{ .gain = 1.0 }));
    try play(scores.lines.Hit, allocator, written.drum.snare, instruments.snare, mixer.bus(.{ .gain = 0.75 }));
    try play(scores.lines.Hit, allocator, written.drum.hihat, instruments.hihat, mixer.bus(.{ .gain = HIHAT_GAIN }));
    try play(scores.lines.Stab, allocator, written.synth.stab, instruments.stab, mixer.bus(.{ .gain = STAB_GAIN }));

    // The piece lasts as long as its timeline; a ringing crash may run past it.
    const end = try max(scores.Scores, written, context);
    const samples = try mixer.finish(end);
    mix.normalize(configs.T, samples, configs.PEAK);
    return samples;
}

fn max(comptime S: type, written: S, ctx: meters.Context) !primitives.Timing.ResolveT {
    // f64 is the meters.Layer(...).extent type
    const ExtentT = f64;
    var maxExtent: ExtentT = 0.0;

    inline for (@typeInfo(S).@"struct".field_names, @typeInfo(S).@"struct".field_types) |group_name, Group| {
        inline for (@typeInfo(Group).@"struct".field_names, @typeInfo(Group).@"struct".field_types) |part_name, _| {
            const extent: ExtentT = @field(@field(@field(written, group_name), part_name), "extent");

            if (maxExtent < extent)
                maxExtent = extent;
        }
    }

    const timing: primitives.Timing = .{ .beat = maxExtent };
    return try timing.resolve(ctx);
}

/// Resolves the score of one vibrating body and runs the procedure on it into `bus`.
fn play(
    comptime L: type,
    allocator: std.mem.Allocator,
    layer: L,
    instrument: instruments.Procedure(L.Resolved).Body,
    bus: mix.Mixer(configs.T).Bus,
) !void {
    const notes = try layer.resolve(allocator, context);
    try instruments.Procedure(L.Resolved).run(allocator, instrument, notes, configs.SAMPLE_RATE, bus);
}

test "max private function must return max extent value from scores.Scores" {
    const ctx: meters.Context = .{
        .bpm = 135,
        .sample_rate = 44100,
        .time_signature = .{ .denominator = 4, .numerator = 4 },
    };
    const ExtentT = f64;
    const FakeScores = struct {
        const Base = struct {
            const Root = struct {
                extent: ExtentT,
            };

            root: Root,
        };

        const Drum = struct {
            const Kick = struct {
                extent: ExtentT,
            };

            kick: Kick,
        };

        base: Base,
        drum: Drum,
    };
    const fs: FakeScores = .{
        .base = .{ .root = .{ .extent = 1.0 } },
        .drum = .{ .kick = .{ .extent = 3.0 } },
    };

    const expected: primitives.Timing.ResolveT = 58800;
    const actual: primitives.Timing.ResolveT = try max(FakeScores, fs, ctx);

    try std.testing.expectEqual(expected, actual);
}

test {
    std.testing.refAllDecls(@This());
}
