const pitches = @import("pitches");
const meters = @import("meters");
const configs = @import("./configs.zig");

/// Twelve-tone equal temperament at A4 = 440 Hz.
pub const tuning: pitches.TwelveToneEqualTemperament = .{ .a4 = 440.0 };

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
};

pub const Pitch = struct {
    name: pitches.TwelveTonePitch,

    pub const ResolveT = configs.T;

    /// Resolves the name to its frequency in `tuning`. Ignores `ctx`.
    pub fn resolve(self: Pitch, ctx: meters.Context) ResolveT {
        _ = ctx;
        return tuning.freq(self.name);
    }
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

pub const Duration = struct {
    const Self = @This();

    const DurationError = error{
        InvalidDuration, // When meters.tempo.framesFromBeats function returns null
    };

    /// Written length in beats of the time signature; must be finite and not negative.
    beats: f64,

    /// A length in frames.
    pub const ResolveT = usize;

    /// Resolves this duration to a length in frames, rounded to the nearest frame. The origin of the
    /// segment does not change a length, so `ctx.origin` is ignored. Returns `error.InvalidDuration`
    /// for beats that are NaN, negative or infinite or a length beyond a `usize`, and a `tempo.Error`
    /// for an invalid context.
    pub fn resolve(self: Self, ctx: meters.Context) (DurationError || meters.tempo.Error)!ResolveT {
        const spb = try meters.tempo.samplesPerBeat(ctx.bpm, ctx.time_signature, ctx.sample_rate);
        return meters.tempo.framesFromBeats(self.beats, spb) orelse error.InvalidDuration;
    }
};

/// How far the palm mutes a guitar string, from 0 (open) to 1 (fully muted).
pub const Mute = struct {
    /// From 0 (open) to 1 (fully muted).
    amount: configs.T,

    /// The amount of muting, handed to the guitar timbre and to the length of the note.
    pub const ResolveT = configs.T;

    /// Resolves to `amount` as it is. Ignores `ctx`.
    pub fn resolve(self: Mute, ctx: meters.Context) ResolveT {
        _ = ctx;
        return self.amount;
    }
};
