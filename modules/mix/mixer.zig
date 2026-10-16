//! Places waveforms one at a time, applies the approximation fade, and mixes them by addition.

const std = @import("std");

/// Returns a mixer type for samples of type `T`.
pub fn inner(comptime T: type) type {
    return struct {
        const Self = @This();

        /// Allocator of `samples`.
        allocator: std.mem.Allocator,
        /// Channels of the mix: 1 (mono) or 2 (stereo, left first).
        channels: u16,
        /// Interleaved samples mixed so far.
        samples: std.ArrayList(T) = .empty,

        /// Errors of `init`.
        pub const InitError = error{
            /// The mixer handles mono and stereo only.
            UnsupportedChannels,
        };

        /// Creates an empty mix of `channels` channels.
        pub fn init(allocator: std.mem.Allocator, channels: u16) InitError!Self {
            if (channels != 1 and channels != 2) return error.UnsupportedChannels;
            return .{ .allocator = allocator, .channels = channels };
        }

        /// Frees the samples mixed so far.
        pub fn deinit(self: *Self) void {
            self.samples.deinit(self.allocator);
        }

        /// Number of frames mixed so far.
        pub fn frames(self: Self) usize {
            return self.samples.items.len / self.channels;
        }

        /// A channel strip: every waveform added through it gets the same gain and pan.
        pub const Bus = struct {
            /// The mix the waveforms are added to.
            mixer: *Self,
            /// Linear gain.
            gain: T,
            /// Stereo position from -1 (left) through 0 (center) to 1 (right), with constant power.
            /// Ignored in mono.
            pan: T,

            /// Options of `bus`.
            pub const Options = struct {
                /// Linear gain; 1 leaves the level as it is.
                gain: T = 1.0,
                /// Stereo position from -1 (left) to 1 (right); 0 is the center.
                pan: T = 0.0,
            };

            /// Places one mono waveform at frame `start` and mixes it in. Over the `fade_frames`
            /// frames from `fade_start` the approximation fade is applied, an equal-power curve
            /// (`cos`) that reaches zero on its last frame; frames after the fade are dropped. With
            /// `fade_frames` zero the whole waveform is placed as it is. The samples are copied.
            pub fn add(self: Bus, samples: []const T, start: usize, fade_start: usize, fade_frames: usize) std.mem.Allocator.Error!void {
                const mixer = self.mixer;
                const length = if (fade_frames > 0) @min(samples.len, fade_start + fade_frames) else samples.len;

                const needed = (start + length) * mixer.channels;
                if (mixer.samples.items.len < needed) {
                    try mixer.samples.appendNTimes(mixer.allocator, 0, needed - mixer.samples.items.len);
                }

                const pan = std.math.clamp(self.pan, -1.0, 1.0);
                const angle = (pan + 1.0) * (std.math.pi / 4.0);
                const left = self.gain * @cos(angle);
                const right = self.gain * @sin(angle);

                const out = mixer.samples.items;
                for (samples[0..length], 0..) |sample, i| {
                    const value = sample * fadeGain(i, fade_start, fade_frames);
                    const frame = (start + i) * mixer.channels;
                    if (mixer.channels == 1) {
                        out[frame] += value * self.gain;
                    } else {
                        out[frame] += value * left;
                        out[frame + 1] += value * right;
                    }
                }
            }
        };

        /// Returns a channel strip of this mixer.
        pub fn bus(self: *Self, options: Bus.Options) Bus {
            return .{ .mixer = self, .gain = options.gain, .pan = options.pan };
        }

        /// Returns the mix as interleaved samples, padded with silence to at least `length` frames,
        /// and leaves the mixer empty. The caller owns the returned slice.
        pub fn finish(self: *Self, length: usize) std.mem.Allocator.Error![]T {
            const needed = length * self.channels;
            if (self.samples.items.len < needed) {
                try self.samples.appendNTimes(self.allocator, 0, needed - self.samples.items.len);
            }
            return self.samples.toOwnedSlice(self.allocator);
        }

        /// Gain of the approximation fade at frame `i` of a waveform.
        fn fadeGain(i: usize, fade_start: usize, fade_frames: usize) T {
            if (fade_frames == 0 or i < fade_start) return 1.0;
            const progress = @as(T, @floatFromInt(i - fade_start + 1)) / @as(T, @floatFromInt(fade_frames));
            return @cos(@min(progress, 1.0) * (std.math.pi / 2.0));
        }
    };
}

test "a waveform is placed at its start with constant-power center pan" {
    const allocator = std.testing.allocator;
    var mixer = try inner(f64).init(allocator, 2);
    defer mixer.deinit();

    try mixer.bus(.{}).add(&.{ 1.0, 0.5 }, 2, 2, 0);
    try std.testing.expectEqual(@as(usize, 4), mixer.frames());

    const half = @sqrt(0.5);
    const expected = [_]f64{ 0, 0, 0, 0, half, half, 0.5 * half, 0.5 * half };
    for (expected, mixer.samples.items) |e, a| try std.testing.expectApproxEqAbs(e, a, 1e-12);
}

test "hard pan sends a waveform to one side" {
    const allocator = std.testing.allocator;
    var mixer = try inner(f64).init(allocator, 2);
    defer mixer.deinit();

    try mixer.bus(.{ .pan = -1.0, .gain = 0.5 }).add(&.{1.0}, 0, 1, 0);
    try std.testing.expectApproxEqAbs(@as(f64, 0.5), mixer.samples.items[0], 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), mixer.samples.items[1], 1e-12);
}

test "the approximation fade reaches zero and drops the frames after it" {
    const allocator = std.testing.allocator;
    var mixer = try inner(f64).init(allocator, 1);
    defer mixer.deinit();

    // Fade over frames 2 and 3; frame 4 is dropped.
    try mixer.bus(.{}).add(&.{ 1.0, 1.0, 1.0, 1.0, 1.0 }, 0, 2, 2);
    try std.testing.expectEqual(@as(usize, 4), mixer.frames());
    try std.testing.expectEqual(@as(f64, 1.0), mixer.samples.items[1]);
    try std.testing.expectApproxEqAbs(@cos(0.5 * std.math.pi / 2.0), mixer.samples.items[2], 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), mixer.samples.items[3], 1e-12);
}

test "waveforms are mixed by addition" {
    const allocator = std.testing.allocator;
    var mixer = try inner(f64).init(allocator, 1);
    defer mixer.deinit();

    try mixer.bus(.{}).add(&.{ 0.25, 0.25 }, 0, 2, 0);
    try mixer.bus(.{ .gain = 2.0 }).add(&.{ 0.25, 0.25 }, 1, 2, 0);
    try std.testing.expectEqualSlices(f64, &.{ 0.25, 0.75, 0.5 }, mixer.samples.items);
}

test "finish pads the mix with silence" {
    const allocator = std.testing.allocator;
    var mixer = try inner(f64).init(allocator, 2);
    defer mixer.deinit();

    try mixer.bus(.{}).add(&.{1.0}, 0, 1, 0);
    const samples = try mixer.finish(3);
    defer allocator.free(samples);
    try std.testing.expectEqual(@as(usize, 6), samples.len);
    try std.testing.expectEqual(@as(f64, 0.0), samples[5]);
}

test "init accepts mono and stereo only" {
    try std.testing.expectError(error.UnsupportedChannels, inner(f64).init(std.testing.allocator, 0));
    try std.testing.expectError(error.UnsupportedChannels, inner(f64).init(std.testing.allocator, 6));
}

test {
    std.testing.refAllDecls(@This());
}
