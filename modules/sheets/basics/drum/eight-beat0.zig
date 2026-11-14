pub fn Gen(comptime L: type) type {
    return struct {
        pub const Kicks: L.Hit = @import("./eight-beat0/kicks.zon");
        pub const Snares: L.Hit = @import("./eight-beat0/snares.zon");
    };
}
