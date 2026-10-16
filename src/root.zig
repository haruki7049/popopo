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

    try play(scores.lines.Guitar, allocator, written.guitar_root, instruments.left_string, mixer.bus(.{}));

    // The piece lasts as long as its timeline; a ringing crash may run past it.
    const end = try (primitives.Timing{ .beat = written.guitar_root.extent }).resolve(context);
    const samples = try mixer.finish(end);
    mix.normalize(configs.T, samples, configs.PEAK);
    return samples;
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

test {
    std.testing.refAllDecls(@This());
}
