# 08 — Stack

Every technology Docket depends on, why it was chosen, what replacing it would cost, and what was
deliberately not used. Written to be read from outside: the rest of `docs/` explains the product,
this one explains the choices it is made of, so a later project can inherit the reasoning.

Versions are the ones pinned or installed today. They will drift; the reasoning is what should not.

**How to read *Cost to replace*:** **Low** — behind an interface we own, swap the implementation and
keep the callers. **Medium** — a day or two of mechanical change. **High** — it reaches into how the
product is written. That column matters more than the version: a low-cost dependency can be chosen
quickly and revisited cheaply; a high-cost one is a decision that will still be true in three years.

**The departure from the baseline.** The project-docs baseline is a TypeScript server monorepo:
Node, Postgres, Drizzle, Zod, an HTTP framework, containers. Docket is a single-user desktop app
with no server and no database (D-01, D-06, D-10), so every server row of that baseline is absent
and listed in §8 with its reason. What carries over is the repository discipline — Conventional
Commits, a gate before every pull request, squash merges, release-please — and Lookout's native
toolchain, which already proved that discipline works around a Swift app (PROJECT.md principle 7).

## 1. Language and platform

| What | Version | Why | Cost to replace |
|---|---|---|---|
| **Swift** | 6.x language mode, complete strict concurrency (6.4 toolchain today) | The status item, popover, notifications and login item are first-class only here (D-01). Strict concurrency turns the poller/UI split of `03-architecture.md` §11 into a compile-time property | High |
| **macOS** | Minimum 15.0 | Matches Lookout, so both apps share one support floor; `@Observable`, `SMAppService` and Swift Testing are all available | Medium |
| **SwiftUI** | System | Every view: popover, rows, settings, What's New | High |
| **AppKit** | System | `NSStatusItem`, `NSPopover`, `NSWorkspace` sleep and wake notifications — the parts SwiftUI's `MenuBarExtra` does not expose (§8) | Medium |
| **Foundation `URLSession`** | System | The GraphQL client. One endpoint, one header, JSON in and out; `URLProtocol` is the test seam (`03` §7) | Low |
| **UserNotifications** | System | Notifications with `threadIdentifier` grouping, categories and click routing (`02` §7) | Low — behind `NotificationSink` |
| **ServiceManagement (`SMAppService`)** | System | Launch at login without a helper app (FR-90) | Low |
| **Network (`NWPathMonitor`)** | System | Pausing polls while offline (FR-95) | Low |
| **CryptoKit** | System | Ed25519 verification of update archives (D-14) | Low |
| **Security framework** (`SecStaticCode`) | System | Checking a downloaded app's designated requirement before installing it (D-14) | Low |
| **os (`Logger`, `os_signpost`)** | System | Structured logs with privacy annotations (`03` §12); signpost intervals measure popover open time for NFR-06 (`07-roadmap.md` §3) | Low |
| **App Intents (`SetFocusFilterIntent`)** | System | Docket's Focus filter, the only documented way an app without entitlements learns that a Focus started and ended (D-25) | Low |
| **Carbon `RegisterEventHotKey`** | System | The P1 global shortcut (FR-48). It needs no Accessibility permission, unlike an `NSEvent` global monitor, and no package | Low |

**No third-party Swift package is a runtime dependency.** Every row above ships with macOS. That is
deliberate: the app reads one API and writes three files, and each package added would be a supply
chain entry in a binary that holds a token with `repo` scope.

## 2. External services

| What | Why | Cost to replace |
|---|---|---|
| **GitHub GraphQL API** (`api.github.com/graphql`) | One query returns status, reviews, threads and requests for many pull requests, priced by page size (`02` §6.2). REST would need several calls per pull request | High — it is the product's only data source |
| **GitHub REST API** | Two narrow uses: `GET /organizations/{id}` to name an organization from an SSO header (`03` §6), and Releases for the updater (D-14) | Low |
| **GitHub CLI** (`gh`) | Source of the token (D-02); 2.101 installed today, any version with `gh auth token` works | Medium — the fallback named in D-02 is a classic token behind the same `TokenProvider` port |
| **GitHub Releases** | Distribution and update source, no appcast or update server (D-14) | Medium |

## 3. Testing

| What | Version | Why | Cost to replace |
|---|---|---|---|
| **Swift Testing** (`import Testing`) | Toolchain | Parameterized tests carry the worked examples of `02-activity-detection.md` §8 as rows; it is what Lookout uses | Medium |
| **`DocketTestSupport`** | Ours, test-only target | Seeded generators and snapshot builders for the properties of `06-engineering-practices.md` §10.2, shared by the test targets | Low |
| **`URLProtocol` stub** | Ours, in `DocketGitHubTests` | Replaces GitHub at the network edge, so the real client is the code under test (`03` §7) | Low |
| **`llvm-cov`** (`xcrun llvm-cov report`) | Toolchain | Reads `swift test --enable-code-coverage` output; `check-coverage.sh` fails the gate under NFR-09 | Low |

## 4. Build and release

| What | Version | Why | Cost to replace |
|---|---|---|---|
| **Xcode** | The one on the release runner's `macos-26` image, and locally | Builds and signs the app | High |
| **XcodeGen** | 2.46.0 | `project.yml` is reviewable; the `.xcodeproj` is generated and never committed, so there are no project-file merge conflicts. As in Lookout | Medium — commit the generated project and edit it in Xcode |
| **SwiftPM** | Toolchain | `DocketKit`'s target graph is the boundary rule (`03` §3) | High |
| **GNU Make** | System | `apps/macos/Makefile` is the one entry point for `gen`, `build`, `test`, `lint`, `format`, `install`, `ci`, as in Lookout | Low |
| **release-please** (`googleapis/release-please-action@v5`) | v5 | Version, changelog and tag from Conventional Commits; the changelog is also What's New (FR-94) | Medium |
| **GitHub Actions** | `actions/checkout@v7`, `pnpm/action-setup@v6`, `actions/setup-node@v7`, pinned by major version | Only the Ubuntu `pr` workflow and the `Release` build on `macos-26` (D-12, `06-engineering-practices.md` §9) | Medium |
| **Dependabot** (`.github/dependabot.yml`) | — | Version updates for npm devDependencies and Actions, as pull requests through the same loop, as in Lookout | Low |
| **`codesign`, self-signed identity** | System | Stable designated requirement without a paid account (D-15) | Low |

## 5. Tooling

| What | Version | Why | Cost to replace |
|---|---|---|---|
| **swift-format** | Toolchain (`swift format`) | Formatting that ships with the compiler; config copied from Lookout's `.swift-format` | Low |
| **SwiftLint** | 0.65.1 | Rules swift-format does not have — force unwraps, file length, custom rules; `--strict`, as in Lookout | Low |
| **Node.js** | 24 (`.nvmrc`) | Only to run the JavaScript tools below. Nothing in the app is JavaScript | Low |
| **pnpm** | 11.25.0, pinned in `packageManager`, via corepack | Lockfile for the three tools below; one command set shared with Lookout (D-11) | Low |
| **Biome** | 2.5.15 | Formats and lints the repository's JSON and the JavaScript config files | Low |
| **commitlint** (`@commitlint/config-conventional`) | 21.2.3 | Conventional Commits in `commit-msg` and in `scripts/ci.sh`; squash merge makes the pull request title the commit, so the title is checked too | Low |
| **lefthook** | 2.2.2, a pnpm devDependency | Hooks for a repository whose files are mostly not JavaScript: per-root globs (`root: apps/macos/`), parallel jobs, one YAML file. As in Lookout | Low |
| **gitleaks** | 8.30.1 (Homebrew locally, `ghcr.io/gitleaks/gitleaks:v8.30.1` in the `pr` job) | Staged files in `pre-commit`, the branch range in `scripts/ci.sh`, and the pull request job — the repository is private now and written as if public (`04-data.md` §6) | Low |
| **Homebrew Bundle** (`Brewfile`) | — | `xcodegen`, `swiftlint`, `gitleaks`, `gh` in one `brew bundle` | Low |

## 6. Code we own instead of depending on

| What | Where | Why not a dependency |
|---|---|---|
| GraphQL client | `DocketGitHub` | Two documents, one endpoint, typed by `Decodable`. A GraphQL client library would add code generation and a normalized cache for a client that needs neither (§8) |
| Updater | `DocketUpdate`, copied from `LookoutUpdate` | D-14 |
| JSON stores with atomic writes | `DocketPersistence` | D-10 |
| Activity rules | `DocketActivity` | They are the product (`02-activity-detection.md`) |

## 7. Versions and pinning

- Swift and Xcode follow the runner image and the local install; the language mode is pinned in
  `project.yml` (`SWIFT_VERSION: "6.0"`, `SWIFT_STRICT_CONCURRENCY: complete`).
- JavaScript tools are pinned exactly in `package.json` and the lockfile. Dependabot proposes
  updates as pull requests that go through the same loop.
- Homebrew tools are not pinned. A lint rule that changes behaviour with a SwiftLint upgrade is
  caught by the gate on the next push and fixed in its own pull request.

## 8. What was deliberately not used

An absence leaves no trace in a lockfile, so it leaves one here.

| Not used | Why |
|---|---|
| **A server, PostgreSQL, Drizzle, an HTTP framework (Elysia, Hono)** | There is nothing to serve and no shared state: one user, one Mac, polling (D-06). Each would be infrastructure for a problem this product does not have |
| **Zod or any schema library** | Swift's `Decodable` is the boundary parser: a GraphQL response that does not match the model fails to decode at the edge, which is the property Zod buys in TypeScript |
| **SQLite, GRDB, SwiftData, Core Data** | D-10. A dictionary of a few hundred tags and cursors does not need a query engine or migrations |
| **Webhooks or a GitHub App** | D-06: a public endpoint and an installation by an organization owner |
| **Docket's own OAuth app, device flow, or a stored personal access token** | D-02: each needs an approval or a second credential |
| **GitHub's `/notifications` endpoint** | D-07: it reports threads and reasons, not events, and it is the user's shared inbox |
| **Octokit or another GitHub SDK** | We use two queries and two REST calls; their failure modes — SSO headers, partial errors, rate limits — are ours to handle, and `URLProtocol` is the whole test strategy |
| **Apollo iOS** | Code generation, a normalized cache and a schema download for two hand-written documents (§6) |
| **`MenuBarExtra`** | It hides the `NSStatusItem`, so there is no control over the count rendering, the click behaviour or the popover's lifecycle. Lookout uses `NSStatusItem` for the same reason |
| **Sparkle** | D-14 |
| **Electron, Tauri, a web view** | D-01 |
| **Avatars and image caching (Kingfisher, Nuke)** | `04-data.md` §5 |
| **Turborepo** | D-11: one app, no task graph |
| **Husky, lint-staged** | lefthook does both, with per-directory roots, and it is what Lookout runs |
| **ESLint, Prettier** | Biome covers the little JavaScript and JSON there is |
| **XCTest** | Swift Testing replaces it for new code; there is no legacy suite |
| **SwiftCheck or another property-testing library** | Its shrinking is the feature worth having; it loses to a hundred lines of seeded generators in `DocketTestSupport` because failing cases become named examples by hand anyway (`06-engineering-practices.md` §10.2) |
| **KeyboardShortcuts and other hot-key packages** | Carbon's `RegisterEventHotKey` does the one shortcut FR-48 needs |
| **`amannn/action-semantic-pull-request`** | Lookout uses it for the title check; Docket runs commitlint on the title instead, so one configuration governs commits and titles (`06-engineering-practices.md` §9.1) |
| **`INFocusStatusCenter`** | D-25: needs an entitlement only a provisioning profile grants, and reports a boolean only when Focus status is shared |
| **Reading `~/Library/DoNotDisturb/DB`** | D-25: undocumented, behind Full Disk Access, and changes between releases |
| **Idle detection (`CGEventSource`, IOKit `HIDIdleTime`, screen-lock notifications)** | D-26: reminders do not read presence, so nothing needs to know whether anybody is at the Mac |
| **Mocking frameworks** | Tests replace the network, the process runner and Notification Center at their edges, never our own modules (`03` §7) |
| **Crash reporters and analytics (Sentry, TelemetryDeck)** | PROJECT.md principle 4: nothing leaves the Mac except requests to GitHub |
| **Notarization and a paid Apple Developer account** | D-15 |
| **Hosted macOS CI for every pull request** | D-12: ten times the minute cost on a private repository. Reopens when the repository goes public |
