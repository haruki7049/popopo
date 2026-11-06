pub fn Gen(comptime L: type) type {
    return struct {
        pub const WithoutThird: L.Guitar = @import("./base/without-third.zon");
    };
}
