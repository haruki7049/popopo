const std = @import("std");

pub fn inner(comptime L: type) type {
    return struct {
        pub const Error = std.mem.Allocator.Error;

        pub const R = struct {
            pub const Base = @import("./b/base.zig").inner(L);
            pub const Drum = @import("./b/drum.zig").inner(L);
            pub const Melody = @import("./b/melody.zig").inner(L);

            base: Base,
            drum: Drum,
            melody: Melody,

            pub fn init(allocator: std.mem.Allocator) Error!R {
                const base: Base = try Base.init(allocator);
                const drum: Drum = try Drum.init(allocator);
                const melody: Melody = try Melody.init(allocator);

                return .{
                    .base = base,
                    .drum = drum,
                    .melody = melody,
                };
            }

            pub fn deinit(r: R, allocator: std.mem.Allocator) void {
                r.base.deinit(allocator);
                r.drum.deinit(allocator);
                r.melody.deinit(allocator);
            }
        };

        pub fn init(allocator: std.mem.Allocator) Error!R {
            return R.init(allocator);
        }

        pub fn deinit(allocator: std.mem.Allocator) void {
            R.deinit(allocator);
        }
    };
}
