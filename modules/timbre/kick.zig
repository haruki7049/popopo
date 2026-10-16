//! Rock kick drum: a sine that drops in pitch, a beater click, and saturation for punch.

const std = @import("std");
const dsp = @import("./dsp.zig");

/// Returns the kick type for samples of type `T`. The fields are the parameters of the timbre.
pub fn inner(comptime T: type) type {
    return struct {
        const Self = @This();

        /// Pitch of the body when the beater hits, in Hz.
        start_frequency: T = 165.0,
        /// Pitch the body settles to, in Hz.
        end_frequency: T = 47.0,
        /// Time constant of the pitch drop, in seconds.
        sweep: T = 0.035,
        /// Time constant of the body's decay, in seconds.
        decay: T = 0.2,
        /// Level of the beater click.
        click: T = 0.4,
        /// Saturation of the whole hit.
        punch: T = 2.4,
        /// Fade of the timbre at the end of the note, in seconds.
        release: T = 0.008,

        /// Returns the first `frames` frames (mono) of a hit at `volume` that sounds `length`
        /// frames if nothing cuts it. Frames past `length` are silent. The caller owns the samples.
        pub fn render(self: Self, allocator: std.mem.Allocator, sample_rate: u32, volume: T, length: usize, frames: usize) std.mem.Allocator.Error![]T {
            const samples = try allocator.alloc(T, frames);
            const rate: T = @floatFromInt(sample_rate);
            const release_frames = dsp.frames(T, self.release, sample_rate);

            var body: dsp.Oscillator(T) = .{};
            var tick_low: dsp.Oscillator(T) = .{};
            var tick_high: dsp.Oscillator(T) = .{};

            for (samples, 0..) |*sample, i| {
                const t = @as(T, @floatFromInt(i)) / rate;
                const frequency = self.end_frequency + (self.start_frequency - self.end_frequency) * dsp.decay(T, t, self.sweep);

                const thump = body.sine(frequency, rate) * dsp.decay(T, t, self.decay);
                const tick = (0.6 * tick_low.sine(2100.0, rate) + 0.4 * tick_high.sine(3900.0, rate)) * dsp.decay(T, t, 0.004);
                const hit = dsp.saturate(T, thump + self.click * tick, self.punch);

                sample.* = volume * hit * dsp.tail(T, i, length, release_frames);
            }
            return samples;
        }
    };
}

test "render returns the frames asked for, starting and ending at zero" {
    const allocator = std.testing.allocator;
    const kick: inner(f64) = .{};
    const samples = try kick.render(allocator, 44100, 1.0, 15435, 15435);
    defer allocator.free(samples);

    try std.testing.expectEqual(@as(usize, 15435), samples.len);
    try std.testing.expectEqual(@as(f64, 0.0), samples[0]);
    try std.testing.expectEqual(@as(f64, 0.0), samples[samples.len - 1]);
    var peak: f64 = 0.0;
    for (samples) |s| peak = @max(peak, @abs(s));
    try std.testing.expect(peak > 0.5 and peak < 1.05);
}

test "a cut hit is the start of the full hit" {
    const allocator = std.testing.allocator;
    const kick: inner(f64) = .{};
    const full = try kick.render(allocator, 44100, 0.8, 10000, 10000);
    defer allocator.free(full);
    const cut = try kick.render(allocator, 44100, 0.8, 10000, 3000);
    defer allocator.free(cut);
    try std.testing.expectEqualSlices(f64, full[0..3000], cut);
}

test {
    std.testing.refAllDecls(@This());
}
