pub fn Gen(comptime L: type) type {
    return struct {
        pub const Drums = @import("./sheets/drums.zig").Gen(L);
    };
}
