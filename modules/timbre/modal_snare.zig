//! A snare drum from a physical model: a circular membrane in modes, with snares that collide with it.
//!
//! The batter head is a circular membrane with a fixed edge, written as the sum of its modes, the
//! Bessel function shapes `J_m(lambda r / a) cos(m theta)` and `... sin(m theta)`, each a damped
//! oscillator. A raised-cosine force strikes it at one point, and the sound is the velocity of the
//! membrane at another point.
//!
//! The snares are `wire_count` wires under the head. Each wire is one damped oscillator, the lowest
//! mode of a wire, that touches the head at one point. A wire and the head collide when the head
//! moves down past the wire, through a power law contact force `contact_stiffness * penetration ^
//! contact_exponent`. The contact is solved with the scalar auxiliary variable (SAV) method, in the
//! way of the paper listed below: the potential energy of the contact is rewritten with a scalar
//! `psi` so that the time step is explicit, needs no iteration, and cannot gain energy through the
//! contact, whatever the time step. One step costs a few passes over the modes per wire, plus a
//! small dense solve of the size of the wire count (Woodbury formula).
//!
//! Model, and where it differs from the paper:
//!
//!   - Michele Ducceschi et al., "Simulation of the snare-membrane collision in modal form using
//!     the scalar auxiliary variable (SAV) method", EAA Forum Acusticum 2023, models one wire as a
//!     stiff string that collides with one membrane. Here the wire is one oscillator, there are
//!     many wires, the contact points lie on a spiral over the head, the head is struck by a
//!     force, and the loss is a damping of every mode. Those parts are the design of this file, not
//!     the paper's.
//!   - The second head, the air in the shell and the shell are not modelled.
//!   - The time step is `1 / (sample_rate * oversampling)`. The scheme averages the stiffness over
//!     two steps, which warps the frequencies, so each frequency is corrected beforehand and the
//!     modes sound at the pitches the membrane has, whatever the oversampling.
//!
//! Solving the drum costs far more than the rest of a hit, and it is the same for every hit: there
//! is no noise, and the volume only scales the sound. So it can be done once: `respond` solves it,
//! and `renderWith` reads the result for each note. `render` does both for one note.
//!
//! The model is not checked by ear.

const std = @import("std");
const lightmix = @import("lightmix");
const dsp = @import("./dsp.zig");

/// First zero of the Bessel function of order 0, the lowest mode of a membrane with a fixed edge.
const first_zero = 2.404825557695773;

/// The angle between two points on a spiral that fills a disc evenly, in radians.
const golden_angle = 2.399963229728653;

/// The offset of the SAV method, in J, that keeps the auxiliary variable away from zero.
const sav_offset = 1.0e-9;

/// Returns the type of the modal snare for samples of type `T`. The fields are the parameters.
pub fn inner(comptime T: type) type {
    return struct {
        const Self = @This();

        pub const Error = std.mem.Allocator.Error || error{
            /// The highest frequency that the sample rate and the settings allow is below the lowest
            /// mode of the membrane.
            NoModes,
        };

        /// Radius of the head in meters. The default is a 17.5 inch head. It sets the mass of the head
        /// with `surface_density`, not the pitch, which is `fundamental`: a head of another radius at the
        /// same tension has the fundamental in proportion to the inverse of the radius.
        radius: T = 0.22225,
        /// Mass of the head per area in kg/m^2. It sets how strong a force is, not the pitch.
        surface_density: T = 0.262,
        /// Frequency in Hz of the lowest mode of the head: the pitch of the drum.
        fundamental: T = 160.0,
        /// Loss that is the same at every frequency, in 1/s: the amplitude of a mode falls by
        /// `exp(-sigma0 * t)` at least.
        sigma0: T = 3.0,
        /// Loss that grows with the square of the frequency, in s: a mode of angular frequency `w`
        /// has the loss `sigma0 + sigma1 * w^2`, so that the high modes die away first.
        sigma1: T = 1.0e-7,
        /// The modes above this frequency in Hz are left out. The sample rate and the oversampling
        /// lower it further. The cost of a hit is about proportional to the number of modes.
        max_frequency: T = 8000.0,
        /// Steps per output sample. The scheme is stable at any value, and more steps follow a
        /// collision more closely at more cost.
        oversampling: usize = 2,
        /// Where the head is struck, as the share of the radius from the center, and the angle in
        /// radians. The center excites the circular modes only.
        strike_radius: T = 0.25,
        strike_angle: T = 0.3,
        /// Where the sound is picked up, with the same meaning.
        pickup_radius: T = 0.35,
        pickup_angle: T = 1.1,
        /// Peak force of the strike in N, and its duration in seconds.
        strike_force: T = 20.0,
        strike_duration: T = 0.001,
        /// Number of wires. Zero leaves the head alone, a plain drum.
        wire_count: usize = 8,
        /// Mass of a wire in kg.
        wire_mass: T = 0.0002,
        /// Frequency in Hz of the oscillation of a wire, and its loss in 1/s.
        wire_frequency: T = 150.0,
        wire_sigma: T = 30.0,
        /// Stiffness of the contact in N/m^contact_exponent, and the exponent of the contact force.
        contact_stiffness: T = 1.0e8,
        contact_exponent: T = 1.5,
        /// Scale from the velocity of the pickup in m/s to the samples, calibrated so that a hit at
        /// the default settings peaks near 0.7.
        gain: T = 0.167,
        /// Fade of the timbre at the end of the note, in seconds.
        release: T = 0.01,

        /// The velocity of the pickup after a strike, which does not depend on the note: the drum has
        /// no noise, and the volume only scales the sound. It is solved once with `respond` and read
        /// by any number of notes with `renderWith`.
        pub const Response = struct {
            /// The velocity of the pickup in m/s, mono, from the strike on. After its last frame the
            /// drum counts as silent.
            velocity: []T,

            pub fn deinit(self: Response, allocator: std.mem.Allocator) void {
                allocator.free(self.velocity);
            }
        };

        /// Solves the drum for `frames` frames at `sample_rate`. A note that sounds longer than
        /// `frames` reads silence after them, so `frames` is the longest note to be rendered with it.
        /// The caller frees the response with `deinit`.
        pub fn respond(self: Self, allocator: std.mem.Allocator, sample_rate: u32, frames: usize) Self.Error!Response {
            const rate: T = @floatFromInt(sample_rate);
            const steps_per_sample = @max(self.oversampling, 1);
            const k: T = 1.0 / (rate * @as(T, @floatFromInt(steps_per_sample)));
            const k2 = k * k;

            // The highest frequency: under the Nyquist frequency of the output, which the modes alone
            // fill, and low enough for the correction of the frequencies below.
            const f_max = @min(self.max_frequency, @min(0.45 * rate, 0.2 / k));
            const lambda_max = first_zero * f_max / self.fundamental;
            if (lambda_max < first_zero) return error.NoModes;

            const modes = try buildModes(T, allocator, self.radius, self.surface_density, lambda_max);
            defer freeModes(T, allocator, modes);
            const p = modes.count();
            const wires = self.wire_count;
            const dofs = p + wires;

            // Per mode and per wire: the angular frequency made right for the scheme, the factor of
            // the update that is the inverse of the left side, and the loss.
            const a_inv = try allocator.alloc(T, dofs);
            defer allocator.free(a_inv);
            const stiff = try allocator.alloc(T, dofs);
            defer allocator.free(stiff);

            const w_unit = 2.0 * std.math.pi * self.fundamental / first_zero;
            for (0..p) |i| {
                const w = w_unit * modes.lambda[i];
                const sigma = self.sigma0 + self.sigma1 * w * w;
                stiff[i] = warped(w, k);
                a_inv[i] = 1.0 / (1.0 / k2 + 0.5 * stiff[i] + sigma / k);
            }
            const ww = 2.0 * std.math.pi * self.wire_frequency;
            for (0..wires) |j| {
                stiff[p + j] = warped(ww, k);
                a_inv[p + j] = 1.0 / (1.0 / k2 + 0.5 * stiff[p + j] + self.wire_sigma / k);
            }

            // Shapes of the modes at the points of the wires, the strike and the pickup.
            const shape = try allocator.alloc(T, wires * p);
            defer allocator.free(shape);
            for (0..wires) |j| {
                const share = 0.85 * @sqrt((@as(T, @floatFromInt(j)) + 0.5) / @as(T, @floatFromInt(wires)));
                const angle = @as(T, @floatFromInt(j)) * golden_angle;
                fillShapes(T, modes, share, angle, shape[j * p ..][0..p]);
            }
            const strike_shape = try allocator.alloc(T, p);
            defer allocator.free(strike_shape);
            fillShapes(T, modes, self.strike_radius, self.strike_angle, strike_shape);
            const pickup_shape = try allocator.alloc(T, p);
            defer allocator.free(pickup_shape);
            fillShapes(T, modes, self.pickup_radius, self.pickup_angle, pickup_shape);

            // The wire coordinate is scaled by the square root of its mass, so that its mass is 1.
            const wire_inv_root = 1.0 / @sqrt(self.wire_mass);

            // H = C^T A^-1 C, for the contact points `C`: the same at every step.
            const h = try allocator.alloc(T, wires * wires);
            defer allocator.free(h);
            for (0..wires) |i| {
                for (0..wires) |j| {
                    var sum: T = 0.0;
                    for (0..p) |m| sum += shape[i * p + m] * shape[j * p + m] * a_inv[m];
                    if (i == j) sum += wire_inv_root * wire_inv_root * a_inv[p + i];
                    h[i * wires + j] = sum;
                }
            }

            // State: two time levels of every mode and wire, and of the penetration at every wire.
            const state = try allocator.alloc(T, 5 * dofs + 8 * wires + wires * wires);
            defer allocator.free(state);
            @memset(state, 0.0);
            var cur: []T = state[0 * dofs ..][0..dofs];
            var prev: []T = state[1 * dofs ..][0..dofs];
            const r0 = state[2 * dofs ..][0..dofs];
            const u = state[3 * dofs ..][0..dofs];
            const d = state[4 * dofs ..][0..dofs];
            const base = 5 * dofs;
            var eta: []T = state[base + 0 * wires ..][0..wires];
            var eta_prev: []T = state[base + 1 * wires ..][0..wires];
            const psi = state[base + 2 * wires ..][0..wires];
            const g = state[base + 3 * wires ..][0..wires];
            const gpsi = state[base + 4 * wires ..][0..wires];
            const y = state[base + 5 * wires ..][0..wires];
            const s = state[base + 6 * wires ..][0..wires];
            const cd = state[base + 7 * wires ..][0..wires];
            const m_matrix = state[base + 8 * wires ..][0 .. wires * wires];
            @memset(psi, @sqrt(@as(T, sav_offset)));

            const velocities = try allocator.alloc(T, frames);
            errdefer allocator.free(velocities);

            const half_inv_k = 0.5 / k;

            for (0..frames) |n| {
                var velocity: T = 0.0;
                for (0..steps_per_sample) |sub| {
                    const t = @as(T, @floatFromInt(n * steps_per_sample + sub)) * k;

                    // The contact, evaluated where the head and the wires are now.
                    var contact = false;
                    for (0..wires) |j| {
                        g[j] = self.contactG(eta[j]);
                        gpsi[j] = g[j] * psi[j];
                        if (g[j] != 0.0) contact = true;
                    }

                    // The right side without the contact: the inertia, the stiffness, and the strike.
                    for (0..dofs) |i| r0[i] = 2.0 * (cur[i] - prev[i]) / k2 - stiff[i] * prev[i];
                    if (t < self.strike_duration) {
                        const force = 0.5 * self.strike_force * (1.0 - @cos(2.0 * std.math.pi * t / self.strike_duration));
                        for (0..p) |i| r0[i] += force * strike_shape[i];
                    }
                    for (0..dofs) |i| u[i] = a_inv[i] * r0[i];

                    // y = C^T A^-1 (r0 - C g psi), the change of the penetration if no contact acts back.
                    for (0..wires) |j| {
                        var sum: T = -wire_inv_root * u[p + j];
                        for (0..p) |i| sum += shape[j * p + i] * u[i];
                        for (0..wires) |l| sum -= h[j * wires + l] * gpsi[l];
                        y[j] = sum;
                    }

                    // s: the contact acting back on itself, from (I + D H D / 4) s = D y / 2.
                    if (contact) {
                        for (0..wires) |i| {
                            for (0..wires) |l| {
                                m_matrix[i * wires + l] = 0.25 * g[i] * h[i * wires + l] * g[l] + if (i == l) @as(T, 1.0) else 0.0;
                            }
                            s[i] = 0.5 * g[i] * y[i];
                        }
                        solveSymmetric(T, m_matrix, s, wires);
                    } else {
                        @memset(s, 0.0);
                    }

                    // The step: d = A^-1 (r0 - C e), with e = g (psi + s / 2).
                    for (0..dofs) |i| d[i] = r0[i];
                    for (0..wires) |j| {
                        const e = g[j] * (psi[j] + 0.5 * s[j]);
                        for (0..p) |i| d[i] -= shape[j * p + i] * e;
                        d[p + j] += wire_inv_root * e;
                    }
                    for (0..dofs) |i| d[i] *= a_inv[i];

                    // The change of the penetration over two steps, and the auxiliary variable.
                    for (0..wires) |j| {
                        var sum = y[j];
                        for (0..wires) |l| sum -= h[j * wires + l] * 0.5 * g[l] * s[l];
                        cd[j] = sum;
                    }

                    if (sub == 0) {
                        var sum: T = 0.0;
                        for (0..p) |i| sum += pickup_shape[i] * d[i];
                        velocity = sum * half_inv_k;
                    }

                    for (0..dofs) |i| prev[i] += d[i];
                    std.mem.swap([]T, &cur, &prev);

                    for (0..wires) |j| {
                        eta_prev[j] += cd[j];
                        psi[j] += 0.5 * g[j] * cd[j];
                    }
                    std.mem.swap([]T, &eta, &eta_prev);
                }

                velocities[n] = velocity;
            }
            return .{ .velocity = velocities };
        }

        /// Returns the first `frames` frames of a hit at `volume` that sounds `length` frames if
        /// nothing cuts it, with the one mono sound written to every channel. Frames past `length`
        /// are silent. The same drum gives the same hit every time, with no noise in it. The caller
        /// owns the samples.
        pub fn render(self: Self, allocator: std.mem.Allocator, sample_rate: u32, channels: u16, volume: T, length: usize, frames: usize) Self.Error![]T {
            const response = try self.respond(allocator, sample_rate, @min(length, frames));
            defer response.deinit(allocator);
            return self.renderWith(allocator, sample_rate, channels, volume, length, frames, response);
        }

        /// The same as `render`, with the drum read from `response` (made by `respond` for the same
        /// drum and sample rate) instead of solved again. The samples are the same as `render` gives
        /// whenever the response has at least as many frames as `render` would solve, the smaller of
        /// `length` and `frames`.
        pub fn renderWith(self: Self, allocator: std.mem.Allocator, sample_rate: u32, channels: u16, volume: T, length: usize, frames: usize, response: Response) Self.Error![]T {
            const samples = try allocator.alloc(T, frames * channels);
            errdefer allocator.free(samples);

            const release_frames = dsp.frames(T, self.release, sample_rate);

            for (0..frames) |n| {
                const value: T = if (n >= length or n >= response.velocity.len)
                    0.0
                else
                    volume * self.gain * response.velocity[n] * dsp.tail(T, n, length, release_frames);
                @memset(samples[n * channels ..][0..channels], value);
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

        /// The same as `wave`, with the drum read from `response` as in `renderWith`.
        pub fn waveWith(self: Self, allocator: std.mem.Allocator, sample_rate: u32, channels: u16, volume: T, length: usize, frames: usize, response: Response) Self.Error!lightmix.Wave(T) {
            const samples = try self.renderWith(allocator, sample_rate, channels, volume, length, frames, response);

            return .{
                .samples = samples,
                .allocator = allocator,
                .sample_rate = sample_rate,
                .channels = channels,
            };
        }

        /// `phi'(eta) / sqrt(2 phi(eta) + sav_offset)` for the contact energy
        /// `phi(eta) = stiffness * eta^(exponent + 1) / (exponent + 1)`, which is zero while the
        /// wire and the head do not touch.
        fn contactG(self: Self, eta: T) T {
            if (eta <= 0.0) return 0.0;
            const exponent = self.contact_exponent;
            const force = self.contact_stiffness * std.math.pow(T, eta, exponent);
            const energy = force * eta / (exponent + 1.0);
            return force / @sqrt(2.0 * energy + @as(T, sav_offset));
        }
    };
}

/// The stiffness to use in the scheme for the angular frequency `w` at the time step `k`, so that
/// the scheme gives exactly the frequency `w`: `2 (sec(w k) - 1) / k^2`.
fn warped(w: anytype, k: @TypeOf(w)) @TypeOf(w) {
    return 2.0 * (1.0 / @cos(w * k) - 1.0) / (k * k);
}

/// The Bessel function of the first kind, of integer `order`, by the trapezoid rule on its integral
/// over a whole period, which converges fast when the number of points is above `order + |x|`.
fn besselJ(comptime T: type, order: usize, x: T) T {
    const n: usize = @as(usize, @intFromFloat(@ceil(@abs(x)))) + order + 32;
    const n_float: T = @floatFromInt(n);
    const m: T = @floatFromInt(order);
    var sum: T = 0.0;
    for (0..n) |i| {
        const tau = 2.0 * std.math.pi * @as(T, @floatFromInt(i)) / n_float;
        sum += @cos(m * tau - x * @sin(tau));
    }
    return sum / n_float;
}

/// Appends the zeros of the Bessel function of `order` that are at most `limit`, in order, to
/// `zeros`, and returns how many there were.
fn appendZeros(comptime T: type, allocator: std.mem.Allocator, zeros: *std.ArrayList(T), order: usize, limit: T) std.mem.Allocator.Error!usize {
    var found: usize = 0;
    // The first zero is above `order`, and the zeros are more than 3 apart, so steps of 1 find each.
    var lo: T = @floatFromInt(order);
    var f_lo = besselJ(T, order, lo);
    while (lo < limit) {
        const hi = lo + 1.0;
        const f_hi = besselJ(T, order, hi);
        if (f_lo * f_hi <= 0.0 and f_lo != 0.0) {
            const zero = refineZero(T, order, lo, hi, f_lo, f_hi);
            if (zero <= limit) {
                try zeros.append(allocator, zero);
                found += 1;
            }
        }
        lo = hi;
        f_lo = f_hi;
    }
    return found;
}

/// The zero of the Bessel function of `order` between `a` and `b`, which have the values `fa` and
/// `fb` of opposite signs, by the false position method with the Illinois rule.
fn refineZero(comptime T: type, order: usize, a: T, b: T, fa: T, fb: T) T {
    var lo = a;
    var hi = b;
    var f_lo = fa;
    var f_hi = fb;
    var side: i8 = 0;
    var c = a;
    for (0..80) |_| {
        c = (lo * f_hi - hi * f_lo) / (f_hi - f_lo);
        const f_c = besselJ(T, order, c);
        if (f_c * f_hi > 0.0) {
            hi = c;
            f_hi = f_c;
            if (side == -1) f_lo *= 0.5;
            side = -1;
        } else if (f_lo * f_c > 0.0) {
            lo = c;
            f_lo = f_c;
            if (side == 1) f_hi *= 0.5;
            side = 1;
        } else {
            break;
        }
        if (@abs(hi - lo) < 1.0e-12) break;
    }
    return c;
}

/// The modes of a circular membrane of `radius` with a fixed edge and `density` per area, whose
/// `lambda` is at most `lambda_max`. The caller frees them with `freeModes`.
fn buildModes(comptime T: type, allocator: std.mem.Allocator, radius: T, density: T, lambda_max: T) std.mem.Allocator.Error!Modes(T) {
    var zeros: std.ArrayList(T) = .empty;
    defer zeros.deinit(allocator);
    var orders: std.ArrayList(usize) = .empty;
    defer orders.deinit(allocator);

    var order: usize = 0;
    while (true) : (order += 1) {
        const found = try appendZeros(T, allocator, &zeros, order, lambda_max);
        if (found == 0) break;
        for (0..found) |_| try orders.append(allocator, order);
    }

    var total: usize = 0;
    for (orders.items) |o| total += if (o == 0) 1 else 2;

    const lambda = try allocator.alloc(T, total);
    errdefer allocator.free(lambda);
    const order_list = try allocator.alloc(usize, total);
    errdefer allocator.free(order_list);
    const sine = try allocator.alloc(bool, total);
    errdefer allocator.free(sine);
    const scale = try allocator.alloc(T, total);
    errdefer allocator.free(scale);

    var i: usize = 0;
    for (zeros.items, orders.items) |zero, o| {
        // The integral of the squared shape over the disc, from the Bessel function of the next order.
        const next = besselJ(T, o + 1, zero);
        const half: T = if (o == 0) 1.0 else 0.5;
        const norm = std.math.pi * radius * radius * half * next * next;
        const unit = 1.0 / @sqrt(density * norm);
        const copies: usize = if (o == 0) 1 else 2;
        for (0..copies) |c| {
            lambda[i] = zero;
            order_list[i] = o;
            sine[i] = c == 1;
            scale[i] = unit;
            i += 1;
        }
    }
    return .{ .lambda = lambda, .order = order_list, .sine = sine, .scale = scale };
}

fn Modes(comptime T: type) type {
    return struct {
        const Self = @This();

        lambda: []T,
        order: []usize,
        sine: []bool,
        scale: []T,

        fn count(self: Self) usize {
            return self.lambda.len;
        }
    };
}

fn freeModes(comptime T: type, allocator: std.mem.Allocator, modes: Modes(T)) void {
    allocator.free(modes.lambda);
    allocator.free(modes.order);
    allocator.free(modes.sine);
    allocator.free(modes.scale);
}

/// Writes into `out` the shape of every mode at the point of the head at `share` of the radius from
/// the center, and the angle `angle`, with the scale that gives each mode a unit mass.
fn fillShapes(comptime T: type, modes: Modes(T), share: T, angle: T, out: []T) void {
    for (0..modes.count()) |i| {
        const order: T = @floatFromInt(modes.order[i]);
        const around = if (modes.sine[i]) @sin(order * angle) else @cos(order * angle);
        out[i] = modes.scale[i] * besselJ(T, modes.order[i], modes.lambda[i] * share) * around;
    }
}

/// Solves `m x = b` in place for the symmetric positive definite `n` by `n` matrix `m` (row-major,
/// destroyed), by the Cholesky factorization. `b` becomes `x`.
fn solveSymmetric(comptime T: type, m: []T, b: []T, n: usize) void {
    for (0..n) |j| {
        var diagonal = m[j * n + j];
        for (0..j) |l| diagonal -= m[j * n + l] * m[j * n + l];
        const root = @sqrt(diagonal);
        m[j * n + j] = root;
        for (j + 1..n) |i| {
            var sum = m[i * n + j];
            for (0..j) |l| sum -= m[i * n + l] * m[j * n + l];
            m[i * n + j] = sum / root;
        }
    }
    for (0..n) |i| {
        var sum = b[i];
        for (0..i) |l| sum -= m[i * n + l] * b[l];
        b[i] = sum / m[i * n + i];
    }
    var i = n;
    while (i > 0) {
        i -= 1;
        var sum = b[i];
        for (i + 1..n) |l| sum -= m[l * n + i] * b[l];
        b[i] = sum / m[i * n + i];
    }
}

/// The energy of `samples` at `frequency` Hz, by the Goertzel algorithm.
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

const Drum = inner(f64);

test "the Bessel function and its zeros match the known values" {
    try std.testing.expectApproxEqAbs(@as(f64, 0.7651976865579666), besselJ(f64, 0, 1.0), 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.4400505857449335), besselJ(f64, 1, 1.0), 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.1149034849319005), besselJ(f64, 2, 1.0), 1e-12);

    const allocator = std.testing.allocator;
    const expected = [_]struct { usize, f64 }{
        .{ 0, 2.404825557695773 },
        .{ 1, 3.831705970207512 },
        .{ 2, 5.135622301840683 },
    };
    for (expected) |e| {
        var zeros: std.ArrayList(f64) = .empty;
        defer zeros.deinit(allocator);
        _ = try appendZeros(f64, allocator, &zeros, e.@"0", 6.0);
        try std.testing.expect(zeros.items.len >= 1);
        try std.testing.expectApproxEqAbs(e.@"1", zeros.items[0], 1e-9);
    }
}

test "the zeros of one order come in order, more than 3 apart" {
    const allocator = std.testing.allocator;
    var zeros: std.ArrayList(f64) = .empty;
    defer zeros.deinit(allocator);
    const found = try appendZeros(f64, allocator, &zeros, 5, 60.0);
    try std.testing.expect(found > 15);
    for (zeros.items[1..], zeros.items[0 .. zeros.items.len - 1]) |next, before| {
        try std.testing.expect(next - before > 3.0);
        try std.testing.expect(next - before < 4.0);
    }
}

test "the modes are normalized: the mean square shape over the disc is one over the mass" {
    const allocator = std.testing.allocator;
    const density = 0.3;
    const radius = 0.2;
    const modes = try buildModes(f64, allocator, radius, density, 8.0);
    defer freeModes(f64, allocator, modes);
    try std.testing.expect(modes.count() >= 5);

    // Integrate the squared shape over the disc by midpoint sums on polar cells.
    const nr: usize = 400;
    const nt: usize = 128;
    const nr_f: f64 = @floatFromInt(nr);
    const nt_f: f64 = @floatFromInt(nt);
    for (0..modes.count()) |i| {
        var sum: f64 = 0.0;
        for (0..nr) |ir| {
            const share = (@as(f64, @floatFromInt(ir)) + 0.5) / nr_f;
            for (0..nt) |it| {
                const angle = 2.0 * std.math.pi * (@as(f64, @floatFromInt(it)) + 0.5) / nt_f;
                var one: [1]f64 = undefined;
                const single: Modes(f64) = .{
                    .lambda = modes.lambda[i .. i + 1],
                    .order = modes.order[i .. i + 1],
                    .sine = modes.sine[i .. i + 1],
                    .scale = modes.scale[i .. i + 1],
                };
                fillShapes(f64, single, share, angle, &one);
                sum += one[0] * one[0] * share * radius * radius * (1.0 / nr_f) * (2.0 * std.math.pi / nt_f);
            }
        }
        // The shape is scaled to a unit mass: density times the integral is 1.
        try std.testing.expectApproxEqRel(@as(f64, 1.0), density * sum, 2e-3);
    }
}

test "the symmetric solve inverts a matrix" {
    var m = [_]f64{ 4.0, 1.0, 0.5, 1.0, 3.0, 0.2, 0.5, 0.2, 2.0 };
    var b = [_]f64{ 1.0, 2.0, 3.0 };
    const original = m;
    solveSymmetric(f64, &m, &b, 3);
    for (0..3) |i| {
        var sum: f64 = 0.0;
        for (0..3) |j| sum += original[i * 3 + j] * b[j];
        try std.testing.expectApproxEqAbs(@as(f64, @floatFromInt(i + 1)), sum, 1e-12);
    }
}

test "render returns the frames asked for, starting and ending at zero" {
    const allocator = std.testing.allocator;
    const drum: Drum = .{};
    const samples = try drum.render(allocator, 8000, 1, 1.0, 2000, 2000);
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
    const drum: Drum = .{};

    const mono = try drum.render(allocator, 8000, 1, 1.0, 1500, 1500);
    defer allocator.free(mono);
    const stereo = try drum.render(allocator, 8000, 2, 1.0, 1500, 1500);
    defer allocator.free(stereo);

    try std.testing.expectEqual(mono.len * 2, stereo.len);
    for (mono, 0..) |s, i| {
        try std.testing.expectEqual(s, stereo[2 * i]);
        try std.testing.expectEqual(s, stereo[2 * i + 1]);
    }
}

test "a cut hit is the start of the full hit" {
    const allocator = std.testing.allocator;
    const drum: Drum = .{};

    const full = try drum.render(allocator, 8000, 1, 0.9, 4000, 4000);
    defer allocator.free(full);
    const cut = try drum.render(allocator, 8000, 1, 0.9, 4000, 1300);
    defer allocator.free(cut);

    try std.testing.expectEqualSlices(f64, full[0..1300], cut);
}

test "the hit dies away" {
    const allocator = std.testing.allocator;
    const drum: Drum = .{};
    const frames: usize = 16000;

    const samples = try drum.render(allocator, 8000, 1, 1.0, frames, frames);
    defer allocator.free(samples);

    try std.testing.expect(rms(samples[frames - 2000 .. frames - 100]) < 0.1 * rms(samples[0..2000]));
}

test "the lowest mode of a plain drum is the fundamental, whatever the oversampling" {
    const allocator = std.testing.allocator;
    const rate: u32 = 8000;
    const frames: usize = 2 * rate;

    for ([_]usize{ 2, 4 }) |oversampling| {
        const drum: Drum = .{ .wire_count = 0, .sigma0 = 1.0, .sigma1 = 0.0, .oversampling = oversampling };
        const samples = try drum.render(allocator, rate, 1, 1.0, frames, frames);
        defer allocator.free(samples);

        var best: f64 = 0.0;
        var best_energy: f64 = -1.0;
        var f: f64 = 0.8 * drum.fundamental;
        while (f <= 1.2 * drum.fundamental) : (f += 0.002 * drum.fundamental) {
            const energy = goertzel(samples, f, @floatFromInt(rate));
            if (energy > best_energy) {
                best_energy = energy;
                best = f;
            }
        }
        try std.testing.expectApproxEqRel(drum.fundamental, best, 0.01);
    }
}

test "the snares change the sound and add to the high frequencies" {
    const allocator = std.testing.allocator;
    const rate: u32 = 8000;
    const frames: usize = 4000;

    const plain: Drum = .{ .wire_count = 0 };
    const snared: Drum = .{};
    const a = try plain.render(allocator, rate, 1, 1.0, frames, frames);
    defer allocator.free(a);
    const b = try snared.render(allocator, rate, 1, 1.0, frames, frames);
    defer allocator.free(b);

    var different = false;
    for (a, b) |x, y| {
        if (x != y) different = true;
    }
    try std.testing.expect(different);
    try std.testing.expect(rms(b) != rms(a));
}

test "the contact cannot make the drum blow up without loss" {
    const allocator = std.testing.allocator;
    const rate: u32 = 8000;
    const frames: usize = 16000;
    const drum: Drum = .{ .sigma0 = 0.0, .sigma1 = 0.0, .wire_sigma = 0.0, .strike_force = 200.0, .contact_stiffness = 1.0e9 };

    const samples = try drum.render(allocator, rate, 1, 1.0, frames, frames);
    defer allocator.free(samples);

    var peak: f64 = 0.0;
    for (samples) |s| {
        try std.testing.expect(std.math.isFinite(s));
        peak = @max(peak, @abs(s));
    }
    // The energy cannot grow, so the sound at the end is no louder than the loudest of the hit.
    var late_peak: f64 = 0.0;
    for (samples[frames - 4000 .. frames - 200]) |s| late_peak = @max(late_peak, @abs(s));
    try std.testing.expect(peak > 0.0);
    try std.testing.expect(late_peak <= 1.5 * peak);
}

test "a drum whose highest mode is below the fundamental has no modes" {
    const allocator = std.testing.allocator;
    const drum: Drum = .{ .max_frequency = 100.0 };
    try std.testing.expectError(error.NoModes, drum.render(allocator, 8000, 1, 1.0, 100, 100));
}

test "a response solved for longer than the note gives the same samples as render" {
    const allocator = std.testing.allocator;
    const drum: Drum = .{};

    const direct = try drum.render(allocator, 8000, 2, 0.7, 2000, 2000);
    defer allocator.free(direct);

    const response = try drum.respond(allocator, 8000, 4000);
    defer response.deinit(allocator);
    const shared = try drum.renderWith(allocator, 8000, 2, 0.7, 2000, 2000, response);
    defer allocator.free(shared);

    try std.testing.expectEqualSlices(f64, direct, shared);
}

test "one response serves notes of different volumes and lengths" {
    const allocator = std.testing.allocator;
    const drum: Drum = .{};
    const response = try drum.respond(allocator, 8000, 3000);
    defer response.deinit(allocator);

    const loud = try drum.renderWith(allocator, 8000, 1, 1.0, 3000, 3000, response);
    defer allocator.free(loud);
    const quiet = try drum.renderWith(allocator, 8000, 1, 0.5, 1500, 1500, response);
    defer allocator.free(quiet);

    // The volume only scales the sound, so half the volume is half the samples, up to the fade.
    for (0..1000) |i| try std.testing.expectApproxEqAbs(0.5 * loud[i], quiet[i], 1e-12);
}

test "past the end of the response the drum counts as silent" {
    const allocator = std.testing.allocator;
    const drum: Drum = .{};
    const response = try drum.respond(allocator, 8000, 500);
    defer response.deinit(allocator);

    const samples = try drum.renderWith(allocator, 8000, 1, 1.0, 2000, 2000, response);
    defer allocator.free(samples);

    for (samples[500..]) |s| try std.testing.expectEqual(@as(f64, 0.0), s);
    try std.testing.expect(rms(samples[0..500]) > 0.0);
}

test {
    std.testing.refAllDecls(@This());
}
