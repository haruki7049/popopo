pub fn Gen(comptime L: type) type {
    return struct {
        pub const FirstSecondThirdFourth: L.Timing = @import("./timing/first-second-third-fourth.zon");
        pub const FirstThirdFourth: L.Timing = @import("./timing/first-third-fourth.zon");
        pub const FirstThird: L.Timing = @import("./timing/first-third.zon");
        pub const SecondFourth: L.Timing = @import("./timing/second-fourth.zon");
        pub const ThirdFourth: L.Timing = @import("./timing/third-fourth.zon");

        /// The first and the third beat of a bar.
        pub const Half = FirstThird;

        /// The second and the fourth beat of a bar.
        pub const Backbeat = SecondFourth;

        /// Every eighth note of a bar.
        /// four-on-the-flour, or four-to-the-flour.
        pub const FourFourth: L.Timing = FirstSecondThirdFourth;

        /// Every eighth note of a bar.
        pub const Gallop: L.Timing = FirstThirdFourth;
    };
}
