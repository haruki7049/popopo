pub fn Gen(comptime L: type) type {
    return struct {
        pub const MainPhrase: L.Guitar = @import("./melody/main-phrase.zon");
    };
}
