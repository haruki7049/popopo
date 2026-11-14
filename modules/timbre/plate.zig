//! A thin metal plate struck once, solved on a grid: the first step towards a physical hi-hat.
//!
//! The plate follows the linear thin plate equation, with a loss that is partly the same at every
//! frequency (`sigma0`) and partly grows with the frequency (`sigma1`), so that the high partials
//! die away first. It is solved with an explicit finite difference scheme: the 13-point stencil of
//! the biharmonic operator in space, and a centred step in time. The edges are simply supported
//! (no displacement and no bending moment at the edge), which an odd reflection of the plate into
//! two layers of ghost nodes gives. A raised-cosine force strikes one node, and the sound is the
//! velocity of another node.
//!
//! Stability: a von Neumann analysis of the scheme gives `h^2 >= 4 k (sigma1 + sqrt(sigma1^2 +
//! kappa^2))` for the distance `h` between nodes, where `k` is the time step and `kappa` is the
//! stiffness constant of the plate. The grid is chosen at that limit, so it has as many nodes as
//! the sample rate can use, and the highest partial is close to the Nyquist frequency.
//!
//! The defaults are a thin plate of the size of a 14 inch hi-hat cymbal, with little loss at high
//! frequencies, so that its many partials spread up to the top of the spectrum (about 8 kHz centroid). The model is linear: a plate struck hard does not pass energy on to higher partials as a real
//! cymbal does. It has one plate and no contact between two plates, so it is not yet a hi-hat.

const std = @import("std");
const lightmix = @import("lightmix");
const dsp = @import("./dsp.zig");

/// Returns the plate type for samples of type `T`. The fields are the parameters of the timbre.
pub fn inner(comptime T: type) type {
    return struct {
        const Self = @This();

        pub const Error = std.mem.Allocator.Error || error{
            /// The plate is too small for the sample rate to fit a grid of 4 cells on each side.
            GridTooSmall,
        };

        /// The grid of a plate at a sample rate.
        pub const Grid = struct {
            /// Distance between neighbouring nodes, in meters.
            spacing: T,
            /// Number of cells along the width.
            nx: usize,
            /// Number of cells along the height.
            ny: usize,
        };

        /// Width of the plate in meters. The grid covers a whole number of cells, so the plate may
        /// be shorter by less than one cell.
        width: T = 0.36,
        /// Height of the plate in meters, with the same rule as the width.
        height: T = 0.36,
        /// Thickness of the plate in meters.
        thickness: T = 0.0005,
        /// Young's modulus of the metal, in Pa. The default is a bronze.
        youngs_modulus: T = 1.1e11,
        /// Density of the metal, in kg/m^3.
        density: T = 8800.0,
        /// Poisson's ratio of the metal.
        poisson: T = 0.3,
        /// Loss that is the same at every frequency, in 1/s: the amplitude of a partial falls by
        /// `exp(-sigma0 * t)` at least.
        sigma0: T = 8.0,
        /// Loss that grows with the frequency, in s: a partial of angular frequency `w` has the
        /// loss `sigma0 + sigma1 * w / kappa`.
        sigma1: T = 1.0e-4,
        /// Where the plate is struck, as a share of the width and of the height, from 0 to 1.
        strike_x: T = 0.31,
        strike_y: T = 0.43,
        /// Where the sound is picked up, with the same meaning.
        pickup_x: T = 0.72,
        pickup_y: T = 0.58,
        /// Peak force of the strike, in N.
        strike_force: T = 50.0,
        /// Duration of the strike, in seconds. A shorter strike excites higher partials.
        strike_duration: T = 0.00005,
        /// Scale from the velocity of the pickup in m/s to the samples, calibrated so that a hit
        /// at the default settings peaks near 1.
        gain: T = 1.0,
        /// Fade of the timbre at the end of the note, in seconds.
        release: T = 0.008,

        /// The stiffness constant of the plate, `sqrt(D / (density * thickness))` for the bending
        /// stiffness `D`, in m^2/s.
        pub fn stiffness(self: Self) T {
            const e = self.youngs_modulus;
            const factor = 12.0 * self.density * (1.0 - self.poisson * self.poisson);
            return self.thickness * @sqrt(e / factor);
        }

        /// The grid at `sample_rate`: the smallest spacing that keeps the scheme stable, and the
        /// cells it gives to the plate. Returns `error.GridTooSmall` for a plate of fewer than 4
        /// cells on a side.
        pub fn grid(self: Self, sample_rate: u32) Error!Grid {
            const k = 1.0 / @as(T, @floatFromInt(sample_rate));
            const kappa = self.stiffness();
            const spacing = @sqrt(4.0 * k * (self.sigma1 + @sqrt(self.sigma1 * self.sigma1 + kappa * kappa)));

            const nx: usize = @intFromFloat(@floor(self.width / spacing));
            const ny: usize = @intFromFloat(@floor(self.height / spacing));
            if (nx < 4 or ny < 4) return error.GridTooSmall;

            return .{ .spacing = spacing, .nx = nx, .ny = ny };
        }

        /// Returns the first `frames` frames of a hit at `volume` that sounds `length` frames if
        /// nothing cuts it, with the one mono sound written to every channel. Frames past `length`
        /// are silent. The same plate gives the same hit every time, with no noise in it. The
        /// caller owns the samples.
        pub fn render(self: Self, allocator: std.mem.Allocator, sample_rate: u32, channels: u16, volume: T, length: usize, frames: usize) Self.Error![]T {
            const g = try self.grid(sample_rate);
            const nx = g.nx;
            const ny = g.ny;
            const h = g.spacing;

            const rate: T = @floatFromInt(sample_rate);
            const k = 1.0 / rate;
            const kappa = self.stiffness();
            const release_frames = dsp.frames(T, self.release, sample_rate);

            // The scheme, with `lap` for the 5-point Laplacian and `bih` for the 13-point
            // biharmonic, both before their division by a power of `h`:
            //   (1 + sigma0 k) next = 2 now - (1 - sigma0 k) prev - kappa^2 k^2 bih / h^4
            //                         + 2 sigma1 k (lap(now) - lap(prev)) / h^2 + k^2 force
            const c0 = 1.0 + self.sigma0 * k;
            const c_prev = 1.0 - self.sigma0 * k;
            const c_bih = kappa * kappa * k * k / (h * h * h * h);
            const c_loss = 2.0 * self.sigma1 * k / (h * h);
            // Force per unit of mass of the plate, spread over the area of one cell.
            const c_force = k * k / (self.density * self.thickness * h * h);

            // Two layers of ghost nodes around the plate hold the odd reflection of the plate.
            const pad = 2;
            const stride = nx + 1 + 2 * pad;
            const size = stride * (ny + 1 + 2 * pad);

            const memory = try allocator.alloc(T, 5 * size);
            defer allocator.free(memory);
            @memset(memory, 0.0);
            var next: []T = memory[0 * size ..][0..size];
            var now: []T = memory[1 * size ..][0..size];
            var prev: []T = memory[2 * size ..][0..size];
            var lap_now: []T = memory[3 * size ..][0..size];
            var lap_prev: []T = memory[4 * size ..][0..size];

            const strike = nodeAt(nx, ny, stride, pad, self.strike_x, self.strike_y);
            const pickup = nodeAt(nx, ny, stride, pad, self.pickup_x, self.pickup_y);

            const samples = try allocator.alloc(T, frames * channels);
            errdefer allocator.free(samples);

            for (0..frames) |n| {
                if (n >= length) {
                    @memset(samples[n * channels ..][0..channels], 0.0);
                    continue;
                }

                reflect(now, nx, ny, stride, pad);

                for (1..ny) |j| {
                    for (1..nx) |i| {
                        const p = (j + pad) * stride + (i + pad);
                        const near = now[p + 1] + now[p - 1] + now[p + stride] + now[p - stride];
                        const diagonal = now[p + stride + 1] + now[p + stride - 1] + now[p - stride + 1] + now[p - stride - 1];
                        const far = now[p + 2] + now[p - 2] + now[p + 2 * stride] + now[p - 2 * stride];

                        const lap = near - 4.0 * now[p];
                        const bih = 20.0 * now[p] - 8.0 * near + 2.0 * diagonal + far;
                        lap_now[p] = lap;

                        next[p] = (2.0 * now[p] - c_prev * prev[p] - c_bih * bih + c_loss * (lap - lap_prev[p])) / c0;
                    }
                }

                const t = @as(T, @floatFromInt(n)) * k;
                if (t < self.strike_duration) {
                    const force = 0.5 * self.strike_force * (1.0 - @cos(2.0 * std.math.pi * t / self.strike_duration));
                    next[strike] += c_force * force / c0;
                }

                const velocity = (next[pickup] - now[pickup]) / k;
                const value = volume * self.gain * velocity * dsp.tail(T, n, length, release_frames);
                @memset(samples[n * channels ..][0..channels], value);

                std.mem.swap([]T, &prev, &now);
                std.mem.swap([]T, &now, &next);
                std.mem.swap([]T, &lap_prev, &lap_now);
            }
            return samples;
        }

        pub fn wave(self: Self, allocator: std.mem.Allocator, sample_rate: u32, channels: u16, volume: T, length: usize, frames: usize) Self.Error!lightmix.Wave(T) {
            const samples = try self.render(allocator, sample_rate, channels, volume, length, frames);

            return .{
                .samples = samples,
                .allocator = allocator,
                .sample_rate = sample_rate,
                .channels = channels,
            };
        }

        /// Index of the node at the shares `x` and `y` of the width and of the height, kept off
        /// the edge, where the plate does not move.
        fn nodeAt(nx: usize, ny: usize, stride: usize, pad: usize, x: T, y: T) usize {
            const i = nodeIndex(nx, x);
            const j = nodeIndex(ny, y);
            return (j + pad) * stride + (i + pad);
        }

        fn nodeIndex(cells: usize, share: T) usize {
            const at: T = @round(share * @as(T, @floatFromInt(cells)));
            const low: T = 1.0;
            const high: T = @floatFromInt(cells - 1);
            return @intFromFloat(@min(@max(at, low), high));
        }

        /// Fills the ghost nodes with the odd reflection of the plate about its edges, which makes
        /// the edges simply supported: the displacement is zero there, and so is the bending moment.
        fn reflect(u: []T, nx: usize, ny: usize, stride: usize, pad: usize) void {
            for (0..ny + 1) |j| {
                const row = (j + pad) * stride;
                u[row + pad - 1] = -u[row + pad + 1];
                u[row + pad - 2] = -u[row + pad + 2];
                u[row + pad + nx + 1] = -u[row + pad + nx - 1];
                u[row + pad + nx + 2] = -u[row + pad + nx - 2];
            }
            for (0..stride) |c| {
                u[(pad - 1) * stride + c] = -u[(pad + 1) * stride + c];
                u[(pad - 2) * stride + c] = -u[(pad + 2) * stride + c];
                u[(pad + ny + 1) * stride + c] = -u[(pad + ny - 1) * stride + c];
                u[(pad + ny + 2) * stride + c] = -u[(pad + ny - 2) * stride + c];
            }
        }
    };
}

/// The energy of `samples` at `frequency` Hz, by the Goertzel algorithm.
/// A plate big and slow enough for the grid at the low sample rates the tests use.
const big: inner(f64) = .{ .width = 0.3, .height = 0.3, .thickness = 0.0008, .sigma0 = 6.0, .sigma1 = 1.35e-3, .strike_duration = 0.0005 };

fn goertzel(samples: []const f64, frequency: f64, rate: f64) f64 {
    const w = 2.0 * std.math.pi * frequency / rate;
    const coeff = 2.0 * @cos(w);
    var s1: f64 = 0.0;
    var s2: f64 = 0.0;
    for (samples) |x| {
        const s0 = x + coeff * s1 - s2;
        s2 = s1;
        s1 = s0;
    }
    return s1 * s1 + s2 * s2 - coeff * s1 * s2;
}

fn rms(samples: []const f64) f64 {
    var sum: f64 = 0.0;
    for (samples) |x| sum += x * x;
    return @sqrt(sum / @as(f64, @floatFromInt(samples.len)));
}

test "render returns the frames asked for, starting and ending at zero" {
    const allocator = std.testing.allocator;
    const plate: inner(f64) = big;
    const samples = try plate.render(allocator, 8000, 1, 1.0, 2000, 2000);
    defer allocator.free(samples);

    try std.testing.expectEqual(@as(usize, 2000), samples.len);
    try std.testing.expectEqual(@as(f64, 0.0), samples[0]);
    try std.testing.expectEqual(@as(f64, 0.0), samples[samples.len - 1]);

    var peak: f64 = 0.0;
    for (samples) |s| {
        try std.testing.expect(std.math.isFinite(s));
        peak = @max(peak, @abs(s));
    }
    try std.testing.expect(peak > 0.0);
}

test "the frames of stereo samples is the double with mono samples, with the same sound in both" {
    const allocator = std.testing.allocator;
    const plate: inner(f64) = big;

    const mono = try plate.render(allocator, 8000, 1, 1.0, 1500, 1500);
    defer allocator.free(mono);
    const stereo = try plate.render(allocator, 8000, 2, 1.0, 1500, 1500);
    defer allocator.free(stereo);

    try std.testing.expectEqual(mono.len * 2, stereo.len);
    for (mono, 0..) |s, i| {
        try std.testing.expectEqual(s, stereo[2 * i]);
        try std.testing.expectEqual(s, stereo[2 * i + 1]);
    }
}

test "a cut hit is the start of the full hit" {
    const allocator = std.testing.allocator;
    const plate: inner(f64) = big;

    const full = try plate.render(allocator, 8000, 1, 0.9, 4000, 4000);
    defer allocator.free(full);
    const cut = try plate.render(allocator, 8000, 1, 0.9, 4000, 1300);
    defer allocator.free(cut);

    try std.testing.expectEqualSlices(f64, full[0..1300], cut);
}

test "the hit dies away" {
    const allocator = std.testing.allocator;
    const plate: inner(f64) = big;
    const frames: usize = 16000;

    const samples = try plate.render(allocator, 8000, 1, 1.0, frames, frames);
    defer allocator.free(samples);

    try std.testing.expect(rms(samples[frames - 2000 .. frames - 100]) < 0.1 * rms(samples[0..2000]));
}

test "the grid keeps the scheme stable, whatever the loss" {
    const allocator = std.testing.allocator;
    const sigma1s = [_]f64{ 0.0, 1.35e-3, 0.05 };

    for (sigma1s) |sigma1| {
        var plate = big;
        plate.sigma1 = sigma1;
        const kappa = plate.stiffness();
        const k = 1.0 / 8000.0;
        const g = try plate.grid(8000);
        try std.testing.expect(g.spacing * g.spacing >= 4.0 * k * (sigma1 + @sqrt(sigma1 * sigma1 + kappa * kappa)) * (1.0 - 1e-12));

        const samples = try plate.render(allocator, 8000, 1, 1.0, 8000, 8000);
        defer allocator.free(samples);
        for (samples) |s| {
            try std.testing.expect(std.math.isFinite(s));
            try std.testing.expect(@abs(s) < 1.0e3);
        }
    }
}

test "the lowest partial is where the plate equation puts it" {
    const allocator = std.testing.allocator;
    const rate: u32 = 8000;
    // Little loss, so that the lowest partial stands out.
    var plate = big;
    plate.sigma0 = 1.0;
    plate.sigma1 = 0.0;
    const g = try plate.grid(rate);

    // The lowest mode of a simply supported rectangular plate, of the size the grid covers.
    const lx = @as(f64, @floatFromInt(g.nx)) * g.spacing;
    const ly = @as(f64, @floatFromInt(g.ny)) * g.spacing;
    const expected = 0.5 * std.math.pi * plate.stiffness() * (1.0 / (lx * lx) + 1.0 / (ly * ly));

    const frames: usize = 2 * rate;
    const samples = try plate.render(allocator, rate, 1, 1.0, frames, frames);
    defer allocator.free(samples);

    var best: f64 = 0.0;
    var best_energy: f64 = -1.0;
    var f = 0.6 * expected;
    while (f <= 1.4 * expected) : (f += 0.005 * expected) {
        const energy = goertzel(samples, f, @floatFromInt(rate));
        if (energy > best_energy) {
            best_energy = energy;
            best = f;
        }
    }
    try std.testing.expectApproxEqRel(expected, best, 0.03);
}

test "a plate too small for the sample rate has no grid" {
    const plate: inner(f64) = .{ .width = 0.02, .height = 0.02 };
    try std.testing.expectError(error.GridTooSmall, plate.grid(44100));
}

test {
    std.testing.refAllDecls(@This());
}
