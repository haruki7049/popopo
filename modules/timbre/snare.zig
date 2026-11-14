//! Rock snare drum: the modes of a circular head, a noise crack, and the wires, driven.
//! The wires are driven by the head. Their level follows its motion, and the head also throws a
//! buzz of its own harmonics into them, so the two sound as one drum, not as a tone with a hiss
//! laid on it.

const std = @import("std");
const lightmix = @import("lightmix");
const dsp = @import("./dsp.zig");

/// Returns the snare type for samples of type `T`. The fields are the parameters of the timbre.
pub fn inner(comptime T: type) type {
    return struct {
        const Self = @This();

        const Error = std.mem.Allocator.Error;

        /// Lowest mode of the head, in Hz. The other modes lie above it as in a circular membrane.
        shell_frequency: T = 182.0,
        /// Time constant of the lowest mode, in seconds. The higher modes die faster.
        shell_decay: T = 0.07,
        /// How much of the motion of the head is thrown into the wires as a buzz at its own
        /// harmonics, besides the noise.
        wire_buzz: T = 2.0,
        /// Level of the wires.
        wires: T = 2.0,
        /// How much the wires follow the motion of the shell, from 0 (they keep ringing for
        /// `wire_decay` after the head has stopped) to 1 (they sound only while the head moves).
        wire_coupling: T = 0.85,
        /// How fast the wires settle after the head moves, in seconds. A time shorter than a cycle
        /// of the shell makes the wires buzz in step with it.
        wire_follow: T = 0.002,
        /// Time constant of the wires, in seconds.
        wire_decay: T = 0.16,
        /// Level of the initial crack.
        crack: T = 0.35,
        /// Saturation of the whole hit.
        drive: T = 1.2,
        /// Level of the hit going into the saturation, which is `tanh`, so no sample passes `volume`.
        /// The lower it is, the less the peaks are bent. It changes the loudness of the drum and
        /// how hard the hit is saturated, not the `volume` of a note.
        input_gain: T = 0.6,
        /// Fade of the timbre at the end of the note, in seconds.
        release: T = 0.008,

        /// The modes of a circular membrane as ratios of the lowest one, the zeros of the Bessel
        /// functions over the first: (0,1) (1,1) (2,1) (0,2) (3,1) (1,2) (4,1) (2,2) (0,3) (5,1)
        /// (3,2) (6,1) (1,3) (4,2) (7,1) (2,3).
        const mode_ratios = [_]T{ 1.0, 1.594, 2.136, 2.295, 2.653, 2.917, 3.156, 3.500, 3.598, 3.647, 4.059, 4.131, 4.230, 4.601, 4.610, 4.832 };

        /// Returns the first `frames` frames (mono) of a hit at `volume` that sounds `length`
        /// frames if nothing cuts it. The noise is drawn from `random`, so the caller decides the
        /// seed. Frames past `length` are silent. The caller owns the samples.
        pub fn render(self: Self, allocator: std.mem.Allocator, random: std.Random, sample_rate: u32, channels: u16, volume: T, length: usize, frames: usize) std.mem.Allocator.Error![]T {
            const samples = try allocator.alloc(T, frames * channels);
            const rate: T = @floatFromInt(sample_rate);
            const release_frames = dsp.frames(T, self.release, sample_rate);

            var modes: [mode_ratios.len]dsp.Oscillator(T) = @splat(.{});
            // Level of a mode: lower modes are stronger, and the strike does not excite them evenly,
            // so the levels wobble in a fixed way. The sum bounds the shell at 1.
            var levels: [mode_ratios.len]T = undefined;
            var level_sum: T = 0.0;
            for (mode_ratios, 0..) |ratio, k| {
                levels[k] = (1.0 + 0.5 * @cos(2.3 * @as(T, @floatFromInt(k)))) / std.math.pow(T, ratio, 1.3);
                level_sum += levels[k];
            }
            var wire_band = dsp.Biquad(T).init(.bandpass, 3800.0, 0.55, rate);
            var wire_air = dsp.Biquad(T).init(.highpass, 1400.0, 0.707, rate);
            // The motion of the head as the wires feel it: its size, which falls slowly.
            var head: T = 0.0;
            // The same, but the wires keep ringing after the head has stopped, for `wire_decay`.
            var ring: T = 0.0;
            const ring_keep: T = @exp(-1.0 / (@max(self.wire_decay, 1.0e-6) * rate));
            const follow_keep: T = @exp(-1.0 / (@max(self.wire_follow, 1.0e-6) * rate));

            for (0..samples.len / channels) |i| {
                const t = @as(T, @floatFromInt(i)) / rate;
                // The head is tighter for a moment after the hit, so the shell starts a little sharp.
                const bend = 1.0 + 0.12 * dsp.decay(T, t, 0.012);
                var shell: T = 0.0;
                for (mode_ratios, 0..) |ratio, k| {
                    // A mode of a higher pitch loses its energy faster.
                    const tau = self.shell_decay / (1.0 + 0.5 * (ratio - 1.0));
                    shell += levels[k] * modes[k].sine(self.shell_frequency * ratio * bend, rate) * dsp.decay(T, t, tau);
                }
                shell *= 1.1 / level_sum;

                const noise = random.float(T) * 2.0 - 1.0;
                // The wires are thrown by the head: they buzz where the head moves, and a little on
                // their own for what is left of `wire_coupling`.
                head = @max(@abs(shell) / 1.1, head * follow_keep);
                ring = @max(@abs(shell) / 1.1, ring * ring_keep);
                const gate = self.wire_coupling * head + (1.0 - self.wire_coupling) * ring;
                // The wires hit the head and the shell in turn, which turns its motion into a buzz at
                // harmonics of it that reach up to where the wires sound.
                const buzz = dsp.saturate(T, shell, 8.0) - shell;
                const rattle = noise * gate + self.wire_buzz * buzz;
                const wires = wire_band.process(rattle) + 0.5 * wire_air.process(rattle);
                const crack = noise * dsp.decay(T, t, 0.005);

                const hit = shell + self.wires * wires + self.crack * crack;
                const onset = dsp.rise(T, t, 0.0004);

                const value = volume * std.math.tanh(self.drive * self.input_gain * hit * onset) * dsp.tail(T, i, length, release_frames);
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
