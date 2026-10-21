pub fn Gen(comptime L: type) type {
    return struct {
        pub const MainPhrase: L.Guitar = @import("./melody/main-phrase.zon");
        pub const ToNext: L.Guitar = @import("./melody/to-next.zon");
    };
}
