//! Sawtooth synthesizer: one band-limited sawtooth per pitch of a chord, summed, with a short rise
//! at the start of the note and a short fade at its end. Nothing else is done to the sound.

const std = @import("std");
const lightmix = @import("lightmix");
const dsp = @import("./dsp.zig");

/// Returns the sawtooth type for samples of type `T`. The fields are the parameters of the timbre.
pub fn inner(comptime T: type) type {
    return struct {
        const Self = @This();

        const Error = std.mem.Allocator.Error;

        /// Most pitches of a chord that are summed.
        const voices = 8;

        /// Rise at the start of the note, in seconds.
        attack: T = 0.002,
        /// Fade of the timbre at the end of the note, in seconds.
        release: T = 0.01,

        /// Returns the first `frames` frames (mono) of a chord, given as the frequencies in Hz of
        /// its pitches, at `volume` that sounds `length` frames if nothing cuts it. At most `voices`
        /// pitches sound. The sum is divided by the number of pitches, so a chord is as loud as a
        /// single pitch. Frames past `length` are silent. The caller owns the samples.
        pub fn render(self: Self, allocator: std.mem.Allocator, sample_rate: u32, frequencies: []const T, volume: T, length: usize, frames: usize) Self.Error![]T {
            const samples = try allocator.alloc(T, frames);
            const rate: T = @floatFromInt(sample_rate);
            const release_frames = dsp.frames(T, self.release, sample_rate);

            const count = @min(frequencies.len, voices);
            var oscillators: [voices]dsp.Oscillator(T) = @splat(.{});
            const share: T = if (count > 0) 1.0 / @as(T, @floatFromInt(count)) else 0.0;

            for (samples, 0..) |*sample, i| {
                const t = @as(T, @floatFromInt(i)) / rate;

                var sum: T = 0.0;
                for (oscillators[0..count], frequencies[0..count]) |*oscillator, frequency| {
                    sum += oscillator.saw(frequency, rate);
                }

                sample.* = volume * share * sum * dsp.rise(T, t, self.attack) * dsp.tail(T, i, length, release_frames);
            }
            return samples;
        }

        pub fn wave(self: Self, allocator: std.mem.Allocator, sample_rate: u32, frequencies: []const T, volume: T, length: usize, frames: usize) Self.Error!lightmix.Wave(T) {
            const samples = try self.render(allocator, sample_rate, frequencies, volume, length, frames);

            return .{
                .samples = samples,
                .allocator = allocator,
                .sample_rate = sample_rate,
                .channels = 1,
            };
        }
    };
}

test "render returns the frames asked for, starting and ending at zero" {
    const allocator = std.testing.allocator;
    const saw: inner(f64) = .{};
    const samples = try saw.render(allocator, 44100, &.{ 220.0, 261.63, 329.63 }, 1.0, 4000, 4000);
    defer allocator.free(samples);

    try std.testing.expectEqual(@as(usize, 4000), samples.len);
    try std.testing.expectEqual(@as(f64, 0.0), samples[0]);
    try std.testing.expectEqual(@as(f64, 0.0), samples[samples.len - 1]);
    var peak: f64 = 0.0;
    for (samples) |s| peak = @max(peak, @abs(s));
    try std.testing.expect(peak > 0.3 and peak <= 1.0);
}

test "a cut note is the start of the full note" {
    const allocator = std.testing.allocator;
    const saw: inner(f64) = .{};
    const full = try saw.render(allocator, 44100, &.{ 220.0, 330.0 }, 0.8, 4000, 4000);
    defer allocator.free(full);
    const cut = try saw.render(allocator, 44100, &.{ 220.0, 330.0 }, 0.8, 4000, 1500);
    defer allocator.free(cut);
    try std.testing.expectEqualSlices(f64, full[0..1500], cut);
}

test "frames past the length are silent, and so is a chord with no pitch" {
    const allocator = std.testing.allocator;
    const saw: inner(f64) = .{};
    const late = try saw.render(allocator, 44100, &.{220.0}, 1.0, 1000, 1200);
    defer allocator.free(late);
    for (late[1000..]) |s| try std.testing.expectEqual(@as(f64, 0.0), s);

    const none = try saw.render(allocator, 44100, &.{}, 1.0, 1000, 1000);
    defer allocator.free(none);
    for (none) |s| try std.testing.expectEqual(@as(f64, 0.0), s);
}

test {
    std.testing.refAllDecls(@This());
}
