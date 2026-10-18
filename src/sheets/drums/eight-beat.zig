pub fn Gen(comptime L: type) type {
    return struct {
        pub const Kicks: L.Hit = @import("./eight-beat/kicks.zon");
        pub const Snares: L.Hit = @import("./eight-beat/snares.zon");
        pub const HiHats: L.Hit = @import("./eight-beat/hi-hats.zon");
    };
}
