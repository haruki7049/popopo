pub fn Gen(comptime L: type) type {
    return struct {
        pub const Melody = @import("./a/melody.zig").Gen(L);
    };
}
