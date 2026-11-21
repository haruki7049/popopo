# Contributing

popopo is an original piece of music written as code. This document describes how to work on it and how it is
versioned.

## Development

### Environment

- [Zig](https://ziglang.org/) 0.17.1 (`minimum_zig_version` in `build.zig.zon`).
- Optionally [Nix](https://nixos.org/): `nix develop` (or `direnv allow`, with `.envrc`) gives a shell with Zig 0.17,
  ZLS, `sox`, `treefmt` and `zon2nix`.

### Layout rules

- `src/` is the piece itself and the only place that imports the modules and puts them together.
- Each module under `modules/` imports nothing but `std` and is tested alone. The exception is `timbre`, which imports
  `lightmix`. Do not add imports between modules.
- `sandbox/` has one program per sound or groove. Use it to listen to a sound while working on it.

See the layout section of [README.md](README.md) for what each directory holds.

### Dependencies

When the dependencies in `build.zig.zon` change, regenerate `.deps.nix` with `zon2nix` so that `nix build` keeps
working.

## Workflow

1. Create a topic branch from the latest `main`. Never commit to `main` directly.
1. Make the change. Keep it small and limited to one purpose.
1. Format the code: `treefmt` (inside `nix develop`), or at least `zig fmt .` when Nix is not available.
1. Run the checks below.
1. Commit with a Conventional Commit message (see below) and push the topic branch.
1. Open a pull request against `main`. Describe what changed and why, and link a related issue from the description with
   a closing keyword (for example `Closes #N`).
1. Wait for CI to pass. The maintainer merges the pull request.

### Checks before you submit

```sh
treefmt --fail-on-change
zig build
zig build test
```

CI runs `zig fmt --check .`, `zig build` and `zig build test` on Linux, macOS and Windows, and `nix flake check` and
`nix build` on Linux and macOS. A change that touches the workflows must also keep `.github/workflows/actions.lock` in
sync, which `verify-actions-lockfile.yml` checks.

If you changed a sound, run `zig build sandbox` and listen to the files in `zig-out/share/sandbox/`. If you changed the
piece, run `zig build` and listen to `zig-out/share/popopo.wav`.

### Commits and pull requests

- Use a Conventional Commit prefix: `feat`, `fix`, `refactor`, `docs`, `build`, `style`, `test`, `perf`, `ci`, `chore`
  or `revert`, optionally with a scope (for example `feat(timbre): add a tom`).
- Write the message in English, in the imperative mood, under 72 characters, without a trailing period.
- Do not put issue numbers in a commit message. Squash merges copy every commit message into `main`, so a closing
  keyword in a commit body can close the wrong issue. Link issues only from the pull request description.
- The pull request title follows the same convention. CI validates it.
- Stage only the files you changed for the task. Do not use `git add -A`.
- Write documentation, code comments, commit messages and pull request descriptions in English.

### AI-assisted contributions

Contributions made with AI agents follow the same rules, plus the rules in [AGENTS.md](AGENTS.md). In short, an agent
may create branches, commits and pull requests, but it never merges a pull request, never pushes to `main`, and never
pushes a tag or changes `version` in `build.zig.zon` unless the maintainer explicitly asks for a release.

## Versioning

popopo uses [Semantic Versioning](https://semver.org/) in the form `X.Y.Z`, or `X.Y.Z-prerelease` such as
`1.0.0-rc.1`. The released artifact is the rendered `popopo.wav`, so compatibility is judged by the SHA-256 hash of
`popopo.wav` (the hash in `SHA256SUMS` of the release), compared with the previous release.

- **Patch**: the change is compatible with the previous release, that is, the SHA-256 hash of `popopo.wav` does not
  change.
- **Minor**: the change is not compatible with the previous release, that is, the SHA-256 hash of `popopo.wav`
  changes.
- **0.x to 1.0.0**: done when the maintainer judges that the piece is ready to be published to everyone.
- **Major (1.x and later)**: done only when the change is one that anyone who listens would call a different piece of
  music, that is, when a different piece is released.

The version is `0.0.0` now.

### The source of truth

The `version` field in `build.zig.zon` is the only source of truth. It is written without a `v` prefix (`0.1.0`, not
`v0.1.0`). Do not create tags by hand.

### Releasing

A release is made by changing `version` in `build.zig.zon` on `main`. Only the maintainer makes a release.

1. Choose the new version with the rules above. Use a pre-release suffix such as `-rc.1` for a release candidate.
1. Open a pull request that changes only the `version` field in `build.zig.zon`. Title it
   `build: bump version to X.Y.Z`.
1. Merge it. The `release.yml` workflow then:
   - reads and validates the version, and stops with an error if it is not `X.Y.Z` or `X.Y.Z-prerelease`;
   - stops without doing anything if the tag `vX.Y.Z` already exists;
   - runs `nix build .#default`, which renders `popopo.wav` and runs the tests in the Nix sandbox;
   - creates the tag `vX.Y.Z` on the merged commit and publishes a GitHub Release with generated notes, `popopo.wav`
     and `SHA256SUMS`. A version with a hyphen is published as a pre-release.
1. Check the workflow run in the Actions tab and confirm that the release looks right.

If the workflow fails after the version bump was merged, fix the cause and run the `Release` workflow again with
`workflow_dispatch` on `main`. A version that was already released is never released twice.
