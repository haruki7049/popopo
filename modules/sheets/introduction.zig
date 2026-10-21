pub fn Gen(comptime L: type) type {
    return struct {
        pub const Melody = @import("./introduction/melody.zig").Gen(L);
    };
}
