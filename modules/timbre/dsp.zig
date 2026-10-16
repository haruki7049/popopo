//! Signal building blocks shared by the timbres: oscillators, filters, saturation and envelopes.
//!
//! These are internal to the timbre module. Every block keeps its state in its own value; nothing
//! here holds global state.

const std = @import("std");

/// Returns a band-limited (polyBLEP) oscillator type with sawtooth and square outputs.
pub fn Oscillator(comptime T: type) type {
    return struct {
        const Self = @This();

        /// Position in the cycle, in [0, 1).
        phase: T = 0.0,

        /// Advances by one sample at `frequency` Hz and returns the sawtooth, from -1 to 1.
        pub fn saw(self: *Self, frequency: T, sample_rate: T) T {
            const step = frequency / sample_rate;
            const value = 2.0 * self.phase - 1.0 - blep(self.phase, step);
            self.advance(step);
            return value;
        }

        /// Advances by one sample at `frequency` Hz and returns the square, from -1 to 1.
        pub fn square(self: *Self, frequency: T, sample_rate: T) T {
            const step = frequency / sample_rate;
            const naive: T = if (self.phase < 0.5) 1.0 else -1.0;
            const value = naive + blep(self.phase, step) - blep(@mod(self.phase + 0.5, 1.0), step);
            self.advance(step);
            return value;
        }

        /// Advances by one sample at `frequency` Hz and returns the sine.
        pub fn sine(self: *Self, frequency: T, sample_rate: T) T {
            const value = @sin(2.0 * std.math.pi * self.phase);
            self.advance(frequency / sample_rate);
            return value;
        }

        fn advance(self: *Self, step: T) void {
            self.phase += step;
            self.phase -= @floor(self.phase);
        }

        /// The polyBLEP residual that smooths a jump at phase 0.
        fn blep(phase: T, step: T) T {
            if (step <= 0.0) return 0.0;
            if (phase < step) {
                const x = phase / step;
                return x + x - x * x - 1.0;
            }
            if (phase > 1.0 - step) {
                const x = (phase - 1.0) / step;
                return x * x + x + x + 1.0;
            }
            return 0.0;
        }
    };
}

/// Returns a second-order filter type (RBJ cookbook biquad, transposed direct form II).
pub fn Biquad(comptime T: type) type {
    return struct {
        const Self = @This();

        /// Feedforward coefficient of the current input, normalized by `a0`.
        b0: T,
        /// Feedforward coefficient of the input one sample back, normalized by `a0`.
        b1: T,
        /// Feedforward coefficient of the input two samples back, normalized by `a0`.
        b2: T,
        /// Feedback coefficient of the output one sample back, normalized by `a0`.
        a1: T,
        /// Feedback coefficient of the output two samples back, normalized by `a0`.
        a2: T,
        /// First state of the transposed direct form II.
        z1: T = 0.0,
        /// Second state of the transposed direct form II.
        z2: T = 0.0,

        /// Kind of response.
        pub const Kind = enum { lowpass, highpass, bandpass };

        /// A filter of `kind` at `cutoff` Hz with resonance `q`. The cutoff is kept below the
        /// Nyquist frequency.
        pub fn init(kind: Kind, cutoff: T, q: T, sample_rate: T) Self {
            var self: Self = .{ .b0 = 0.0, .b1 = 0.0, .b2 = 0.0, .a1 = 0.0, .a2 = 0.0 };
            self.tune(kind, cutoff, q, sample_rate);
            return self;
        }

        /// Changes the coefficients and keeps the state, for a cutoff that moves.
        pub fn tune(self: *Self, kind: Kind, cutoff: T, q: T, sample_rate: T) void {
            const f = std.math.clamp(cutoff, 10.0, 0.45 * sample_rate);
            const w = 2.0 * std.math.pi * f / sample_rate;
            const cos_w = @cos(w);
            const alpha = @sin(w) / (2.0 * q);
            const a0 = 1.0 + alpha;

            switch (kind) {
                .lowpass => {
                    self.b0 = (1.0 - cos_w) / 2.0 / a0;
                    self.b1 = (1.0 - cos_w) / a0;
                    self.b2 = self.b0;
                },
                .highpass => {
                    self.b0 = (1.0 + cos_w) / 2.0 / a0;
                    self.b1 = -(1.0 + cos_w) / a0;
                    self.b2 = self.b0;
                },
                .bandpass => {
                    self.b0 = alpha / a0;
                    self.b1 = 0.0;
                    self.b2 = -alpha / a0;
                },
            }
            self.a1 = -2.0 * cos_w / a0;
            self.a2 = (1.0 - alpha) / a0;
        }

        /// Filters one sample.
        pub fn process(self: *Self, x: T) T {
            const y = self.b0 * x + self.z1;
            self.z1 = self.b1 * x - self.a1 * y + self.z2;
            self.z2 = self.b2 * x - self.a2 * y;
            return y;
        }
    };
}

/// Saturates `x` with `tanh`, scaled so that an input of 1 stays 1 whatever the `drive`.
pub fn saturate(comptime T: type, x: T, drive: T) T {
    return std.math.tanh(drive * x) / std.math.tanh(drive);
}

/// Exponential decay with time constant `tau` seconds at `t` seconds.
pub fn decay(comptime T: type, t: T, tau: T) T {
    return @exp(-t / tau);
}

/// Rises from 0 to 1 over `attack` seconds (a raised cosine), then stays at 1.
pub fn rise(comptime T: type, t: T, attack: T) T {
    if (t >= attack) return 1.0;
    return 0.5 - 0.5 * @cos(std.math.pi * t / attack);
}

/// The end of a note: 1 until `release_frames` before frame `length`, then a raised cosine down to
/// 0 at the last frame, and 0 from frame `length` on.
pub fn tail(comptime T: type, i: usize, length: usize, release_frames: usize) T {
    if (i >= length) return 0.0;
    const left = length - i; // frames left including this one, at least 1
    if (left > release_frames) return 1.0;
    const progress = @as(T, @floatFromInt(left - 1)) / @as(T, @floatFromInt(release_frames));
    return 0.5 - 0.5 * @cos(std.math.pi * progress);
}

/// Seconds to frames at `sample_rate`, rounded to the nearest frame.
pub fn frames(comptime T: type, seconds: T, sample_rate: u32) usize {
    return @intFromFloat(@round(seconds * @as(T, @floatFromInt(sample_rate))));
}

test "saw and square stay within their range and average to about zero" {
    var saw: Oscillator(f64) = .{};
    var square: Oscillator(f64) = .{};
    var saw_sum: f64 = 0.0;
    var square_sum: f64 = 0.0;
    for (0..44100) |_| {
        const s = saw.saw(110.0, 44100.0);
        const q = square.square(110.0, 44100.0);
        try std.testing.expect(@abs(s) <= 1.0 + 1e-9);
        try std.testing.expect(@abs(q) <= 1.0 + 1e-9);
        saw_sum += s;
        square_sum += q;
    }
    try std.testing.expect(@abs(saw_sum / 44100.0) < 0.01);
    try std.testing.expect(@abs(square_sum / 44100.0) < 0.01);
}

test "lowpass passes a low tone and stops a high one" {
    var low = Biquad(f64).init(.lowpass, 500.0, 0.707, 44100.0);
    var high = Biquad(f64).init(.lowpass, 500.0, 0.707, 44100.0);
    var low_osc: Oscillator(f64) = .{};
    var high_osc: Oscillator(f64) = .{};
    var low_peak: f64 = 0.0;
    var high_peak: f64 = 0.0;
    for (0..44100) |i| {
        const a = low.process(low_osc.sine(100.0, 44100.0));
        const b = high.process(high_osc.sine(8000.0, 44100.0));
        if (i > 4410) {
            low_peak = @max(low_peak, @abs(a));
            high_peak = @max(high_peak, @abs(b));
        }
    }
    try std.testing.expect(low_peak > 0.9);
    try std.testing.expect(high_peak < 0.01);
}

test "tail ends at zero and is one before the release" {
    try std.testing.expectEqual(@as(f64, 1.0), tail(f64, 0, 100, 10));
    try std.testing.expectEqual(@as(f64, 1.0), tail(f64, 89, 100, 10));
    try std.testing.expect(tail(f64, 95, 100, 10) < 1.0);
    try std.testing.expectEqual(@as(f64, 0.0), tail(f64, 99, 100, 10));
    try std.testing.expectEqual(@as(f64, 0.0), tail(f64, 100, 100, 10));
}

test "rise starts at zero" {
    try std.testing.expectEqual(@as(f64, 0.0), rise(f64, 0.0, 0.01));
    try std.testing.expectEqual(@as(f64, 1.0), rise(f64, 0.01, 0.01));
}

test {
    std.testing.refAllDecls(@This());
}
