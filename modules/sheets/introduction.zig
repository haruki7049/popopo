pub fn Gen(comptime L: type) type {
    return struct {
        pub const Drums = @import("./introduction/drums.zig").Gen(L);
        pub const Base = @import("./introduction/base.zig").Gen(L);
    };
}
