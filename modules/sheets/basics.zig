pub fn Gen(comptime L: type) type {
    return struct {
        pub const Base = @import("./basics/base.zig").Gen(L);
        pub const Drum = @import("./basics/drum.zig").Gen(L);
    };
}
