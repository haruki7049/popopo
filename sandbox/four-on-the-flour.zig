const std = @import("std");
const body = @import("body");
const timbre = @import("timbre");
const lightmix = @import("lightmix");
const meters = @import("meters");
const mix = @import("mix");
const perform = @import("perform");

const instruments = struct {
    const T = configs.T;

    /// The procedure for vibrating bodies whose resolved notes are `R`.
    pub fn Procedure(comptime R: type) type {
        return perform.Procedure(T, R, body, .timing);
    }

    const HitNote = lines.Hit.Resolved;

    /// Seconds to frames.
    fn toFrames(seconds: T) usize {
        return @intFromFloat(@round(seconds * @as(T, @floatFromInt(configs.SAMPLE_RATE))));
    }

    /// A generator for the noise of one note, seeded by the body and by where the note starts, so
    /// the waveform of a note depends on nothing else.
    fn seeded(salt: u64, start: usize) std.Random.DefaultPrng {
        return .init(salt ^ @as(u64, start));
    }

    /// A drum sounds for `seconds` unless its volume is zero.
    fn drumLength(note: HitNote) usize {
        const SECONDS: usize = 1;

        return if (note.volume > 0.0) toFrames(SECONDS) else 0;
    }

    /// The kick, with a shorter decay than the default, so it has died away by the end of its 0.55 s.
    const kick_timbre: timbre.Kick(T) = .{ .decay = 0.17 };
    /// The snare with its default settings.
    const snare_timbre: timbre.Snare(T) = .{};
    /// The cymbals; the closed and open hi-hat and the crash are its settings.
    const Cymbal = timbre.Cymbal(T);
    /// The open hi-hat.
    const hihat_timbre = Cymbal.open;

    /// Sounds the kick at the volume of the note.
    fn kickDrumTimble(allocator: std.mem.Allocator, note: HitNote, length: usize, frames: usize) anyerror![]T {
        return kick_timbre.render(allocator, configs.SAMPLE_RATE, configs.CHANNELS, note.volume, length, frames);
    }

    /// Sounds the snare at the volume of the note.
    fn snareDrumTimble(allocator: std.mem.Allocator, note: HitNote, length: usize, frames: usize) anyerror![]T {
        var prng = seeded(0x5a7e, note.timing);
        return snare_timbre.render(allocator, prng.random(), configs.SAMPLE_RATE, configs.CHANNELS, note.volume, length, frames);
    }

    /// Sounds the open hi-hat at the volume of the note.
    fn hihatTimble(allocator: std.mem.Allocator, note: HitNote, length: usize, frames: usize) anyerror![]T {
        var prng = seeded(0x41a7, note.timing);
        return hihat_timbre.render(allocator, prng.random(), configs.SAMPLE_RATE, note.volume, length, frames);
    }

    pub const kick: Procedure(HitNote).Body = .{ .length = drumLength, .timbre = kickDrumTimble };

    pub const snare: Procedure(HitNote).Body = .{ .length = drumLength, .timbre = snareDrumTimble };

    /// An open hi-hat rings until the next hit cuts it, as a hi-hat pedal closes it.
    pub const hihat: Procedure(HitNote).Body = .{ .length = drumLength, .timbre = hihatTimble };

    test {
        std.testing.refAllDecls(@This());
    }
};

const primitives = struct {
    const Timing = struct {
        const Self = @This();

        const Error = error{InvalidPosition};

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

    /// The energy given to a vibrating body. Zero is a rest: the note does not sound.
    const Volume = struct {
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
};

const lines = struct {
    const thin = struct {
        const Timing = meters.Layer(.{ .timing = primitives.Timing });
        const Volume = meters.Layer(.{ .volume = primitives.Volume });
    };

    const Hit = thin.Timing.Zip(thin.Volume);
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

const scores = struct {
    const primitives = struct {
        const timing = struct {
            const Quarter: lines.thin.Timing = @import("./four-on-the-flour/timing-quarter.zon");
            const Backbeat: lines.thin.Timing = @import("./four-on-the-flour/timing-backbeat.zon");
            const Offbeat: lines.thin.Timing = @import("./four-on-the-flour/timing-offbeat.zon");
        };

        const volume = struct {
            const Default: lines.thin.Volume = @import("./four-on-the-flour/volume-default.zon");
        };
    };

    const Scores = struct {
        const Drum = struct {
            kick: lines.Hit,
            snare: lines.Hit,
            hihat: lines.Hit,
        };

        drum: Drum,
    };

    const Section = struct {
        const Self = @This();

        const Drum = struct {
            kick: ?lines.Hit = null,
            snare: ?lines.Hit = null,
            hihat: ?lines.Hit = null,
        };

        /// Length of this section in beats; every part written in it must last exactly this long.
        extent: f64,

        drum: Drum = .{},

        /// Places `all_sections` one after another and gives the score of each vibrating body.
        /// Returns `error.MismatchedExtent` when a part does not last as long as its section.
        pub fn concat(allocator: std.mem.Allocator, all_sections: []const Self) !Scores {
            var result: Scores = undefined;

            // Walks Scores.<group>.<part>, so Section must have the same names as Scores.
            inline for (@typeInfo(Scores).@"struct".fields) |group| {
                inline for (@typeInfo(group.type).@"struct".fields) |part| {
                    const L = part.type;
                    const parts = try allocator.alloc(L, all_sections.len);
                    for (all_sections, parts) |section, *slot| {
                        const written = @field(@field(section, group.name), part.name);
                        slot.* = written orelse L.empty(section.extent);
                        if (slot.extent != section.extent) return error.MismatchedExtent;
                    }
                    @field(@field(result, group.name), part.name) = try L.join(allocator, parts);
                }
            }

            return result;
        }
    };

    const MusicPart = enum {
        introduction,
    };

    pub fn compose(allocator: std.mem.Allocator) !Scores {
        var all: std.ArrayList(Section) = .empty;
        inline for (@typeInfo(MusicPart).@"enum".fields) |field| {
            const part: MusicPart = @enumFromInt(field.value);
            try all.appendSlice(allocator, try sections(allocator, part));
        }

        return Section.concat(allocator, all.items);
    }

    fn sections(allocator: std.mem.Allocator, part: MusicPart) ![]const Section {
        return switch (part) {
            .introduction => introduction(allocator),
        };
    }

    /// The drum parts of a four-on-the-floor. It names only `lines.Hit`, so the function below
    /// does not depend on `Section`.
    const FourOnTheFloor = struct {
        kick: lines.Hit,
        snare: lines.Hit,
        hihat: lines.Hit,
    };

    /// Writes `bars` bars of four-on-the-floor: the kick sounds on every beat, the snare on the
    /// second and fourth beats, and the open hi-hat on the off-beats, halfway between the beats.
    /// All parts last `bars` bars, so `kick.extent` is the length of the section they are written
    /// in.
    fn fourOnTheFloor(allocator: std.mem.Allocator, bars: usize) !FourOnTheFloor {
        // One bar of each, pairing its timings with the one shared volume. `primitives` alone is
        // ambiguous here, as the file has another one, so it is reached through `scores`.
        const kick_bar = try scores.primitives.timing.Quarter.zip(allocator, scores.primitives.volume.Default);
        const snare_bar = try scores.primitives.timing.Backbeat.zip(allocator, scores.primitives.volume.Default);
        const hihat_bar = try scores.primitives.timing.Offbeat.zip(allocator, scores.primitives.volume.Default);

        return .{
            .kick = try kick_bar.repeat(allocator, bars),
            .snare = try snare_bar.repeat(allocator, bars),
            .hihat = try hihat_bar.repeat(allocator, bars),
        };
    }

    /// Four bars of four-on-the-floor.
    fn introduction(allocator: std.mem.Allocator) ![]const Section {
        const drum = try fourOnTheFloor(allocator, 4);

        return allocator.dupe(Section, &.{
            .{
                .extent = drum.kick.extent,
                .drum = .{ .kick = drum.kick, .snare = drum.snare, .hihat = drum.hihat },
            },
        });
    }
};

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

/// Level of the hi-hat bus; the hi-hat sits behind the kick and the snare.
const HIHAT_GAIN: configs.T = 0.15;

fn render(allocator: std.mem.Allocator) ![]configs.T {
    const written: scores.Scores = try scores.compose(allocator);

    var mixer: mix.Mixer(configs.T) = try .init(allocator, configs.CHANNELS);
    defer mixer.deinit();

    try play(lines.Hit, allocator, written.drum.kick, instruments.kick, mixer.bus(.{ .gain = 1.0 }));
    try play(lines.Hit, allocator, written.drum.snare, instruments.snare, mixer.bus(.{ .gain = 0.75 }));
    try play(lines.Hit, allocator, written.drum.hihat, instruments.hihat, mixer.bus(.{ .gain = HIHAT_GAIN }));

    // The piece lasts as long as its timeline; a ringing crash may run past it.
    const end = try max(scores.Scores, written, context);
    const samples = try mixer.finish(end);
    mix.normalize(configs.T, samples, configs.PEAK);
    return samples;
}

fn max(comptime S: type, written: S, ctx: meters.Context) !primitives.Timing.ResolveT {
    // f64 is the meters.Layer(...).extent type
    const ExtentT = f64;
    var maxExtent: ExtentT = 0.0;

    inline for (@typeInfo(S).@"struct".fields) |group| {
        inline for (@typeInfo(group.type).@"struct".fields) |part| {
            const extent: ExtentT = @field(@field(@field(written, group.name), part.name), "extent");

            if (maxExtent < extent)
                maxExtent = extent;
        }
    }

    const timing: primitives.Timing = .{ .beat = maxExtent };
    return try timing.resolve(ctx);
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
