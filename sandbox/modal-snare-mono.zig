const std = @import("std");
const timbre = @import("timbre");
const lightmix = @import("lightmix");

/// Audio format of the modal snare sandbox.
const configs = struct {
    /// Sample rate in Hz, of the synthesis and of the output file.
    pub const SAMPLE_RATE: u32 = 44100;
    /// Monaural.
    pub const CHANNELS: u16 = 1;
    /// Sample type used for synthesis.
    pub const T = f64;
};

/// One hit on the physical model of a snare drum, for 1 second.
pub fn gen(init: std.process.Init) !lightmix.Wave(configs.T) {
    const volume: configs.T = 1.0;
    const length = configs.SAMPLE_RATE * 1;
    const frames = length;
    const allocator = init.arena.allocator();
    const snare = timbre.ModalSnare(configs.T){};

    return snare.wave(
        allocator,
        configs.SAMPLE_RATE,
        configs.CHANNELS,
        volume,
        length,
        frames,
    );
}
