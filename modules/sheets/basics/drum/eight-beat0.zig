pub fn Gen(comptime L: type) type {
    return struct {
        pub const KicksWithRests: L.Hit = @import("./eight-beat0/kicks-with-rests.zon");
        pub const Kicks: L.Hit = @import("./eight-beat0/kicks.zon");
        pub const Snares: L.Hit = @import("./eight-beat0/snares.zon");
    };
}
