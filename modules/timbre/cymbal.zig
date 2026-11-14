//! Cymbals: a thin metal plate struck once, solved on a grid (see `plate.zig`), mixed with noise,
//! high-passed, with a decay. The closed hi-hat, the open hi-hat and the crash are three settings of
//! the same timbre.
//!
//! The metal is the velocity of the plate, whose many inharmonic partials are the shimmer of a
//! cymbal. The noise stays as the sizzle that a linear plate alone does not have. Neither the plate
//! nor the settings are checked by ear.
//!
//! Solving the plate costs far more than the rest of a hit, and it is the same for every hit of a
//! setting, so it can be done once: `respond` solves it, and `renderWith` reads the result for each
//! note. `render` does both for one note.

const std = @import("std");
const dsp = @import("./dsp.zig");
const Plate = @import("./plate.zig").inner;

/// Scale of the plate. It gives the plate, after the filters, about the level and the decay of the
/// metal it replaced (the sum of square partials): within a factor of 1.5 over the first 0.3 s.
const plate_scale = 1.0;

/// Returns the cymbal type for samples of type `T`. The fields are the parameters of the timbre.
pub fn inner(comptime T: type) type {
    return struct {
        const Self = @This();

        /// Time constant of the decay, in seconds.
        decay: T,
        /// Cutoff of the high-pass that leaves only the sizzle, in Hz.
        tone: T,
        /// Cutoff of the low-pass that softens the top, in Hz.
        brightness: T,
        /// Share of the plate against the noise, from 0 to 1.
        metal: T,
        /// Rise at the start of the hit, in seconds.
        attack: T = 0.0005,
        /// Fade of the timbre at the end of the note, in seconds.
        release: T = 0.006,

        /// A closed hi-hat: short and bright.
        pub const closed: Self = .{ .decay = 0.032, .tone = 7600.0, .brightness = 15000.0, .metal = 0.55 };
        /// An open hi-hat: the same metal, ringing.
        pub const open: Self = .{ .decay = 0.28, .tone = 6400.0, .brightness = 13500.0, .metal = 0.6 };
        /// A crash cymbal: wider, lower and long.
        pub const crash: Self = .{ .decay = 0.85, .tone = 3600.0, .brightness = 10500.0, .metal = 0.4, .attack = 0.002 };

        /// The sound of the plate for this setting and a sample rate, which does not depend on the
        /// note: the plate has no noise and no volume, and it is struck the same way every time. It
        /// is solved once with `respond` and read by any number of notes with `renderWith`.
        pub const Response = struct {
            /// The plate velocity from the strike on, mono, or null if the plate is too small for the
            /// sample rate, which leaves only the noise. After its last frame the plate counts as
            /// silent.
            plate: ?[]T,

            pub fn deinit(self: Response, allocator: std.mem.Allocator) void {
                if (self.plate) |samples| allocator.free(samples);
            }
        };

        /// Solves the plate for `frames` frames at `sample_rate`. A note that sounds longer than
        /// `frames` reads silence after them, so `frames` is the longest note to be rendered with it.
        /// The caller frees the response with `deinit`.
        pub fn respond(self: Self, allocator: std.mem.Allocator, sample_rate: u32, frames: usize) std.mem.Allocator.Error!Response {
            // The plate loses the amplitude `exp(-t / decay)` at least, as the noise does. It is not
            // faded here, the fade comes after the filters. A plate too small for the sample rate
            // gives no metal, only the noise.
            var plate: Plate(T) = .{ .sigma0 = 1.0 / self.decay, .sigma1 = 2.0e-5, .release = 0.0 };
            const samples = plate.render(allocator, sample_rate, 1, 1.0, frames, frames) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.GridTooSmall => return .{ .plate = null },
            };
            return .{ .plate = samples };
        }

        /// Returns the first `frames` frames (mono) of a hit at `volume` that sounds `length`
        /// frames if nothing cuts it. The noise is drawn from `random`, so the caller decides the
        /// seed. Frames past `length` are silent. The caller owns the samples.
        pub fn render(self: Self, allocator: std.mem.Allocator, random: std.Random, sample_rate: u32, volume: T, length: usize, frames: usize) std.mem.Allocator.Error![]T {
            const response = try self.respond(allocator, sample_rate, frames);
            defer response.deinit(allocator);
            return self.renderWith(allocator, random, sample_rate, volume, length, frames, response);
        }

        /// The same as `render`, with the plate read from `response` (made by `respond` for the same
        /// setting and sample rate) instead of solved again. The samples are the same as `render`
        /// gives whenever the response has at least `frames` frames.
        pub fn renderWith(self: Self, allocator: std.mem.Allocator, random: std.Random, sample_rate: u32, volume: T, length: usize, frames: usize, response: Response) std.mem.Allocator.Error![]T {
            const samples = try allocator.alloc(T, frames);
            const rate: T = @floatFromInt(sample_rate);
            const release_frames = dsp.frames(T, self.release, sample_rate);

            const share: T = if (response.plate == null) 0.0 else self.metal;
            var high_a = dsp.Biquad(T).init(.highpass, self.tone, 0.707, rate);
            var high_b = dsp.Biquad(T).init(.highpass, self.tone, 0.707, rate);
            var top = dsp.Biquad(T).init(.lowpass, self.brightness, 0.707, rate);

            for (samples, 0..) |*sample, i| {
                const t = @as(T, @floatFromInt(i)) / rate;

                const metal: T = if (response.plate) |m| (if (i < m.len) plate_scale * m[i] else 0.0) else 0.0;
                const noise = (random.float(T) * 2.0 - 1.0) * dsp.decay(T, t, self.decay);

                const sizzle = top.process(high_b.process(high_a.process(share * metal + (1.0 - share) * noise)));
                sample.* = volume * 2.5 * sizzle * dsp.rise(T, t, self.attack) * dsp.tail(T, i, length, release_frames);
            }
            return samples;
        }
    };
}

test "every setting returns the frames asked for, starting and ending at zero" {
    const allocator = std.testing.allocator;
    const Cymbal = inner(f64);
    inline for (.{ Cymbal.closed, Cymbal.open, Cymbal.crash }) |cymbal| {
        var prng = std.Random.DefaultPrng.init(1);
        const samples = try cymbal.render(allocator, prng.random(), 44100, 1.0, 6000, 6000);
        defer allocator.free(samples);

        try std.testing.expectEqual(@as(usize, 6000), samples.len);
        try std.testing.expectEqual(@as(f64, 0.0), samples[0]);
        try std.testing.expectEqual(@as(f64, 0.0), samples[samples.len - 1]);
        for (samples) |s| try std.testing.expect(std.math.isFinite(s) and @abs(s) < 2.0);
    }
}

test "the open hi-hat rings longer than the closed one" {
    const allocator = std.testing.allocator;
    const Cymbal = inner(f64);
    var energy: [2]f64 = .{ 0.0, 0.0 };
    inline for (.{ Cymbal.closed, Cymbal.open }, 0..) |cymbal, k| {
        var prng = std.Random.DefaultPrng.init(3);
        const samples = try cymbal.render(allocator, prng.random(), 44100, 1.0, 22050, 22050);
        defer allocator.free(samples);
        // Energy after 0.1 s.
        for (samples[4410..]) |s| energy[k] += s * s;
    }
    try std.testing.expect(energy[1] > 100.0 * energy[0]);
}

test "with the plate alone the sound does not depend on the seed, and it is not silent" {
    const allocator = std.testing.allocator;
    var cymbal = inner(f64).open;
    cymbal.metal = 1.0;

    var first = std.Random.DefaultPrng.init(1);
    const a = try cymbal.render(allocator, first.random(), 44100, 1.0, 4000, 4000);
    defer allocator.free(a);
    var second = std.Random.DefaultPrng.init(2);
    const b = try cymbal.render(allocator, second.random(), 44100, 1.0, 4000, 4000);
    defer allocator.free(b);

    try std.testing.expectEqualSlices(f64, a, b);
    var peak: f64 = 0.0;
    for (a) |s| peak = @max(peak, @abs(s));
    try std.testing.expect(peak > 0.01);
}

test "a cut hit is the start of the full hit" {
    const allocator = std.testing.allocator;
    const cymbal = inner(f64).closed;

    var first = std.Random.DefaultPrng.init(7);
    const full = try cymbal.render(allocator, first.random(), 44100, 0.8, 5000, 5000);
    defer allocator.free(full);
    var second = std.Random.DefaultPrng.init(7);
    const cut = try cymbal.render(allocator, second.random(), 44100, 0.8, 5000, 1500);
    defer allocator.free(cut);

    try std.testing.expectEqualSlices(f64, full[0..1500], cut);
}

test "a response solved for longer than the note gives the same samples as render" {
    const allocator = std.testing.allocator;
    const cymbal = inner(f64).open;

    var first = std.Random.DefaultPrng.init(11);
    const direct = try cymbal.render(allocator, first.random(), 44100, 0.7, 3000, 3000);
    defer allocator.free(direct);

    const response = try cymbal.respond(allocator, 44100, 6000);
    defer response.deinit(allocator);
    var second = std.Random.DefaultPrng.init(11);
    const shared = try cymbal.renderWith(allocator, second.random(), 44100, 0.7, 3000, 3000, response);
    defer allocator.free(shared);

    try std.testing.expectEqualSlices(f64, direct, shared);
}

test "one response serves notes of different volumes, lengths and seeds" {
    const allocator = std.testing.allocator;
    const cymbal = inner(f64).closed;
    const response = try cymbal.respond(allocator, 44100, 4000);
    defer response.deinit(allocator);

    var first = std.Random.DefaultPrng.init(1);
    const loud = try cymbal.renderWith(allocator, first.random(), 44100, 1.0, 4000, 4000, response);
    defer allocator.free(loud);
    var second = std.Random.DefaultPrng.init(1);
    const quiet = try cymbal.renderWith(allocator, second.random(), 44100, 0.5, 2000, 2000, response);
    defer allocator.free(quiet);

    // The same seed and the same plate: half the volume is half the samples, up to the fade.
    for (0..1500) |i| try std.testing.expectApproxEqAbs(0.5 * loud[i], quiet[i], 1e-12);
}

test "past the end of the response the plate counts as silent" {
    const allocator = std.testing.allocator;
    var cymbal = inner(f64).closed;
    cymbal.metal = 1.0;
    const response = try cymbal.respond(allocator, 44100, 500);
    defer response.deinit(allocator);

    var prng = std.Random.DefaultPrng.init(1);
    const samples = try cymbal.renderWith(allocator, prng.random(), 44100, 1.0, 3000, 3000, response);
    defer allocator.free(samples);

    var peak: f64 = 0.0;
    for (samples[2000..]) |s| peak = @max(peak, @abs(s));
    try std.testing.expect(peak < 1e-3);
}

test {
    std.testing.refAllDecls(@This());
}
