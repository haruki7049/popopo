pub fn Gen(comptime L: type) type {
    return struct {
        /// One element at full level, which is broadcast over every element it is zipped with.
        pub const Default: L.Volume = @import("./volume/default.zon");
    };
}
