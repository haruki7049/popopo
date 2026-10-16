pub fn Gen(comptime L: type) type {
    return struct {
        pub const SingleSound: L.Guitar = @import("./sheets/single-sound.zon");
    };
}
