const std = @import("std");
const timbre = @import("timbre");
const lightmix = @import("lightmix");

/// Song-wide constants: audio format.
const configs = struct {
    /// Sample rate in Hz, of the synthesis and of the output file.
    pub const SAMPLE_RATE: u32 = 44100;
    /// Monaural.
    pub const CHANNELS: u16 = 1;
    /// Sample type used for synthesis and mixing.
    pub const T = f64;
};

/// The open hi-hat of the cymbal timbre, struck once.
pub fn gen(init: std.process.Init) !lightmix.Wave(configs.T) {
    var prng = std.Random.DefaultPrng.init(7);
    const volume: configs.T = 0.6;
    const length = configs.SAMPLE_RATE * 2;
    const frames = length;
    const allocator = init.arena.allocator();
    const cymbal = timbre.Cymbal(configs.T).open;

    const samples = try cymbal.render(
        allocator,
        prng.random(),
        configs.SAMPLE_RATE,
        volume,
        length,
        frames,
    );

    return lightmix.Wave(configs.T){
        .samples = samples,
        .allocator = allocator,
        .sample_rate = configs.SAMPLE_RATE,
        .channels = configs.CHANNELS,
    };
}
