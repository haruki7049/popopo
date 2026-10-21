pub fn Gen(comptime L: type) type {
    return struct {
        pub const EightBeat0 = @import("./drums/eight-beat0.zig").Gen(L);
    };
}
