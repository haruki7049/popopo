# popopo

An original piece of music written as code. popopo is composed in [Zig](https://ziglang.org/) with
[lightmix](https://github.com/haruki7049/lightmix): the score, the instruments and the sounds of the
instruments are all source files, and `zig build` renders them into a wav file.

At the moment the piece is the introduction, four bars of an eight beat: a kick, a snare and a
closed hi-hat.

## Requirements

- [Zig](https://ziglang.org/) 0.16.0
- Optionally [Nix](https://nixos.org/): `nix develop` (or `direnv allow`, with `.envrc`) gives a shell
  with Zig 0.16, ZLS and `sox`, and `nix build` builds the piece and runs its tests.

## Build

```sh
zig build            # renders zig-out/share/popopo.wav
zig build play       # plays the produced wave
zig build test       # runs the tests of every module and of the piece
zig build sandbox    # renders the sandbox wav files into zig-out/share/sandbox/
```

`-Dmusic-part=<name>` builds one music part alone instead of all of them joined in order. The only
part now is `introduction`:

```sh
zig build -Dmusic-part=introduction
```

CI runs `zig fmt --check .`, `zig build` and `zig build test` on Linux, macOS and Windows.

## Layout

| Path | What is in it |
| --- | --- |
| `src/` | The piece: the music parts (`scores.zig`), what each line of score is made of (`scores/`), the instruments (`instruments.zig`) and the mix (`root.zig`). |
| `modules/body` | The rule of a vibrating body. |
| `modules/meters` | Metric and time scheduling data structures: layers of score information placed in time. |
| `modules/mix` | Placing and mixing of the sounds, and normalizing the result. |
| `modules/perform` | The procedure that turns the notes of a score into waveforms. |
| `modules/sheets` | Basic pieces of score, written in ZON, that the music parts are built from. |
| `modules/timbre` | Ready-made timbres: kick, snare, cymbals (closed and open hi-hat, crash) and guitar. |
| `sandbox/` | One program for each sound or groove, each rendered into its own wav file by `zig build sandbox`. |

Each module under `modules/` is created with no imports, so it can import nothing but `std` and is
tested alone. The exception is `timbre`, which imports `lightmix` so that each timbre can make a
`lightmix.Wave`. The piece in `src/` is the only place that imports the modules and puts them
together.

## Sandbox

The sandbox renders each sound on its own, which is the way to listen to a timbre while working on
it: `kick-mono`, `kick-stereo`, `snare-mono`, `snare-stereo`, `closed-hihat-mono`, `open-hihat-mono`,
`crash-mono`, and two grooves, `four-on-the-flour` and `eight-beat`.

## License

Licensed under either of

- Apache License, Version 2.0 ([LICENSE-APACHE](LICENSE-APACHE))
- MIT license ([LICENSE-MIT](LICENSE-MIT))

at your option.
