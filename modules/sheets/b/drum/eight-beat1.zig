pub fn Gen(comptime L: type) type {
    return struct {
        pub const Kicks: L.Hit = @import("./eight-beat1/kicks.zon");
    };
}
