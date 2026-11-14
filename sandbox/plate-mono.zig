const std = @import("std");
const timbre = @import("timbre");
const lightmix = @import("lightmix");

/// Audio format of the plate sandbox.
const configs = struct {
    /// Sample rate in Hz, of the synthesis and of the output file.
    pub const SAMPLE_RATE: u32 = 44100;
    /// Monaural.
    pub const CHANNELS: u16 = 1;
    /// Sample type used for synthesis.
    pub const T = f64;
};

/// One hit on a bare plate, for 3 seconds, to hear what the model gives before it is made a hi-hat.
pub fn gen(init: std.process.Init) !lightmix.Wave(configs.T) {
    const volume: configs.T = 1.0;
    const length = configs.SAMPLE_RATE * 3;
    const frames = length;
    const allocator = init.arena.allocator();
    const plate = timbre.Plate(configs.T){};

    return plate.wave(
        allocator,
        configs.SAMPLE_RATE,
        configs.CHANNELS,
        volume,
        length,
        frames,
    );
}
