# Agent Guidelines for `popopo`

This document defines core principles, architectural invariants, and non-negotiable safety rules for AI agents working
on the `popopo` repository.

______________________________________________________________________

## 1. Project Overview & Architecture

`popopo` is an original piece of music written as code. It is composed in Zig with
[`lightmix`](https://github.com/haruki7049/lightmix): the score, the instruments and the sounds of the instruments are
all source files, and `zig build` renders them into a wav file.

- **Development Environment**: Managed with Nix (`flake.nix`), `direnv` (`.envrc`), and `treefmt-nix` for formatting
  Zig, Nix, GitHub Actions, Markdown and shell scripts. `treefmt` is available on `PATH` inside `nix develop` (or via
  direnv) through the default devShell's `inputsFrom`.
- **Target Language Version**: Zig `0.17.1` (`minimum_zig_version` in `build.zig.zon`).
- **Dependencies**: `lightmix` and `pitches`, declared in `build.zig.zon`. The Nix build reads them from `.deps.nix`
  (see "Dependency updates" below).
- **Directory Structure**:
  - `src/`: The piece itself. `root.zig` is the mix, `scores.zig` holds the music parts (currently `introduction`),
    `scores/` holds what each line of score is made of, `instruments.zig` the instruments, and `configs.zig` and
    `primitives.zig` the shared settings and primitives. This is the only place that imports the modules and puts them
    together.
  - `modules/`: Independent building blocks, each with its own `root.zig`:
    - `body`: The rule of a vibrating body.
    - `meters`: Metric and time scheduling data structures.
    - `mix`: Placing and mixing of the sounds, and normalizing the result.
    - `perform`: The procedure that turns the notes of a score into waveforms.
    - `sheets`: Basic pieces of score written in ZON.
    - `timbre`: Ready-made timbres (kick, snare, cymbals, guitar).
  - `sandbox/`: One program per sound or groove, each rendered into its own wav file by `zig build sandbox`.
  - `build.zig` & `build.zig.zon`: Build definition and package metadata. Steps: `zig build` (renders
    `zig-out/share/popopo.wav`), `zig build play`, `zig build test`, `zig build sandbox`, and the option
    `-Dmusic-part=<name>` to build a single music part.
  - `.github/workflows/`: Zig CI (`zig-ci.yml`: `zig fmt --check .`, `zig build` and `zig build test` on Linux, macOS and
    Windows), Nix CI (`nix-ci.yml`: `nix flake check` and `nix build`), PR title validation
    (`pr-conventional-commits-validation.yml`), the actions lockfile check (`verify-actions-lockfile.yml`,
    `actions.lock`), Dependabot auto-merge (`dependabot-auto-merge.yml`), and release (`release.yml`).
- **Module Isolation**: Each module under `modules/` imports nothing but `std` and is tested alone. The exception is
  `timbre`, which imports `lightmix` so that each timbre can make a `lightmix.Wave`. Do not add imports between modules.
  Only `src/` combines them.
- **Dependency updates**: When `build.zig.zon` dependencies change, `.deps.nix` must be regenerated (`zon2nix` is in the
  devShell) so that `nix build` keeps working.

______________________________________________________________________

## 2. Strict Safety & Operational Rules (Always Enforced)

- **NEVER MERGE PULL REQUESTS**: AI agents **MUST NEVER** merge PRs (including enabling auto-merge with
  `gh pr merge --auto`), execute `git merge` into `main`, or directly push commits to the `main` branch autonomously.
- **NEVER RELEASE ON YOUR OWN**: Pushing a `v*` tag publishes a GitHub Release (`release.yml`). AI agents **MUST NEVER**
  push tags or change `version` in `build.zig.zon` unless the user explicitly asks for that release.
- **NEVER PROPOSE COMMITS OR PUSHES UNPROMPTED**: AI agents **MUST NEVER** prompt the user to commit or push, nor
  propose commit messages unprompted. When instructed by the user or when creating/updating pull requests on topic
  branches, agents may execute `git commit` and `git push` directly without seeking confirmation.
- **Mandatory Human Approval**: AI agents may create branches, create commits, push topic branches, propose PRs, format
  code, and run test suites, but the final action of merging changes into `main` rests strictly with the human
  maintainer.
- **Verification Before Submitting**: All changes must pass `treefmt --fail-on-change`, `zig build`, and
  `zig build test`.
- **Conventional Commits**: Use conventional commit prefixes (`feat:`, `fix:`, `refactor:`, `docs:`, `build:`, `style:`,
  `test:`), optionally with a scope (e.g. `feat(hyprland):`). English, imperative mood, under 72 characters, no trailing
  period. PR titles are validated by CI with the same convention.
- **No Issue Numbers in Commits**: Do not put issue numbers anywhere in a commit message, summary or body: squash merges
  copy every commit message into `main`, so a `Closes #24` in a body can close the wrong issue. Link issues only from
  the PR description with closing keywords.
- **Stage Explicitly**: Stage only the files changed for the task (`git add <path>`), never `git add -A`.
- **Evidence First**: Base all answers and actions on actual file contents and command output. Never speculate or
  assume. State plainly what could not be verified.
- **Non-Destructive**: Never perform irreversible actions (file deletions, hard resets, rewriting pushed history such as
  amending or rebasing pushed commits and force-pushing, pushing to `main`) without explicit user approval. Ordinary
  pushes of new commits to a topic branch don't need approval (see above).
- **Targeted Edits**: Make minimal, logical changes strictly necessary for the request. Do not modify unrelated files.
- **English-Only Documentation**: All repository documentation, agent skills, code comments, commit messages, and PR
  descriptions must be written strictly in English.
- **Explicit Milestone Assignment Only**: AI agents **MUST NEVER** automatically attach or set GitHub Milestones on
  Pull Requests or Issues unless explicitly requested or instructed by the user.
- **No Session Links**: Do not include AI session URLs or other internal session identifiers (e.g. a `Claude-Session:`
  trailer) in commit messages, PR descriptions, issues, or comments. A `Co-Authored-By:` trailer is fine.

______________________________________________________________________

## 3. Status Assessment Workflow

When asked to check status, assess the situation, or understand workspace context:

1. **Local Git State**: Inspect working tree (`git status -s -b`) and recent commits (`git log -n 5 --oneline`).
1. **GitHub PRs (always display)**: List **all** open PRs (`gh pr list`) and check the current branch's PR
   (`gh pr status`). Never skip this step, even when the local state is clean.
1. **GitHub Issues (always display)**: List **all** open issues (`gh issue list`). Never skip this step.
1. **Environment Health**: Verify build and test status (`treefmt --fail-on-change`, `zig build`, `zig build test`).
1. **Synthesis**: Report a concise, structured status covering local state, remote GitHub state, and environment
   health. The report **must** include the open PR and Issue lists (number, title, and state), or explicitly state that
   there are none.
