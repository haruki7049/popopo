pub fn Gen(comptime L: type) type {
    return struct {
        pub const Timing = @import("./basics/timing.zig").Gen(L);
        pub const Volume = @import("./basics/volume.zig").Gen(L);
    };
}
