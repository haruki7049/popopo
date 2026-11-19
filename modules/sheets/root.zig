pub fn Gen(comptime L: type) type {
    return struct {
        pub const Timing = @import("./timing.zig").Gen(L);
        pub const Volume = @import("./volume.zig").Gen(L);
    };
}
