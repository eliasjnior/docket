# Docket

> A macOS menu bar app that lists the open pull requests you wrote and the ones waiting for your
> review, with each one's status, how long it has been open and your own local tags, and that
> notifies you — grouped by repository — when someone requests your review, reviews your pull
> request or replies to a comment of yours.

Native Swift, read-only, using the token of the GitHub CLI you are already signed in to.

## Where the plan lives

[`PROJECT.md`](PROJECT.md) holds the problem, the scope and every decision; [`docs/`](docs/) holds
the plan; [`CLAUDE.md`](CLAUDE.md) is the working agreement. This file only covers running the code.

## Current state

`M0` is done: the repository, the gate and an empty menu bar app. `M1` in
[`docs/07-roadmap.md`](docs/07-roadmap.md) is next. The authoritative built / not-built table is in
[`CLAUDE.md`](CLAUDE.md) under "What exists today".

## Requirements

| Tool | Version | Note |
|---|---|---|
| macOS | 15 or later | To run; development on the current macOS |
| Xcode | Current release | Swift 6 toolchain |
| Homebrew | — | For `brew bundle` |
| Node.js | 24 (`.nvmrc`) | Only for commitlint, Biome and lefthook |
| GitHub CLI | Any with `gh auth token` | Signed in with `repo` and `read:org` — [`docs/09-provider-setup.md`](docs/09-provider-setup.md) |

## Getting started

```bash
git clone git@github.com:eliasjnior/docket.git
cd docket
brew bundle                      # xcodegen, swiftlint, gitleaks, gh
corepack enable && pnpm install  # tools and git hooks
gh auth status                   # signed in, with repo and read:org
make -C apps/macos gen build     # generates the Xcode project and builds Debug
open apps/macos/build/Build/Products/Debug/Docket.app
```

The first poll establishes a baseline and sends no notifications; from then on, only what is new.

## Commands

| Command | What it does |
|---|---|
| `./scripts/ci.sh` | Every check; runs on `git push` |
| `make -C apps/macos test` | `DocketKit` tests |
| `make -C apps/macos lint` / `format` | swift-format and SwiftLint |
| `make -C apps/macos install` | Release build, signed, into `/Applications` |
| `swift run --package-path apps/macos/Packages/DocketKit docket-cli poll` | One poll against your account, printed |

## Surprising things

- **The Xcode project is generated** from `apps/macos/project.yml` and not committed. Run
  `make -C apps/macos gen` after pulling.
- **Checks run on your machine, not in CI.** The repository is private and hosted macOS minutes are
  expensive, so `pre-push` is the gate ([`PROJECT.md`](PROJECT.md) D-12).
- **Starting over** is deleting `~/Library/Application Support/Docket/` with the app quit.

## Repository layout

```
apps/macos/App/                 SwiftUI + AppKit: status item, popover, settings, wiring
apps/macos/Packages/DocketKit/  Swift package: one target per concern, all the logic and tests
apps/macos/project.yml          XcodeGen spec
docs/                           The plan
scripts/ci.sh                   The gate
```

## Contributing

Every change is a pull request against `main`, including from the maintainer. The loop is in
[`CLAUDE.md`](CLAUDE.md) and [`docs/06-engineering-practices.md`](docs/06-engineering-practices.md).
