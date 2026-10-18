pub fn Gen(comptime L: type) type {
    return struct {
        pub const EightBeat = @import("./drums/eight-beat.zig").Gen(L);
    };
}
