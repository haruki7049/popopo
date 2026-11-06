const std = @import("std");
const l = @import("lightmix");

/// The modules under `modules/`, one per role. Each is created with no `imports`, so it can
/// import nothing but `std`: an `@import` of `lightmix` or of another module fails to compile.
const module_names = [_][]const u8{
    "body", // The rule of a vibrating body
    "meters", // Metric and time scheduling data structures
    "mix", // Place and mix
    "perform", // The procedure that turns values into waveforms
    "sheets", // Music sheets separated by popopo music parts
    "timbre", // Ready-made timbres
};

/// The music parts that can be built with `-Dmusic-part=<name>`; without it, all of them are
/// joined in declaration order. Each tag matches a declaration of the `sheets` module and a
/// branch of `sections` in `src/scores.zig`.
const MusicPart = enum {
    introduction,
    a,
    b,
};

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const music_part = b.option(MusicPart, "music-part", "Build only this music part (default: all parts, joined in order)");

    const lightmix = b.dependency("lightmix", .{});
    const lightmix_import: std.Build.Module.Import = .{ .name = "lightmix", .module = lightmix.module("lightmix") };

    const pitches = b.dependency("pitches", .{});
    const pitches_import: std.Build.Module.Import = .{ .name = "pitches", .module = pitches.module("pitches") };

    const test_step = b.step("test", "Run tests");

    // Modules: no imports. Each runs its own tests, without the others.
    var imports: std.ArrayList(std.Build.Module.Import) = .empty;
    try imports.append(b.allocator, lightmix_import);
    try imports.append(b.allocator, pitches_import);

    for (module_names) |name| {
        // The timbre module is an exception because I wanna create .wave method for each timbres
        const inner_imports: []const std.Build.Module.Import =
            if (std.mem.eql(u8, name, "timbre")) &.{lightmix_import} else &.{};

        const module = b.createModule(.{
            .root_source_file = b.path(b.fmt("modules/{s}/root.zig", .{name})),
            .target = target,
            .optimize = optimize,
            .imports = inner_imports,
        });
        try imports.append(b.allocator, .{ .name = name, .module = module });

        const module_tests = b.addTest(.{ .name = name, .root_module = module });
        test_step.dependOn(&b.addRunArtifact(module_tests).step);
    }

    const build_options = b.addOptions();
    // An enum option cannot be optional: `music_part` only matters when `all_parts` is false.
    build_options.addOption(bool, "all_parts", music_part == null);
    build_options.addOption(MusicPart, "music_part", music_part orelse .introduction);
    try imports.append(b.allocator, .{ .name = "build_options", .module = build_options.createModule() });

    // The piece: the only module that imports `lightmix` and the modules.
    const mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = imports.items,
    });

    // Wave file installation
    const wave = try l.addWave(b, mod, .{
        .optimize = optimize,
        .format = .{ .wav = .{
            .bits = 16,
            .format_code = .pcm,
            .name = "popopo.wav",
        } },
    });
    l.installWave(b, wave);

    const play_step = b.step("play", "Play the produced Wave file");
    const play = try l.addPlay(b, wave, .{});
    play_step.dependOn(&play.step);

    // Tests of the piece
    const mod_tests = b.addTest(.{
        .name = "popopo",
        .root_module = mod,
    });
    test_step.dependOn(&b.addRunArtifact(mod_tests).step);

    // Sandbox
    const sandbox_step = b.step("sandbox", "Generate wav files on sandbox");
    try build_sandbox(b, target, optimize, imports.items, sandbox_step);
}

fn build_sandbox(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    imports: []const std.Build.Module.Import,
    sandbox_step: *std.Build.Step,
) !void {
    const paths_names: []const struct { []const u8, []const u8 } = &.{
        .{ "sandbox/kick-mono.zig", "kick-mono.wav" },
        .{ "sandbox/kick-stereo.zig", "kick-stereo.wav" },
        .{ "sandbox/snare-mono.zig", "snare-mono.wav" },
        .{ "sandbox/snare-stereo.zig", "snare-stereo.wav" },
    };

    inline for (paths_names) |pn| {
        const path = pn.@"0";
        const name = pn.@"1";

        const mod = b.createModule(.{
            .root_source_file = b.path(path),
            .target = target,
            .optimize = optimize,
            .imports = imports,
        });

        try add_sandbox_wave(b, optimize, mod, name, sandbox_step);
    }
}

fn add_sandbox_wave(
    b: *std.Build,
    optimize: std.builtin.OptimizeMode,
    mod: *std.Build.Module,
    name: []const u8,
    sandbox_step: *std.Build.Step,
) !void {
    const wave = try l.addWave(b, mod, .{
        .optimize = optimize,
        .format = .{ .wav = .{
            .bits = 16,
            .format_code = .pcm,
            .name = name,
        } },
        .path = .{ .custom = "share/sandbox" },
    });
    sandbox_step.dependOn(wave.step);
}
