const std = @import("std");

pub fn inner(comptime L: type) type {
    return struct {
        pub const Error = std.mem.Allocator.Error;

        pub const R = struct {
            without_third: L.Guitar,

            pub fn init(allocator: std.mem.Allocator) Error!R {
                var r: R = undefined;
                r.without_third = try init_without_third(allocator);

                return R;
            }

            pub fn deinit(r: R, allocator: std.mem.Allocator) void {
                try deinit_without_third(r.without_third, allocator);
            }
        };

        pub fn init(allocator: std.mem.Allocator) Error!R {
            return R.init(allocator);
        }

        pub fn deinit(allocator: std.mem.Allocator) void {
            R.deinit(allocator);
        }

        // --- Internal functions ---
        fn init_without_third(allocator: std.mem.Allocator) Error!L.Guitar {
            const NOTES_LENGTH: usize = 4;

            var string: L.String = L.String.empty(0.0);
            string.extent = 4.0;

            // Notations
            const half_duration: L.thin.Duration = .notate(&.{
                .{ .beats = 0.5 },
            });
            const mute: L.thin.Mute = .notate(&.{
                .{ .mute = 0.7 },
            });
            const pitch: L.thin.Pitch = .notate(&.{
                .{ .name = .{ .code = .a, .octave = 1 } },
            });
            const volume: L.thin.Volume = .notate(&.{
                .{ .value = 1.0 },
            });
            const timings: L.thin.Timing = .notate(&.{
                // bar 0
                .{ .bar = 0, .beat = 0.0 },
                .{ .bar = 0, .beat = 0.5 },
                .{ .bar = 0, .beat = 2.0 },
                .{ .bar = 0, .beat = 2.5 },
            });

            if (timings.columns.timing.len != NOTES_LENGTH)
                unreachable;

            try string.zip(allocator, &.{timings}); // Zip timings notations. It must be here because it has four but others are one
            inline for (.{ half_duration, mute, pitch, volume }) |unit| {
                const units = try unit.repeat(allocator, NOTES_LENGTH);
                try string.zip(allocator, &.{units});
            }

            return string;
        }

        fn deinit_without_third(without_third: L.Guitar, allocator: std.mem.Allocator) Error!void {}
    };
}
