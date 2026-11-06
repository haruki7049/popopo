const std = @import("std");
const timbre = @import("timbre");
const lightmix = @import("lightmix");
const meters = @import("meters");

const primitives = struct {
    const Timing = struct {
        const Self = @This();

        const Error = error{InvalidPosition};

        /// 0-indexed bar, counted from the start of the segment the element was written in.
        bar: usize = 0,
        /// Beat offset from the start of `bar`; must be finite and not negative.
        beat: f64 = 0.0,

        /// A frame position, counted from the start of the score.
        const ResolveT = usize;

        /// Resolves this timing to a frame position: `ctx.origin` beats, plus `bar` bars, plus `beat`
        /// beats, rounded to the nearest frame once. Returns `error.InvalidPosition` for a beat that is
        /// NaN, negative or infinite or a position beyond a `usize`, and a `tempo.Error` for an invalid
        /// context.
        fn resolve(self: Self, ctx: meters.Context) (Self.Error || meters.tempo.Error)!ResolveT {
            // Written as a negation so that NaN is rejected too; infinity is caught below.
            if (!(self.beat >= 0.0)) return error.InvalidPosition;

            const spb = try meters.tempo.samplesPerBeat(ctx.bpm, ctx.time_signature, ctx.sample_rate);
            const numerator: f64 = @floatFromInt(ctx.time_signature.numerator);
            const beats = ctx.origin + @as(f64, @floatFromInt(self.bar)) * numerator + self.beat;
            return meters.tempo.framesFromBeats(beats, spb) orelse error.InvalidPosition;
        }
    };

    /// The energy given to a vibrating body. Zero is a rest: the note does not sound.
    const Volume = struct {
        /// Linear level from 0 (a rest) to 1 (full).
        value: configs.T,

        /// A linear level, handed to the timbre as its volume.
        const ResolveT = configs.T;

        /// Resolves to `value` as it is. Ignores `ctx`.
        fn resolve(self: Volume, ctx: meters.Context) ResolveT {
            _ = ctx;
            return self.value;
        }
    };
};

const lines = struct {
    const thin = struct {
        const Timing = meters.Layer(.{ .timing = primitives.Timing });
        const Volume = meters.Layer(.{ .volume = primitives.Volume });
    };

    const Hit = thin.Timing.Zip(thin.Volume);
};

const sheets = struct {
    const timing = struct {
        const Quarter: lines.thin.Timing = @import("./four-on-the-flour/timing-quarter.zon");
        const Third: lines.thin.Timing = @import("./four-on-the-flour/timing-third.zon");
    };

    const volume = struct {
        const Default: lines.thin.Volume = @import("./four-on-the-flour/volume-default.zon");
    };
};

/// Song-wide constants: tempo, meter and audio format.
const configs = struct {
    /// Tempo in quarter notes per minute.
    pub const BPM: usize = 135;
    /// Beats per bar (4/4).
    pub const BEATS_PER_BAR: usize = 4;
    /// Note value of one beat (4/4).
    pub const BEAT_VALUE: usize = 4;
    /// Sample rate in Hz, of the synthesis and of the output file.
    pub const SAMPLE_RATE: u32 = 44100;
    /// Monaural.
    pub const CHANNELS: u16 = 1;
    /// Sample type used for synthesis and mixing.
    pub const T = f64;
    /// Peak level the final mix is normalized to (about -1 dBFS).
    pub const PEAK: T = 0.89;
};

pub fn gen(init: std.process.Init) !lightmix.Wave(configs.T) {
    const volume: configs.T = 1.0;
    const length = configs.SAMPLE_RATE * 1;
    const frames = length;
    const allocator = init.arena.allocator();
    const kick = timbre.Kick(configs.T){};

    return kick.wave(
        allocator,
        configs.SAMPLE_RATE,
        configs.CHANNELS,
        volume,
        length,
        frames,
    );
}
