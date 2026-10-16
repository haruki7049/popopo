//! The procedure for one vibrating body, and the instrument-set type the user fills in.

const std = @import("std");

/// Rejects, at compile time, a rule of a vibrating body that does not have the shape the procedure
/// uses.
fn assertRule(comptime B: type) void {
    inline for (.{ "Strike", "Cut", "decide" }) |name| {
        if (!@hasDecl(B, name)) @compileError(@typeName(B) ++ " is not a rule of a vibrating body: it has no `" ++ name ++ "`");
    }
    inline for (.{ "start", "length" }) |name| {
        if (!@hasField(B.Strike, name)) @compileError(@typeName(B) ++ ".Strike has no field `" ++ name ++ "`");
    }
    inline for (.{ "frames", "fade_start", "fade_frames" }) |name| {
        if (!@hasField(B.Cut, name)) @compileError(@typeName(B) ++ ".Cut has no field `" ++ name ++ "`");
    }
}

/// Returns the procedure for vibrating bodies whose resolved notes are `R`, making samples of type
/// `T`.
///
/// - `B` is the rule of a vibrating body. It provides `Strike` (`start`, `length`), `Cut`
///   (`frames`, `fade_start`, `fade_frames`) and
///   `decide(allocator, []const Strike, sample_rate) ![]Cut`, one cut per strike in order.
/// - `start` names the field of `R` that holds the frame position of a note.
pub fn inner(comptime T: type, comptime R: type, comptime B: type, comptime start: std.meta.FieldEnum(R)) type {
    comptime assertRule(B);

    return struct {
        /// One vibrating body of the instrument set, filled in by the user. Which notes share it
        /// is decided by which score is handed to it in `run`.
        pub const Body = struct {
            /// How long a note sounds if nothing cuts it, in frames. Zero: the note does not sound.
            length: *const fn (note: R) usize,
            /// The timbre: returns the first `frames` frames (mono) of `note`, which sounds `length`
            /// frames if nothing cuts it; `frames` is at most `length`. The fade of the timbre, how
            /// the sound itself dies away, is part of it. The samples are allocated with `allocator`
            /// and owned by the caller.
            timbre: *const fn (allocator: std.mem.Allocator, note: R, length: usize, frames: usize) anyerror![]T,
        };

        /// Errors of `run` besides those of the allocator, the timbre and the sink.
        pub const Error = error{
            /// The timbre returned a number of frames other than the one it was asked for.
            WrongTimbreLength,
        };

        /// Turns the resolved notes of one vibrating body into waveforms:
        ///
        /// 1. asks `body` how long each note sounds if nothing cuts it,
        /// 2. hands the starts and lengths to the rule `B`, which decides the approximation fade,
        /// 3. asks the timbre of `body` for the frames that actually sound,
        /// 4. passes each waveform on to `sink.add(samples, start, fade_start, fade_frames)`, which
        ///    applies the fade, places and mixes it, and must copy the samples.
        ///
        /// The procedure never changes a sample.
        pub fn run(allocator: std.mem.Allocator, body: Body, notes: []const R, sample_rate: u32, sink: anytype) !void {
            const strikes = try allocator.alloc(B.Strike, notes.len);
            defer allocator.free(strikes);
            for (notes, strikes) |note, *strike| {
                strike.* = .{ .start = @field(note, @tagName(start)), .length = body.length(note) };
            }

            const cuts = try B.decide(allocator, strikes, sample_rate);
            defer allocator.free(cuts);

            for (notes, strikes, cuts) |note, strike, cut| {
                if (cut.frames == 0) continue;

                const samples = try body.timbre(allocator, note, strike.length, cut.frames);
                defer allocator.free(samples);
                if (samples.len != cut.frames) return error.WrongTimbreLength;

                try sink.add(samples, strike.start, cut.fade_start, cut.fade_frames);
            }
        }
    };
}

// A rule, notes, a body and a sink written the way the user's repository connects them.

/// Cuts a note where the next one starts, with no fade. Notes must be in order of start.
const TestRule = struct {
    pub const Strike = struct { start: usize, length: usize };
    pub const Cut = struct { frames: usize, fade_start: usize, fade_frames: usize };

    pub fn decide(allocator: std.mem.Allocator, strikes: []const Strike, sample_rate: u32) ![]Cut {
        _ = sample_rate;
        const cuts = try allocator.alloc(Cut, strikes.len);
        for (strikes, cuts, 0..) |strike, *cut, i| {
            var frames = strike.length;
            if (i + 1 < strikes.len) frames = @min(frames, strikes[i + 1].start - strike.start);
            cut.* = .{ .frames = frames, .fade_start = @min(frames, 2), .fade_frames = frames - @min(frames, 2) };
        }
        return cuts;
    }
};

const TestNote = struct { at: usize, level: f64 };

const TestSink = struct {
    const Call = struct { first: f64, len: usize, start: usize, fade_start: usize, fade_frames: usize };

    calls: [8]Call = undefined,
    count: usize = 0,

    pub fn add(self: *TestSink, samples: []const f64, start: usize, fade_start: usize, fade_frames: usize) !void {
        self.calls[self.count] = .{ .first = samples[0], .len = samples.len, .start = start, .fade_start = fade_start, .fade_frames = fade_frames };
        self.count += 1;
    }
};

fn testLength(note: TestNote) usize {
    return if (note.level == 0.0) 0 else 10;
}

/// Fills `frames` frames with the level of the note, plus the full length in the first sample.
fn testTimbre(allocator: std.mem.Allocator, note: TestNote, length: usize, frames: usize) anyerror![]f64 {
    const samples = try allocator.alloc(f64, frames);
    @memset(samples, note.level);
    samples[0] += @floatFromInt(length);
    return samples;
}

fn shortTimbre(allocator: std.mem.Allocator, note: TestNote, length: usize, frames: usize) anyerror![]f64 {
    _ = note;
    _ = length;
    return allocator.alloc(f64, frames - 1);
}

const TestProcedure = inner(f64, TestNote, TestRule, .at);

test "run asks the body, applies the rule and passes each waveform on" {
    var sink: TestSink = .{};
    try TestProcedure.run(std.testing.allocator, .{ .length = testLength, .timbre = testTimbre }, &.{
        .{ .at = 0, .level = 0.5 },
        .{ .at = 4, .level = 0.25 },
    }, 44100, &sink);

    try std.testing.expectEqual(@as(usize, 2), sink.count);
    // Cut by the next note at frame 4: 4 frames, the timbre still knows the full length of 10.
    try std.testing.expectEqual(TestSink.Call{ .first = 10.5, .len = 4, .start = 0, .fade_start = 2, .fade_frames = 2 }, sink.calls[0]);
    try std.testing.expectEqual(TestSink.Call{ .first = 10.25, .len = 10, .start = 4, .fade_start = 2, .fade_frames = 8 }, sink.calls[1]);
}

test "a note that does not sound is not passed on" {
    var sink: TestSink = .{};
    try TestProcedure.run(std.testing.allocator, .{ .length = testLength, .timbre = testTimbre }, &.{
        .{ .at = 0, .level = 0.0 },
    }, 44100, &sink);
    try std.testing.expectEqual(@as(usize, 0), sink.count);
}

test "a timbre that returns the wrong number of frames is an error" {
    var sink: TestSink = .{};
    try std.testing.expectError(error.WrongTimbreLength, TestProcedure.run(std.testing.allocator, .{ .length = testLength, .timbre = shortTimbre }, &.{
        .{ .at = 0, .level = 1.0 },
    }, 44100, &sink));
}

test {
    std.testing.refAllDecls(@This());
}
