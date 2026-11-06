const std = @import("std");
const timbre = @import("timbre");
const lightmix = @import("lightmix");

/// Song-wide constants: tempo, meter and audio format.
const configs = struct {
    /// Tempo in quarter notes per minute.
    pub const BPM: usize = 135;
    /// Beats per bar (4/4).
    pub const BEATS_PER_BAR: usize = 4;
    /// Note value of one beat (4/4).
    pub const BEAT_VALUE: usize = 4;
    /// Sample rate in Hz, of the synthesis and of the output file.
    pub const SAMPLE_RATE: u32 = 44100;
    /// Monaural.
    pub const CHANNELS: u16 = 1;
    /// Sample type used for synthesis and mixing.
    pub const T = f64;
    /// Peak level the final mix is normalized to (about -1 dBFS).
    pub const PEAK: T = 0.89;
};

pub fn gen(init: std.process.Init) !lightmix.Wave(configs.T) {
    var prng = std.Random.DefaultPrng.init(7);
    const volume: configs.T = 1.0;
    const length = configs.SAMPLE_RATE * 1;
    const frames = length;
    const allocator = init.arena.allocator();
    const snare = timbre.Snare(configs.T){};

    return snare.wave(
        allocator,
        prng.random(),
        configs.SAMPLE_RATE,
        configs.CHANNELS,
        volume,
        length,
        frames,
    );
}
