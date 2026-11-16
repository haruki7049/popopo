const std = @import("std");
const meters = @import("meters");
const configs = @import("./configs.zig");

pub const Timing = struct {
    const Self = @This();

    const Error = error{
        InvalidPosition,
    };

    /// 0-indexed bar, counted from the start of the segment the element was written in.
    bar: usize = 0,
    /// Beat offset from the start of `bar`; must be finite and not negative.
    beat: f64 = 0.0,

    /// A frame position, counted from the start of the score.
    pub const ResolveT = usize;

    /// Resolves this timing to a frame position: `ctx.origin` beats, plus `bar` bars, plus `beat`
    /// beats, rounded to the nearest frame once. Returns `error.InvalidPosition` for a beat that is
    /// NaN, negative or infinite or a position beyond a `usize`, and a `tempo.Error` for an invalid
    /// context.
    pub fn resolve(self: Self, ctx: meters.Context) (Self.Error || meters.tempo.Error)!ResolveT {
        // Written as a negation so that NaN is rejected too; infinity is caught below.
        if (!(self.beat >= 0.0)) return error.InvalidPosition;

        const spb = try meters.tempo.samplesPerBeat(ctx.bpm, ctx.time_signature, ctx.sample_rate);
        const numerator: f64 = @floatFromInt(ctx.time_signature.numerator);
        const beats = ctx.origin + @as(f64, @floatFromInt(self.bar)) * numerator + self.beat;
        return meters.tempo.framesFromBeats(beats, spb) orelse error.InvalidPosition;
    }

    /// A transform for `Layer.map` that moves every timing to `factor` times its position, counted
    /// from the start of the layer: 0.5 puts it twice as near, as if it were played twice as fast.
    /// It goes with `Layer.stretch`, which scales the extent and the origins in the same way.
    pub const Stretch = struct {
        /// What every position is multiplied by; must be finite and greater than zero.
        factor: f64,
        /// Beats in a bar, which positions are counted in: a bar and a beat make one position.
        beats_per_bar: f64 = @floatFromInt(configs.BEATS_PER_BAR),

        /// The timing at `factor` times the position of `timing`, written again as a bar and a beat.
        /// Returns `error.InvalidPosition` for a factor that is not finite and greater than zero, and
        /// for a timing whose beat is NaN, negative or infinite.
        pub fn apply(self: Stretch, timing: Self) Self.Error!Self {
            if (!std.math.isFinite(self.factor) or !(self.factor > 0.0)) return error.InvalidPosition;
            if (!std.math.isFinite(timing.beat) or !(timing.beat >= 0.0)) return error.InvalidPosition;

            const position = @as(f64, @floatFromInt(timing.bar)) * self.beats_per_bar + timing.beat;
            const stretched = position * self.factor;
            const bar = @floor(stretched / self.beats_per_bar);
            return .{ .bar = @intFromFloat(bar), .beat = stretched - bar * self.beats_per_bar };
        }
    };
};

/// The energy given to a vibrating body. Zero is a rest: the note does not sound.
pub const Volume = struct {
    /// Linear level from 0 (a rest) to 1 (full).
    value: configs.T,

    /// A linear level, handed to the timbre as its volume.
    pub const ResolveT = configs.T;

    /// Resolves to `value` as it is. Ignores `ctx`.
    pub fn resolve(self: Volume, ctx: meters.Context) ResolveT {
        _ = ctx;
        return self.value;
    }
};
