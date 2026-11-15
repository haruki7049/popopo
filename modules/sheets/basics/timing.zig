pub fn Gen(comptime L: type) type {
    return struct {
        /// The first and the third beat of a bar.
        pub const Half: L.Timing = @import("./timing/half.zon");
        /// The second and the fourth beat of a bar.
        pub const Backbeat: L.Timing = @import("./timing/backbeat.zon");
        /// Every eighth note of a bar.
        pub const Eighth: L.Timing = @import("./timing/eighth.zon");
    };
}
