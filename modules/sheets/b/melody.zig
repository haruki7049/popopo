pub fn Gen(comptime L: type) type {
    return struct {
        /// The first two bars, which the main phrase and the phrase to the next part share.
        pub const Opening: L.Guitar = @import("./melody/opening.zon");
        /// The last two bars of the main phrase.
        pub const MainEnding: L.Guitar = @import("./melody/main-ending.zon");
        /// The last two bars of the phrase to the next part.
        pub const ToNextEnding: L.Guitar = @import("./melody/to-next-ending.zon");
    };
}
