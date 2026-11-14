//! Rock snare drum: two shell modes, a noise crack, and band-limited noise for the wires, driven.
//! The wires are driven by the shell: their level follows the motion of the head, so the two sound
//! as one drum, not as a tone with a hiss laid on it.

const std = @import("std");
const lightmix = @import("lightmix");
const dsp = @import("./dsp.zig");

/// Returns the snare type for samples of type `T`. The fields are the parameters of the timbre.
pub fn inner(comptime T: type) type {
    return struct {
        const Self = @This();

        const Error = std.mem.Allocator.Error;

        /// Lower shell mode, in Hz.
        shell_frequency: T = 182.0,
        /// Upper shell mode as a ratio of the lower one.
        shell_ratio: T = 1.62,
        /// Time constant of the shell, in seconds.
        shell_decay: T = 0.07,
        /// Level of the wires.
        wires: T = 0.85,
        /// How much the wires follow the motion of the shell, from 0 (they ring on their own, as
        /// noise with a decay) to 1 (they sound only while the head moves).
        wire_coupling: T = 0.9,
        /// How fast the wires settle after the head moves, in seconds. A time shorter than a cycle
        /// of the shell makes the wires buzz in step with it.
        wire_follow: T = 0.004,
        /// Time constant of the wires, in seconds.
        wire_decay: T = 0.16,
        /// Level of the initial crack.
        crack: T = 0.6,
        /// Saturation of the whole hit.
        drive: T = 2.0,
        /// Fade of the timbre at the end of the note, in seconds.
        release: T = 0.008,

        /// Returns the first `frames` frames (mono) of a hit at `volume` that sounds `length`
        /// frames if nothing cuts it. The noise is drawn from `random`, so the caller decides the
        /// seed. Frames past `length` are silent. The caller owns the samples.
        pub fn render(self: Self, allocator: std.mem.Allocator, random: std.Random, sample_rate: u32, channels: u16, volume: T, length: usize, frames: usize) std.mem.Allocator.Error![]T {
            const samples = try allocator.alloc(T, frames * channels);
            const rate: T = @floatFromInt(sample_rate);
            const release_frames = dsp.frames(T, self.release, sample_rate);

            var low: dsp.Oscillator(T) = .{};
            var high: dsp.Oscillator(T) = .{};
            var wire_band = dsp.Biquad(T).init(.bandpass, 3800.0, 0.55, rate);
            var wire_air = dsp.Biquad(T).init(.highpass, 1400.0, 0.707, rate);
            // The motion of the head as the wires feel it: its size, which falls slowly.
            var head: T = 0.0;
            const follow_keep: T = @exp(-1.0 / (@max(self.wire_follow, 1.0e-6) * rate));

            for (0..samples.len / channels) |i| {
                const t = @as(T, @floatFromInt(i)) / rate;
                // The head is tighter for a moment after the hit, so the shell starts a little sharp.
                const bend = 1.0 + 0.12 * dsp.decay(T, t, 0.012);
                const shell = (0.7 * low.sine(self.shell_frequency * bend, rate) +
                    0.4 * high.sine(self.shell_frequency * self.shell_ratio * bend, rate)) * dsp.decay(T, t, self.shell_decay);

                const noise = random.float(T) * 2.0 - 1.0;
                // The wires are thrown by the head: they buzz where the head moves, and a little on
                // their own for what is left of `wire_coupling`.
                head = @max(@abs(shell) / 1.1, head * follow_keep);
                const gate = self.wire_coupling * head + (1.0 - self.wire_coupling);
                const wires = (wire_band.process(noise) + 0.5 * wire_air.process(noise)) * dsp.decay(T, t, self.wire_decay) * gate;
                const crack = noise * dsp.decay(T, t, 0.005);

                const hit = shell + self.wires * wires + self.crack * crack;
                const onset = dsp.rise(T, t, 0.0004);

                const value = volume * dsp.saturate(T, hit * onset, self.drive) * dsp.tail(T, i, length, release_frames);
                for (0..channels) |j|
                    samples[i * channels + j] = value;
            }
            return samples;
        }

        pub fn wave(self: Self, allocator: std.mem.Allocator, random: std.Random, sample_rate: u32, channels: u16, volume: T, length: usize, frames: usize) Self.Error!lightmix.Wave(T) {
            const samples = try self.render(allocator, random, sample_rate, channels, volume, length, frames);

            return .{
                .samples = samples,
                .allocator = allocator,
                .sample_rate = sample_rate,
                .channels = channels,
            };
        }
    };
}

test "render returns the frames asked for, starting and ending at zero" {
    const allocator = std.testing.allocator;
    var prng = std.Random.DefaultPrng.init(7);
    const snare: inner(f64) = .{};
    const samples = try snare.render(allocator, prng.random(), 44100, 1, 1.0, 13230, 13230);
    defer allocator.free(samples);

    try std.testing.expectEqual(@as(usize, 13230), samples.len);
    try std.testing.expectEqual(@as(f64, 0.0), samples[0]);
    try std.testing.expectEqual(@as(f64, 0.0), samples[samples.len - 1]);
    for (samples) |s| try std.testing.expect(@abs(s) < 1.05);
}

test "the same seed gives the same hit, and a cut hit is the start of the full hit" {
    const allocator = std.testing.allocator;
    const snare: inner(f64) = .{};

    var a = std.Random.DefaultPrng.init(42);
    const full = try snare.render(allocator, a.random(), 44100, 1, 0.9, 8000, 8000);
    defer allocator.free(full);
    var b = std.Random.DefaultPrng.init(42);
    const cut = try snare.render(allocator, b.random(), 44100, 1, 0.9, 8000, 2500);
    defer allocator.free(cut);

    try std.testing.expectEqualSlices(f64, full[0..2500], cut);
}

test "The frames of stereo samples is the double with mono samples" {
    const SAMPLE_RATE: u32 = 44100;
    const VOLUME: f64 = 1.0;
    const FRAMES: usize = 15345;
    const LENGTH: usize = FRAMES;
    const MONO: u16 = 1;
    const STEREO: u16 = 2;

    const allocator = std.testing.allocator;
    var prng = std.Random.DefaultPrng.init(7);
    const snare: inner(f64) = .{};

    const mono = try snare.render(allocator, prng.random(), SAMPLE_RATE, MONO, VOLUME, LENGTH, FRAMES);
    defer allocator.free(mono);
    const stereo = try snare.render(allocator, prng.random(), SAMPLE_RATE, STEREO, VOLUME, LENGTH, FRAMES);
    defer allocator.free(stereo);

    try std.testing.expectEqual(mono.len, FRAMES);
    try std.testing.expectEqual(stereo.len, mono.len * 2);
}

test "the wires follow the head: with coupling they die away with the shell" {
    const allocator = std.testing.allocator;
    const SAMPLE_RATE: u32 = 44100;
    const frames: usize = 22050;

    // Both hits have the same noise; only the coupling differs.
    const free: inner(f64) = .{ .wire_coupling = 0.0 };
    const coupled: inner(f64) = .{ .wire_coupling = 1.0 };
    var a = std.Random.DefaultPrng.init(3);
    const loose = try free.render(allocator, a.random(), SAMPLE_RATE, 1, 1.0, frames, frames);
    defer allocator.free(loose);
    var b = std.Random.DefaultPrng.init(3);
    const tied = try coupled.render(allocator, b.random(), SAMPLE_RATE, 1, 1.0, frames, frames);
    defer allocator.free(tied);

    // Well after the shell has died (7 time constants), the free wires still ring; the coupled ones do not.
    var loose_energy: f64 = 0.0;
    var tied_energy: f64 = 0.0;
    for (frames / 2..frames) |i| {
        loose_energy += loose[i] * loose[i];
        tied_energy += tied[i] * tied[i];
    }
    try std.testing.expect(tied_energy < 0.1 * loose_energy);
}

test {
    std.testing.refAllDecls(@This());
}
