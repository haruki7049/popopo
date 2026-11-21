pub fn Gen(comptime L: type) type {
    return struct {
        /// One chord of the pitches A3, C4 and E4, which is broadcast over every element it is zipped with.
        pub const A3C4E4: L.Chord = @import("./chord/a3-c4-e4.zon");
    };
}
