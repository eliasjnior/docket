# Popover Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the redesign, triage and AI actions of the spec as a stack of open pull requests the
maintainer installs and tests before anything is merged.

**Architecture:** The rules are pure functions in `DocketActivity`: the bot test, human activity,
triage, seen, filters, Mine groups, Jira and command scripts. The new GitHub fields are added in
`DocketGitHub`. The views stay wiring in the app target. The terminal launcher is an adapter in
`App/Sources/Environment/`.

**Tech Stack:** Swift 6, SwiftUI with AppKit, SwiftPM (`DocketKit`), Swift Testing, XcodeGen.

**Spec:** `docs/superpowers/specs/2026-10-21-popover-redesign-design.md`

## Global Constraints

- Every non-negotiable of `CLAUDE.md` applies.
  - `DocketActivity`/`DocketCore` never call `Date()` and never do I/O.
  - Copy goes in `Localizable.xcstrings`, synced with `make strings`.
  - Fixtures are synthetic (`acme/api`, `ana`, `you`).
  - The token never reaches a child process.
- Coverage floors: 90% for `DocketActivity` lines and 75% for `DocketKit`.
- Each PR is under ~400 changed lines, excluding fixtures and snapshots.
- PRs are stacked. Each is opened against the previous task's branch, labelled `needs-human` when a
  condition applies, and **never merged** (maintainer's decision).
- New config and state fields are additive. They decode with defaults, so file versions stay at 1.
- A PR that changes behaviour in `docs/01`–`05` updates those docs in the same PR.

## Review Focus

1. A PR title with `$(…)`, a backtick, `'` or a newline reaches the terminal script. It must stay
   one literal word. Task 6: `hostileValuesStayLiteral`.
2. A Dependabot rebase on a PR you already saw must not bring it back to unseen or out of Stale.
   Task 1: `botPushIsNotHumanActivity`.
3. When the seen feature is first installed, 62 listed PRs must not all light up. Task 3:
   `firstRunMarksEverythingSeen`.
4. Five review requests arrive in one poll from five repositories. The result is at most five
   notifications: four individual ones and an overflow. Task 2: `manyRequestsStillCapped`.
5. Changing "Extra bot logins" takes effect without waiting for a pull request to change, because
   the stamps are stored raw and judged at read time. Task 1: `extraBotLoginsApplyAtReadTime`.

---

### Task 1: GitHub fields and human activity

**Files:**
- Modify: `DocketCore/Model/PullRequest.swift`. Add these fields:
  - `labels: [Label]`
  - `headRefName: String?`
  - `issueLinks: [URL]`
  - `headCommit: CommitStamp?`
  - `lastForcePush: ActivityStamp?`
- Create: `DocketCore/Model/ActivityStamp.swift`. It holds three types:
  - `ActivityStamp { login: String; isBot: Bool; at: Date }`
  - `CommitStamp { login: String?; name: String?; at: Date }`
  - `Label { name: String; color: String }`
- Modify: `DocketCore/Files/SnapshotCache.swift`. Add `CachedPullRequest.activity: [ActivityStamp]`:
  the latest stamp per login from the detail, kept from the previous cache when there is no detail.
- Modify: `DocketCore/Files/Config.swift`. Add `triage: Config.Triage` with these fields:
  - `staleAfterDays = 7`
  - `extraBotLogins: [String] = []`
  - `countBots = true`
  - `countStale = false`
- Create: `DocketActivity/HumanActivity.swift`.
- Modify: `DocketGitHub/Queries.swift` and `PullRequestDTO.swift`.
  - The summary reads `body headRefName labels(first:10){nodes{name color}}`.
  - The head commit reads `committedDate author{name user{login}}`.
  - The summary also reads `timelineItems(last:1,itemTypes:[HEAD_REF_FORCE_PUSHED_EVENT])`.
  - The body is reduced to `issueLinks` (URLs whose path matches `/browse/[A-Z][A-Z0-9]+-\d+`) and is
    never kept.
- Modify: `DocketActivity/PollEngine.swift`. `cachedEntry` fills `activity`.
- Tests: `DocketActivityTests/HumanActivityTests.swift` and `DocketGitHubTests` (summary fixture).

**Interfaces (produces):**
- `Bots.isBot(_ actor: Actor?, extra: [String]) -> Bool`
- `Bots.isBot(commit: CommitStamp, extra: [String]) -> Bool`. True when the login or the name ends in
  `[bot]`, or the login is in `extra`.
- `HumanActivity.stamps(in detail: PullRequestDetail) -> [ActivityStamp]`. Covers reviews, comments,
  thread comments and request-event actors, keeping the latest stamp per login.
- `HumanActivity.last(_ cached: CachedPullRequest, excluding viewer: String?, extra: [String]) -> Date?`
  - Takes the max over non-bot stamps, plus the head commit if its author is not a bot, plus the force
    push if its actor is not a bot.
  - With `viewer` set, stamps by the viewer are skipped.

- [ ] Write the tests:
  - `stampsKeepLatestPerLogin`
  - `botPushIsNotHumanActivity`: a dependabot force push and a `[bot]`-named commit leave `last` at
    the human comment's date.
  - `viewerExcludedForOthers`
  - `extraBotLoginsApplyAtReadTime`: the same cached entry gives a different `last` when `extra`
    changes.
  - the summary DTO maps `labels`, `headRefName` and `issueLinks`, and `body` is not stored.
- [ ] Run `swift test --package-path apps/macos/Packages/DocketKit` and expect FAIL.
- [ ] Implement, then run the same command and expect PASS.
- [ ] Update `02` §6.1 and §6.2 (fields, cost) and `04` §2.1 and §2.3 (new fields).
- [ ] Commit and push through the gate. Open PR 1 against `main`, labelled `needs-human` for the
  public `DocketCore` types.

### Task 2: Triage, count, notifications

**Files:**
- Create: `DocketActivity/Triage.swift`.
- Modify:
  - `DocketActivity/WatchedPullRequest.swift`: add `triage: Triage?` (nil unless `reviewRequested`)
    and `isUnseen`, and `Watch.items(…, now:)`.
  - `DocketActivity/Count.swift`
  - `DocketActivity/Reminders.swift`: `Context.excluded: Set<String>`.
  - `DocketActivity/PollEngine.swift`: drop `reviewRequested` events and reminders for excluded IDs.
  - `DocketActivity/Coalesce.swift`: the `reviewRequested` key includes `pullRequestID`.
  - `DocketNotify/ComposedNotification.swift`: the single `reviewRequested` title becomes
    `@ana is waiting for your review`.
  - `DocketStores/WatchStore.swift`: inject `now: () -> Date`.

**Interfaces (produces):**
- `enum Triage: String, CaseIterable { case humans, bots, stale }`
- `Triage.of(_ cached: CachedPullRequest, viewer: String?, config: Config, now: Date) -> Triage`
  - Stale when `now - max(HumanActivity.last(excluding: nil), createdAt) >= staleAfterDays * 86400`.
  - Otherwise bots when the author is a bot.
  - Otherwise humans.
- `Triage.isExcluded(_ triage: Triage, config: Config.Triage) -> Bool`. True for bots when
  `!countBots`, and for stale when `!countStale`.

- [ ] Write the tests:
  - `staleWinsOverBots`
  - `freshRequestOnOldPullRequestIsNotStale`: a request event by a human counts.
  - `staleExcludedFromCountByDefault`
  - `botsCountByDefault`
  - `staleRequestDoesNotNotifyOrRemind`
  - `oneNotificationPerReviewRequest`: three requests in `acme/api` give three notifications.
  - `manyRequestsStillCapped`: seven requests give four individual notifications plus an overflow.
- [ ] Run and expect FAIL. Implement. Run and expect PASS.
- [ ] Update `02` §4, §5.7 and §7.1, `05` §8, and add worked examples #43–#45 in `02` §8.
- [ ] Commit, push, and open PR 2 against PR 1's branch, labelled `needs-human`.

### Task 3: Seen and unseen

**Files:**
- Modify: `DocketCore/Files/PersistedState.swift`. Add `seen: [String: Date]` and
  `seenBaselineAt: Date?`.
- Modify: `DocketActivity/PollEngine.swift`. When `seenBaselineAt == nil`, every cached ID is seen at
  `now`, then `seenBaselineAt = now`.
- Modify: `DocketActivity/WatchedPullRequest.swift`. `isUnseen = seen == nil ||
  HumanActivity.last(excluding: viewer) > seen`.
- Modify: `DocketPersistence/Retention.swift`. Prune `seen` keys with no cursor.
- Modify: `DocketStores/WatchStore.swift` and the app's `AppEnvironment`. Add
  `markSeen(_ ids: [String])`, which goes through `Poller.updateState`.

- [ ] Write the tests:
  - `firstRunMarksEverythingSeen`
  - `newPullRequestAfterBaselineIsUnseen`
  - `humanCommentAfterSeenMakesUnseen`
  - `botCommentAfterSeenStaysSeen`
  - `ownCommentStaysSeen`
  - `retentionDropsSeenForGonePullRequests`
- [ ] Run and expect FAIL. Implement. Run and expect PASS.
- [ ] Update `04` §2.2 and `01` (FR-46 is replaced by seen/unseen).
- [ ] Commit, push, and open PR 3 stacked, labelled `needs-human`.

### Task 4: Labels instead of tags, filters, Mine groups

**Files:**
- Delete:
  - `DocketCore/Model/Tags.swift`
  - `DocketStores/TagStore.swift` (the `SelectionStore` part moves to `SelectionStore.swift`)
  - `App/Sources/Popover/TagEditorView.swift`
  - the tag tests
- Modify: `Config` (drop `tags`, add `mineLayout: MineLayout = .list`) and `Retention` (drop tags).
- Create: `DocketActivity/PopoverFilter.swift`.
- Modify: `DocketActivity/Sections.swift`.

**Interfaces (produces):**
- `struct PopoverFilter: Hashable { organizations, repositories, labels: Set<String>; statuses: Set<Status> }`
  - `matches(_ item: WatchedPullRequest) -> Bool`: OR within a dimension, AND across dimensions,
    names compared case-insensitively.
  - `isEmpty`
- `Sections(_ items: [WatchedPullRequest], filter: PopoverFilter = PopoverFilter())`
  - `reviewRequested(_ triage: Triage) -> [RepositoryGroup]`
  - `triageCounts: [Triage: Int]`
  - `mine: [MineGroup]` with `MineGroup { kind: MineKind (.ready, .blocked, .draft); items }`
- `MineKind.of(_ item: WatchedPullRequest) -> MineKind`. Draft first, then blocked when the status is
  in `[.conflict, .checksFailing, .changesRequested]`, otherwise ready.
- `enum Config.MineLayout: String { case list, board }`

- [ ] Write the tests:
  - `filterOrWithinAndAcross`
  - `draftAlwaysDraft`
  - `blockedStatuses`
  - `mineGroupsInOrderReadyBlockedDraft`
  - `triagePartitionsReviewRequested`
  - `configWithOldTagsStillDecodes`
- [ ] Run and expect FAIL. Implement. Run and expect PASS.
- [ ] Update `01` (FR-80…83 replaced by labels, and FR-82 by multi-filters), `04` and `05` §6.4 and
  §6.6.
- [ ] Commit, push, and open PR 4 stacked, labelled `needs-human` for the public type and the
  on-disk change.

### Task 5: The popover UI

**Files:**
- Modify:
  - `App/Sources/Popover/PopoverView.swift`
  - `SectionsView.swift`
  - `RowView.swift`
  - `Chips.swift`
  - `PopoverModel.swift`
  - `RowActions.swift`
  - `RowAccessibility.swift`
  - `Support/Theme.swift`
  - `Support/Snapshots.swift`
  - `Settings/SettingsView.swift`: the Mine layout picker in General, and triage settings in
    Notifications.
- Create:
  - `Popover/HeaderView.swift`: logo, name, spinning refresh, settings.
  - `Popover/TabBar.swift`: segmented tabs with the count circle.
  - `Popover/FilterBar.swift`: sub-tabs, `•••` actions and filter chips.
  - `Popover/MineView.swift`: list and board.

Behaviour (spec §2, §6, §7):
- Group headers are pinned with `LazyVStack(pinnedViews: [.sectionHeaders])`.
- Opening a pull request calls `markSeen`.
- Unseen rows get the accent tint and a semibold title.
- The popover is about 620 pt wide on Mine with Board selected, and 380 pt elsewhere.

- [ ] Add snapshot states:
  - `popover-triage`
  - `popover-filters`
  - `popover-mine-list`
  - `popover-mine-board`
  - `popover-unseen`
- [ ] Run `make -C apps/macos build`, render with `Docket --snapshot`, and inspect the PNGs in light
  and dark.
- [ ] Run `make strings` and update `05` §4–§6 and §9.
- [ ] Commit, push, and open PR 5 stacked.

### Task 6: Jira and AI actions

**Files:**
- Create: `DocketActivity/Jira.swift` and `DocketActivity/CommandScript.swift`.
- Create: `App/Sources/Environment/TerminalLauncher.swift`. It writes `<tmp>/Docket/<uuid>.command`
  with mode `0700` and opens it with `NSWorkspace` in the chosen app.
- Create: `App/Sources/Settings/AISettingsView.swift`.
- Modify: `Config`. Add `integrations: Config.Integrations` with these fields:
  - `jiraBaseURL: String?`
  - `terminalApp: String?` (a bundle path; nil means the `.command` handler)
  - `reviewCommand`
  - `summarizeCommand`
  - `clones: [String: String]`
- Modify: the row context menu.
- Modify: `PROJECT.md` §6 to add D-28.

**Interfaces (produces):**
- `Jira.link(for pullRequest: PullRequest, base: String?) -> URL?`. The order is: an `issueLinks`
  entry on the base's host, then a key in the title, then a key in `headRefName`. The result is
  `<base>/browse/<KEY>`.
- `CommandScript.render(template: String, values: [String: String], directory: String?) -> String`.
  - Keys are `url`, `repo`, `number`, `title` and `branch`.
  - It scans the template's quote state. `{x}` becomes `"${DOCKET_X}"` outside quotes and
    `${DOCKET_X}` inside double quotes, and is left as is inside single quotes.
  - The script is `#!/bin/zsh`, then `rm -f -- "$0"`, then the single-quoted `export` lines, then
    `cd -- '<dir>' || exit 1` (or a `mktemp -d` folder), then the command.
- `CommandScript.placeholdersInSingleQuotes(_ template: String) -> [String]`, for the Settings
  warning.
- Default commands:
  - review: `claude "Review the pull request {url}. Read the diff, the description and the review comments with gh. Report bugs, risky changes and missing tests, citing file and line."`
  - summarize: `claude "Summarize the pull request {url} in a few sentences: what it changes and why. Read it with gh."`

- [ ] Write the tests:
  - `jiraPrefersBodyLink`
  - `jiraFallsBackToTitleThenBranch`
  - `jiraNilWithoutBase`
  - `hostileValuesStayLiteral`: render, run with `/bin/zsh -n` in the test to check the syntax, then
    run with `echo` substituted for `claude` and assert the output equals the hostile title.
  - `placeholderInSingleQuotesWarns`
- [ ] Run and expect FAIL. Implement. Run and expect PASS.
- [ ] Update `05` §6.5 and §9, `03` (the launcher adapter), and `01` (new FRs).
- [ ] Commit, push, and open PR 6 stacked, labelled `needs-human` for D-28.

### Task 7: Install and hand over

- [ ] Update `CLAUDE.md` "What exists today" in PR 6, or in a docs PR stacked on it.
- [ ] Run `make -C apps/macos install` from the top branch and confirm `/Applications/Docket.app`
  runs a poll. Check with `docket-cli poll` and the logs.
- [ ] Hand the maintainer the list of PRs and the manual test list.
