pub fn Gen(comptime L: type) type {
    return struct {
        pub const EightBeat1 = @import("./drum/eight-beat1.zig").Gen(L);
    };
}
