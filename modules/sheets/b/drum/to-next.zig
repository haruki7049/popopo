pub fn Gen(comptime L: type) type {
    return struct {
        pub const Kicks: L.Hit = @import("./to-next/kicks.zon");
        pub const Snares: L.Hit = @import("./to-next/snares.zon");
    };
}
