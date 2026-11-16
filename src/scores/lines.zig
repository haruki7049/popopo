//! The layer type of each kind of vibrating body: which primitives one line of score is made of.

const std = @import("std");
const meters = @import("meters");
const primitives = @import("../primitives.zig");

/// The timings alone, written apart from the volume so that one volume serves every timing.
pub const Timing = meters.Layer(.{ .timing = primitives.Timing });

/// The volume alone.
pub const Volume = meters.Layer(.{ .volume = primitives.Volume });

/// Score of a drum: kick, snare or hi-hat. A timing layer zipped with a volume layer.
pub const Hit = Timing.Zip(Volume);

/// Plays `layer` `times` times as fast: its extent and the position of each element become `1 / times`
/// of what they were, so a layer of one bar lasts a bar over `times`. `layer` is any layer with a
/// timing column, such as `Timing` or `Hit`. Repeat the result `times` times to fill the bar again.
/// Returns `error.InvalidFactor` for `times` that is not finite and greater than zero. The caller owns
/// the returned slices.
pub fn speed(allocator: std.mem.Allocator, layer: anytype, times: f64) !@TypeOf(layer) {
    const factor = 1.0 / times;
    const stretched = try layer.stretch(allocator, factor);

    return stretched.map(allocator, .timing, primitives.Timing.Stretch{ .factor = factor });
}

// 120 BPM, 44100 Hz: a beat is 22050 frames.
const test_context: meters.Context = .{ .bpm = 120, .sample_rate = 44100 };

/// A gallop of one bar: the first beat, and the third and fourth beats.
const gallop: Timing = .{
    .columns = .{ .timing = &.{
        .{ .bar = 0, .beat = 0.0 },
        .{ .bar = 0, .beat = 2.0 },
        .{ .bar = 0, .beat = 3.0 },
    } },
    .extent = 4.0,
};

test "speed 2.0 moves every timing half as far, and the layer lasts half as long" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const quick = try speed(allocator, gallop, 2.0);
    try std.testing.expectEqual(@as(f64, 2.0), quick.extent);

    const beats = [_]f64{ 0.0, 1.0, 1.5 };
    for (quick.columns.timing, beats) |timing, beat| {
        try std.testing.expectEqual(@as(usize, 0), timing.bar);
        try std.testing.expectEqual(beat, timing.beat);
    }
}

test "speed, repeated, plays the same pattern twice in a bar" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const bar = try (try speed(allocator, gallop, 2.0)).repeat(allocator, 2);
    try std.testing.expectEqual(@as(f64, 4.0), bar.extent);

    // Beats 0, 1, 1.5, 2, 3, 3.5 at 22050 frames a beat.
    const resolved = try bar.resolve(allocator, test_context);
    const frames = [_]usize{ 0, 22050, 33075, 44100, 66150, 77175 };
    try std.testing.expectEqual(frames.len, resolved.len);
    for (resolved, frames) |note, frame| try std.testing.expectEqual(frame, note.timing);
}

test "speed 1.0 leaves the layer as it was, and it also works on a Hit" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const same = try speed(allocator, gallop, 1.0);
    try std.testing.expectEqual(gallop.extent, same.extent);
    for (same.columns.timing, gallop.columns.timing) |a, b| {
        try std.testing.expectEqual(b.bar, a.bar);
        try std.testing.expectEqual(b.beat, a.beat);
    }

    const volume: Volume = .{ .columns = .{ .volume = &.{.{ .value = 1.0 }} } };
    const hit = try gallop.zip(allocator, volume);
    const quick = try speed(allocator, hit, 2.0);
    try std.testing.expectEqual(@as(f64, 2.0), quick.extent);
    try std.testing.expectEqual(@as(usize, 3), quick.count());
}

test "speed rejects a factor that is not finite and greater than zero" {
    for ([_]f64{ 0.0, -2.0, std.math.nan(f64), std.math.inf(f64) }) |times| {
        // `1 / times` is 0 or infinite or NaN or negative, which `stretch` does not accept.
        try std.testing.expectError(error.InvalidFactor, speed(std.testing.allocator, gallop, times));
    }
}

test {
    std.testing.refAllDecls(@This());
}
