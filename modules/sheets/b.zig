pub fn Gen(comptime L: type) type {
    return struct {
        pub const Base = @import("./b/base.zig").Gen(L);
        pub const Drum = @import("./b/drum.zig").Gen(L);
        pub const Melody = @import("./b/melody.zig").Gen(L);
    };
}
