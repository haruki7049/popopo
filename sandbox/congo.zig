const std = @import("std");
const body = @import("body");
const timbre = @import("timbre");
const lightmix = @import("lightmix");
const meters = @import("meters");
const mix = @import("mix");
const sheets = @import("sheets");
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
    /// The closed hi-hat.
    const hihat_timbre = Cymbal.closed;

    /// Sounds the kick at the volume of the note.
    fn kickDrumTimble(allocator: std.mem.Allocator, note: HitNote, length: usize, frames: usize) anyerror![]T {
        return kick_timbre.render(allocator, configs.SAMPLE_RATE, configs.CHANNELS, note.volume, length, frames);
    }

    /// Sounds the snare at the volume of the note.
    fn snareDrumTimble(allocator: std.mem.Allocator, note: HitNote, length: usize, frames: usize) anyerror![]T {
        var prng = seeded(0x5a7e, note.timing);
        return snare_timbre.render(allocator, prng.random(), configs.SAMPLE_RATE, configs.CHANNELS, note.volume, length, frames);
    }

    /// A closed hi-hat sounds for `SECONDS` unless its volume is zero; it has died away by then and
    /// the next hit comes later, so it never cuts the previous one.
    fn hihatLength(note: HitNote) usize {
        const SECONDS: T = 0.15;

        return if (note.volume > 0.0) toFrames(SECONDS) else 0;
    }

    /// Sounds the closed hi-hat at the volume of the note.
    fn hihatTimble(allocator: std.mem.Allocator, note: HitNote, length: usize, frames: usize) anyerror![]T {
        var prng = seeded(0x41a7, note.timing);
        return hihat_timbre.render(allocator, prng.random(), configs.SAMPLE_RATE, note.volume, length, frames);
    }

    pub const kick: Procedure(HitNote).Body = .{ .length = drumLength, .timbre = kickDrumTimble };

    pub const snare: Procedure(HitNote).Body = .{ .length = drumLength, .timbre = snareDrumTimble };

    pub const hihat: Procedure(HitNote).Body = .{ .length = hihatLength, .timbre = hihatTimble };

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

        /// A transform for `Layer.map` that moves every timing to `factor` times its position, counted
        /// from the start of the layer: 0.5 puts it twice as near, as if it were played twice as fast.
        /// It goes with `Layer.stretch`, which scales the extent and the origins in the same way.
        pub const Stretch = struct {
            /// What every position is multiplied by; must be finite and greater than zero.
            factor: f64,
            /// Beats in a bar, which positions are counted in: a bar and a beat make one position.
            beats_per_bar: f64 = @floatFromInt(configs.BEATS_PER_BAR),

            /// The timing at `factor` times the position of `timing`, written again as a bar and a
            /// beat. Returns `error.InvalidPosition` for a factor that is not finite and greater than
            /// zero, and for a timing whose beat is NaN, negative or infinite.
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
    /// The timings alone, written apart from the volume so that one volume serves every timing.
    pub const Timing = meters.Layer(.{ .timing = primitives.Timing });

    /// The volume alone.
    pub const Volume = meters.Layer(.{ .volume = primitives.Volume });

    /// Score of a drum: kick, snare or hi-hat. A timing layer zipped with a volume layer.
    pub const Hit = Timing.Zip(Volume);

    /// Plays `layer` `times` times as fast: its extent and the position of each element become
    /// `1 / times` of what they were, so a layer of one bar lasts a bar over `times`. `layer` is any
    /// layer with a timing column, such as `Timing` or `Hit`. Repeat the result `times` times to fill
    /// the bar again. Returns `error.InvalidFactor` for `times` that is not finite and greater than
    /// zero. The caller owns the returned slices.
    pub fn speed(allocator: std.mem.Allocator, layer: anytype, times: f64) !@TypeOf(layer) {
        const factor = 1.0 / times;
        const stretched = try layer.stretch(allocator, factor);

        return stretched.map(allocator, .timing, primitives.Timing.Stretch{ .factor = factor });
    }
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
            inline for (@typeInfo(Scores).@"struct".field_names, @typeInfo(Scores).@"struct".field_types) |group_name, Group| {
                inline for (@typeInfo(Group).@"struct".field_names, @typeInfo(Group).@"struct".field_types) |part_name, L| {
                    const parts = try allocator.alloc(L, all_sections.len);
                    for (all_sections, parts) |section, *slot| {
                        const written = @field(@field(section, group_name), part_name);
                        slot.* = written orelse L.empty(section.extent);
                        if (slot.extent != section.extent) return error.MismatchedExtent;
                    }
                    @field(@field(result, group_name), part_name) = try L.join(allocator, parts);
                }
            }

            return result;
        }
    };

    const MusicPart = enum {
        congo,
    };

    pub fn compose(allocator: std.mem.Allocator) !Scores {
        var all: std.ArrayList(Section) = .empty;
        inline for (std.enums.values(MusicPart)) |part| {
            try all.appendSlice(allocator, try sections(allocator, part));
        }

        return Section.concat(allocator, all.items);
    }

    fn sections(allocator: std.mem.Allocator, part: MusicPart) ![]const Section {
        return switch (part) {
            .congo => congo(allocator),
        };
    }

    /// One bar of drums, written in eighth notes as `xwwxxw.w` (`x`: kick, `.`: snare, `w`: rest).
    fn congo(allocator: std.mem.Allocator) ![]const Section {
        const s = sheets.Gen(lines);

        // The backbeat at double speed lasts two beats and sounds at 0.5 and 1.5; twice of it fills
        // a bar with 0.5, 1.5, 2.5 and 3.5.
        const double_speed_backbeat: lines.Timing = try lines.speed(allocator, s.Timing.Backbeat, 2.0);
        const offbeats: lines.Timing = try double_speed_backbeat.repeat(allocator, 2);

        // The first and the third beat, with the second offbeat, at 1.5 beats, laid over them.
        const second_offbeat: lines.Timing = try offbeats.pick(allocator, &.{1});
        const kick_timing: lines.Timing = try s.Timing.Half.merge(allocator, second_offbeat);

        // The fourth beat alone: the second element of the backbeat.
        const snare_timing: lines.Timing = try s.Timing.Backbeat.pick(allocator, &.{1});

        return allocator.dupe(Section, &.{
            .{
                .extent = 4.0,
                .drum = .{
                    .kick = try kick_timing.zip(allocator, s.Volume.Default),
                    .snare = try snare_timing.zip(allocator, s.Volume.Default),
                },
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

    inline for (@typeInfo(S).@"struct".field_names, @typeInfo(S).@"struct".field_types) |group_name, Group| {
        inline for (@typeInfo(Group).@"struct".field_names, @typeInfo(Group).@"struct".field_types) |part_name, _| {
            const extent: ExtentT = @field(@field(@field(written, group_name), part_name), "extent");

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
