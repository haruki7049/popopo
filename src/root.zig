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

fn render(allocator: std.mem.Allocator) ![]configs.T {
    const written: scores.Scores = try scores.compose(allocator);

    var mixer: mix.Mixer(configs.T) = try .init(allocator, configs.CHANNELS);
    defer mixer.deinit();

    try play(scores.lines.Guitar, allocator, written.base.root, instruments.guitar, mixer.bus(.{ .gain = 0.2 }));
    try play(scores.lines.Hit, allocator, written.drum.kick, instruments.kick, mixer.bus(.{ .gain = 1.0 }));
    try play(scores.lines.Hit, allocator, written.drum.snare, instruments.snare, mixer.bus(.{ .gain = 0.25 }));

    // The piece lasts as long as its timeline; a ringing crash may run past it.
    const end = try max(scores.Scores, written, context);
    const samples = try mixer.finish(end);
    mix.normalize(configs.T, samples, configs.PEAK);
    return samples;
}

fn max(comptime S: type, written: S, ctx: meters.Context) !primitives.Timing.ResolveT {
    // f64 is the meters.Layer(...).extent type
    const ExtentT = f64;
    var maxExtent: ExtentT = written.base.root.extent;

    inline for (@typeInfo(S).@"struct".fields) |group| {
        inline for (@typeInfo(group.type).@"struct".fields) |part| {
            const extent: ExtentT = @field(@field(@field(written, group.name), part.name), "extent");

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
