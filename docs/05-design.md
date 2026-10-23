# 05 — Design

How Docket looks and reads: the status item, the popover and its rows, the status pills and labels,
every account and error screen, notification composition, settings, and the checklist a
screen is reviewed against. The rules that decide *what* is shown are in
[`02-activity-detection.md`](02-activity-detection.md); this document decides how.

## 1. What to avoid

Three failures are common in menu bar tools for GitHub, and each one breaks a principle of
`PROJECT.md` §3.

**A web dashboard squeezed into a popover.** Avatars in circles, brand-coloured headers, card
shadows, a custom font, a dark theme that ignores the system appearance. It is what an Electron
tray app looks like by default, and it is the reason D-01 chose Swift: the popover sits directly
under the menu bar and next to Control Center, and anything that does not use the same materials
reads as foreign. Avatars are also excluded on data grounds (`04-data.md` §5).

**Status by colour alone.** A red, yellow or green dot per row is unreadable to a colour-blind user,
invisible in a screenshot pasted into Slack in greyscale, and ambiguous between "conflict" and
"checks failing", which are both red and need different actions. NFR-11 forbids it: every status is
a symbol, a word and a colour, and the word is the one that carries the meaning.

**Badge noise.** A count that includes every open pull request, a red badge behind the number, a
number that bounces when it changes. The count in the menu bar is a promise as strong as a
notification: it is the number of pull requests that need you (`02-activity-detection.md` §4), and
it is rendered as plain text beside the icon, like the battery percentage.

## 2. Thesis

Docket looks like it shipped with macOS. It uses the popover's own material, the system font at the
system's text styles, SF Symbols, `NSColor` semantic colours that follow light, dark and Increase
Contrast without a line of theme code, and the controls of System Settings. It has no brand colour
inside the interface; the only colour is status, and status is always also a symbol and a word.
It is quiet: nothing moves unless the user acted, the count is the only thing visible without a
click, and a screen that has nothing to say says so in one line. The test of every screen is whether
it could be mistaken for a panel of a first-party app.

## 3. Component stack

| Piece | Built with | Why |
|---|---|---|
| Status item | `NSStatusItem` with an `NSStatusBarButton`, template image and attributed title | SwiftUI's `MenuBarExtra` cannot show a right-click menu, set `appearsDisabled`, or anchor a popover programmatically for a notification click (FR-59) |
| Popover | `NSPopover`, `behavior = .transient`, hosting a SwiftUI view through `NSHostingController`, as Lookout's `HostedPopover` does | The system popover material and arrow for free; `.transient` closes it on the first click elsewhere |
| Lists, chips, banners, the board | SwiftUI | Declarative state from `WatchStore` (`03-architecture.md` §4) |
| Settings | SwiftUI `Settings` scene with a toolbar-style `TabView` and grouped `Form`s | The System Settings look with no custom layout |
| Icons | SF Symbols only | Matches the menu bar's own glyphs at every weight and scale |
| Notifications | `UNUserNotificationCenter` through `DocketNotify` | `03-architecture.md` §3 |

**`NSMenu` with custom item views was the alternative** for the list, and many menu bar apps use
it. It lost on the filters and the board: a menu cannot host chips, sub-tabs or columns, a context menu
inside a menu is not possible, and long lists in a menu scroll by hovering over an arrow. The
popover keeps the right-click menu of the status item (§4) for the three menu-like actions.

**No third-party UI library, no custom font, no web view, no image cache.** Each would be the first
step towards §1's dashboard.

## 4. The status item

**Icon.** The SF Symbol `arrow.triangle.pull` as a template image (`isTemplate = true`), at the
menu bar's default point size and `.regular` weight, so it tints with the menu bar in light, dark
and tinted wallpapers. Lookout draws its own mark (`lookout/docs/brand`); Docket uses a system
symbol because a pull request already has one, and a custom mark at 16 px would be a weaker version
of it. **Revisit if** the app icon gets a mark that survives at menu bar size.

**Count.** Plain text after the icon in `NSFont.menuBarFont(ofSize: 0)` with monospaced digits, no
badge, no background.

| Count | Shown |
|---|---|
| 0 | The icon alone, no number (FR-40) |
| 1–99 | The number: `7` |
| ≥ 100 | `99+` |
| Both halves off in settings (`count.*`, `04-data.md` §2.1) | The icon alone, always |

The count never animates. Monospaced digits keep the item's width stable from `9` to `10` within
one digit's advance, so the items to its left do not jump on every poll.

**States.** The item never goes blank: it always shows the icon, so the user can always click it.

| State | Icon | Count slot | Tooltip and VoiceOver label |
|---|---|---|---|
| Normal | Template icon | Count per the table above | `5 pull requests need you` / `Nothing needs you` |
| Loading, first poll of a launch with no cache | Template icon | Empty | `Loading pull requests` |
| Offline | Template icon, `appearsDisabled = true` | Cached count, dimmed with the icon | `Offline. Showing data from 14:03` |
| Rate-limited (`02` §6.3) | Template icon, `appearsDisabled = true` | Cached count, dimmed | `Paused by GitHub's rate limit until 14:30` |
| Setup needed: `gh` missing, signed out, missing scopes | Template icon | `exclamationmark.triangle.fill`, template, at cap height | `Docket needs attention: GitHub CLI not signed in` |
| Error: last poll failed for another reason, cache older than two intervals | Template icon | Cached count followed by `exclamationmark.triangle.fill` | `Last update failed at 14:03` |

SAML on one organization (FR-13) does not change the item: the other organizations still work and
their count is correct. The banner in the popover is where it is said.

**Clicks.** Left click toggles the popover. Right click, or Control-click, opens an `NSMenu` with
`Refresh` (`⌘R`), `Settings` (`⌘,`) and `Quit Docket` (`⌘Q`), so the app can be quit without
opening the popover.

## 5. The popover

### 5.1 Frame

| Property | Value | Why |
|---|---|---|
| Width | 460 pt; 640 pt while *Mine* is shown as a board | Three equal tabs fit `Review requested` and its count circle with room on both sides; three board columns need the room |
| Height | Fixed: 640 pt or the screen's visible height minus 40 pt, whichever is smaller, whatever the list holds. A full screen (§7.1) keeps its content height | A popover that followed its rows jumped on every fold and tab switch; a fixed one never runs off a 13-inch screen |
| Scrolling | The list scrolls; the header, tabs and filters stay fixed | Refresh and the filters are always reachable |
| Background | `windowBackgroundColor`, solid; group headers add a raised band | Through the popover's vibrant material, text read pale and see-through |

### 5.2 Layout

```
┌──────────────────────────────────────────────────── 460 pt ┐
│  [icon] Docket                                    ⟳     ⚙  │  header
│  ⚠  acme requires SAML authorization.        [Authorize]   │  banners, §7.2
│ ┌─────────────────────────────────────────────────────────┐ │
│ │ ( Review requested  (62) )   Mine  (5)   Involved  (4)  │ │  tabs: segmented, count circle at the trailing edge
│ └─────────────────────────────────────────────────────────┘ │
│  (Humans 14) (Bots 31) (Stale 17)                   [•••]   │  sub-tabs, Review requested only; actions menu
│  [Org: acme, globex ✕] [Label: backend ✕] [+ Filter]        │  filter chips
├─────────────────────────────────────────────────────────────┤
│ [A] acme / api                                         (3)  │  repository header, pinned while scrolling
│ ┃ Rate-limit the export endpoint                            │  row, §6.1
│ ┃ #490 (◌ Checks running) @bruno [backend]            1h    │
└─────────────────────────────────────────────────────────────┘
```

**Header.** The app icon at 22 pt, `Docket` in `.headline`, a refresh button with `arrow.clockwise`
(FR-45, `⌘R`) and a settings button with `gearshape` that opens a menu of `Settings`,
`Check for Updates` and `Quit Docket`. The refresh symbol spins while a poll runs; there is no
`Updating…` text. When the list is older than two poll intervals, a banner reads
`Updated N min ago` (FR-44, §7.2).

**Tabs.** A segmented control the width of the popover: *Review requested*, *Mine*,
*Involved*, and *Ignored* while something is ignored, 28 pt tall. The segments are of equal width, and each
centres its label and its count circle together, the number centred in the circle. The selected
segment is filled with the accent colour, its label white and its circle white with accent digits.
When four segments do not fit, a label shrinks to 75% before it truncates. A first version pinned the
circle to the trailing edge with the label centred across the segment; a long label then ran into its
circle.

**Sub-tabs.** In *Review requested* only: `Humans`, `Bots`, `Drafts` and `Stale` (`02` §3.6) as pills with
the same count circle, `Humans` selected by default. The selected sub-tab is kept for the life of the
process. At the end of the row, `•••` opens the actions menu: `Mark All as Seen` marks every row of
the visible list seen (FR-46). In the other tabs the actions menu ends the filter row.

**Filters.** One chip per active dimension, `Org: acme, globex ✕`, then `+ Filter`: a menu per
dimension (organization, repository, label, status) listing the values in the current tab with their
counts, each a toggle. Several values combine with OR within a dimension and AND across them
(FR-82). `✕` clears a dimension; `Escape` clears the most recently added one, then closes the
popover. A click on a grouped notification opens the popover with that repository as the only filter
(FR-59). When the chips do not fit, a dimension with several values shows its count.

### 5.3 Sections and order

| Section | Contains (role, `02` §2.2) | Order |
|---|---|---|
| **Review requested** | `reviewRequested`, in the selected sub-tab | Grouped by repository. Groups ordered by their newest request, newest first; rows inside a group by request time, newest first. Ties by `owner/name`, then `#number` |
| **Mine** | `authored` | Three groups in this order: **Ready** (not a draft, not blocked), **Blocked** (not a draft; `conflict`, `checksFailing` or `changesRequested`), **Draft** (every draft). Inside a group, by status in the precedence order of `02-activity-detection.md` §3.2, then newest first. Shown as stacked sections or as a board (`config.mineLayout`) |
| **Involved** | `involved` | By `updatedAt`, most recent first |
| **Ignored** | Any role, ignored (FR-49) | By `ignoredAt`, most recent first. Rows in `text.secondary`, no status colour: nothing here asks for attention |

A **repository header** is a raised band: an 18 pt rounded square in a colour derived from the
repository name (FNV-1a into blue, purple, pink, teal, indigo, cyan, brown and mint) with the name's
initial, then the owner in `text.secondary`, `/`, the name in semibold, and the count circle on the
right, with a disclosure chevron before the square. Headers stay pinned at the top while their rows
scroll and are replaced by the next group's. Clicking a header folds its group: the chevron points
right and the rows, and the keyboard focus, skip it until it is opened again. Folds last for the life
of the process.

*Mine* as a **list** uses the same pinned headers, one per group, with a coloured dot: green Ready,
red Blocked, grey Draft. Every group folds from its chevron like a repository; Draft starts
collapsed. As a **board**, the three groups are columns side by side; each card shows the status
rail, the title on up to two lines, `owner/name #number` and the age, then the blocking reason
(`Conflict with the base branch`, `Checks failing`, `Changes requested by @carla`) or the status pill. A card's column follows from its
state; nothing is dragged.

When a section holds more than its search returned, its last line reads `+N not shown`
(`02-activity-detection.md` §2.1) in `text.tertiary`.

## 6. The row

### 6.1 Anatomy

A row is a 3 pt status rail, then two lines, 16 pt horizontal padding on both sides and 8 pt
vertical. The whole row is the click target (FR-42), and opening it marks it seen (FR-46).

```
┌─────────────────────────────────────────────────────────────┐
│ ┃ Fix login redirect loop after the SSO session expi…       │  title, one line
│ ┃ #482 (✕ Checks failing) @ana [urgent] [backend]  ● 4d     │  number · status · author · labels · age
└─────────────────────────────────────────────────────────────┘
```

| Element | Content | Style |
|---|---|---|
| Status rail | The status colour (§6.3) | 3 pt, full height; at 55% opacity on a seen row |
| Title | The pull request title, verbatim | `.body`, one line, truncated at the tail; the full title is the tooltip. **Unseen**: semibold in `text.primary`, and the row tinted with the accent at 10%. **Seen**: regular in `text.seen` (`labelColor` at 72%), no tint |
| Number | `#482` | `.subheadline`, monospaced digits, `text.secondary`. The repository is the group header |
| Status pill | §6.3 | `Ready to merge` shortens to `Ready` in *Review requested* |
| Draft modifier | `✎ Draft` (FR-31) | `status.neutral` |
| Author | `@carla`, except in *Mine* | `.subheadline`, `text.secondary` |
| Team | `via @acme/frontend` (FR-21) in *Review requested* | `.subheadline`, `text.secondary` |
| Reviewers | *Mine* only, order of `02` §3.3, with `circle.dashed`, `checkmark`, `arrow.uturn.backward` or `text.bubble`; after three, `+N` | `.subheadline`, `text.secondary` |
| Labels | GitHub labels, §6.4 | After the rest |
| Age | Waited time in *Review requested* (FR-33), age elsewhere (FR-32), §6.2 | Trailing, monospaced digits; `bell.slash` before it when muted |

The second line never wraps: reviewers collapse to `+N` first, then labels; the status pill is
never truncated.

### 6.2 Age styles

The thresholds are in `02-activity-detection.md` §3.4; here is the rendering.

| Style | Rendering | VoiceOver adds |
|---|---|---|
| Normal | `4h` | — |
| Ageing | 5 pt `circle.fill` in `status.attention`, then `4d` | `ageing` |
| Stale | The dot, then `9d` in `.semibold` | `stale` |

### 6.3 Status pills

One pill per row, for the status of `02-activity-detection.md` §3.2: a capsule filled with the colour
at 16%, the symbol and the word in the colour, `.subheadline` semibold.

| Status | SF Symbol | Text | Colour |
|---|---|---|---|
| `conflict` | `exclamationmark.triangle.fill` | `Conflict` | `status.blocking` |
| `checksFailing` | `xmark.circle.fill` | `Checks failing` | `status.blocking` |
| `changesRequested` | `arrow.uturn.backward.circle.fill` | `Changes requested` | `status.attention` |
| `checksRunning` | `circle.dotted`, rotating | `Checks running` | `status.running` symbol; the word in `text.primary`, since yellow text is unreadable on a light popover |
| `readyToMerge` | `checkmark.circle.fill` | `Ready to merge` | `status.ready` |
| `waitingForReview` | `eye` | `Waiting for review` | `status.waiting` |
| `noReviewers` | `person.crop.circle.badge.questionmark` | `No reviewers` | `status.neutral` |

A first version gave `checksRunning` and `waitingForReview` the same grey; with dozens of rows a
running check could not be told from a pull request waiting for review.

### 6.4 Labels

GitHub labels, read only. Each is a capsule outlined in the label's colour at 55%, filled with it at
14%, the name in the colour mixed 35% towards white in dark mode or black in light mode, so pale and
dark labels both read. Labels replaced local tags: they are what the team already uses, and they
need no editor.

### 6.5 Context menu

Right click on a row or a board card (FR-43):

| Item | Action |
|---|---|
| `Open in Browser` | The pull request's `url` (same as a click); marks it seen |
| `Copy URL` | The `url` |
| `Copy Reference` | `owner/name#number`, without the space, so it pastes as a GitHub reference |
| — | |
| `Open in Jira` | FR-86. The issue linked in the description, else a key in the title or branch on the site the other pull requests link to. Disabled when none is found |
| `Review with AI` | FR-87, D-28: the review command in the chosen terminal |
| `Summarize with AI` | FR-87, D-28: the summarize command in the chosen terminal |
| — | |
| `Filter to acme/api` | Adds the repository to the filter of §5.2 |
| `Mark as Seen` | Only on an unseen row |
| — | |
| `Mute Reminders` / `Unmute Reminders` | Scope `reminders` (FR-63, `02` §5.7). Shown only on a `reviewRequested` row, with a checkmark when set |
| `Mute Notifications` / `Unmute Notifications` | Scope `all`. With a checkmark when set; setting it replaces a `reminders` mute |
| `Ignore` / `Stop Ignoring` | FR-49, `02` §5.8. Hides both mute entries while ignored |

## 7. Account, error and empty screens

### 7.1 Full screens

When no poll can run, the section area is replaced by one centred screen: an SF Symbol at 28 pt in
`text.secondary`, a title in `.headline`, one or two sentences in `.body` `text.secondary`, the
fixing command in a monospaced, selectable box with a `Copy` button, and the actions. The header
stays, so refresh and settings remain.

| Condition (FR-12) | Symbol | Title | Body and command | Actions |
|---|---|---|---|---|
| `gh` not found | `terminal` | `GitHub CLI not found` | Docket reads your account through the GitHub CLI. Install it, then sign in. `brew install gh` | `Copy`, `Choose Location` (FR-11), `Try Again` |
| `gh` not signed in, or `401` after re-reading (FR-14) | `person.crop.circle.badge.xmark` | `Sign in to the GitHub CLI` | Run this in Terminal and follow the prompts. `gh auth login` | `Copy`, `Try Again` |
| Missing scopes | `key` | `The GitHub CLI token is missing read:org` | Lists every missing scope by name, then the command with exactly those scopes: `gh auth refresh -h github.com -s read:org` or `-s repo,read:org` | `Copy`, `Try Again` |
| First poll of a launch with no cache | `ProgressView`, small | `Loading pull requests…` | — | — |

`Try Again` re-runs the authentication steps of `03-architecture.md` §6 and polls. The setup itself
is in `09-provider-setup.md`.

### 7.2 Banners

Banners sit between the header and the sections, one line each, `.subheadline`, a symbol in its
token colour, an action button on the right. They stack in the order of the table.

| Condition | Symbol | Copy | Action |
|---|---|---|---|
| SAML required, one banner per organization (FR-13) | `lock.shield` in `status.attention` | `acme requires SAML authorization.` | `Authorize` — opens the URL GitHub returned |
| Rate-limited (`02` §6.3) | `clock` | `Paused by GitHub's rate limit until 14:30.` | — |
| Offline | `wifi.slash` | `Offline. Showing data from 14:03.` | — |
| Last poll failed | `exclamationmark.triangle` in `status.attention` | `Couldn't update. Showing data from 14:03.` | `Try Again` |
| First run, after the baseline (D-19) | `info.circle` | `Watching from now on. What was already waiting is listed but did not notify.` | `OK` — dismissed for good |
| First run, launch at login not decided (FR-90) | `power` | `Open Docket at login?` | `Turn On`, `Not Now` |
| Notification permission denied | `bell.slash` | `Notifications are off for Docket.` | `Open System Settings` |
| Focus hold on (`02` §7.5) | `moon` | `Holding 7 updates until your Focus ends.` | `Deliver Now` |

Times are local, `HH:mm` per the user's locale, with the date added when not today.

### 7.3 Empty states

One line in `text.secondary` under the section header, never an illustration.

| Section or condition | Copy |
|---|---|
| Review requested, empty | `No reviews waiting on you.` |
| Mine, empty | `No open pull requests of yours in the watched repositories.` |
| Involved, empty | `Nothing you commented on or reviewed in the last 30 days.` |
| Filters with no rows | `Nothing matches these filters.` with `Clear Filters` |
| Bots, empty | `No review requests from bots.` |
| Drafts, empty | `No drafts waiting on you.` |
| Stale, empty | `Nothing stale.` |
| Selection in `only` mode with nothing selected | `No repositories selected.` with `Choose Repositories` |

## 8. Notification composition

The strings are the English source values in `02-activity-detection.md` §7.1, coalescing and the
cap are §7.1 and §7.3, and click targets are §7.4. The composition rules on top of them:

| Rule | Value |
|---|---|
| Logins | Always prefixed `@`; a team is `@org/team` |
| Repository and number | `owner/name #number` in the subtitle; `#number` alone inside a body line, since the subtitle names the repository |
| Title length | Pull request titles truncated to 80 characters at a word boundary, with `…` |
| Body lines | At most 4; a group with more ends with `and N more` |
| Thread identifier | `repo:<owner/name>`, with the repository as summary argument (`02` §7.2) |
| Sound | `UNNotificationSound.default`; the user's per-app settings and Focus decide the rest |
| Interruption level | `.active` (D-22), reminders included. Never `.timeSensitive`: breaking through Focus would override the user's own schedule, and Docket's quiet hours cover only reminders (D-24) |
| Attachments | None, no avatars |

Categories, registered at launch:

| Category | Used by | Actions |
|---|---|---|
| `docket.single` | One event | `Open` (the URL of `02` §7.4), `Open Docket` |
| `docket.group` | A coalesced group, and the `N more updates` notification | `Open Docket` (the popover, filtered to the repository) |
| `docket.reminder` | One reminder | `Open`, `Mute Reminders` (writes scope `reminders` for that pull request, without opening anything) |
| `docket.digest` | The Focus digest of `02` §7.5, one per repository | `Open Docket` (the popover, filtered to the repository) |

A group of reminders uses `docket.group`: muting needs one pull request, and the popover is where
the group's rows are.

`Open Docket` is a foreground action that shows the popover; `Open` opens the browser without
bringing Docket forward.

## 9. Settings

A window with a native settings toolbar (`NSTabViewController`, `.toolbar` style), one SF Symbol per tab, each tab a hosted SwiftUI grouped `Form` 560 pt wide. *Notifications* and *AI* are 560 pt tall at most and scroll inside; the other tabs are as tall as their content. A SwiftUI `TabView` in a plain window was the first version; it drew its own segmented bar, crowded against the title bar once there were seven tabs. Every
control writes `config.json` on change (`04-data.md` §2.1); there is no Apply button.

| Tab | Symbol | Contents |
|---|---|---|
| **Account** | `person.crop.circle` | Signed-in login; `gh` path with `Choose Location` and `Use Default` (FR-11); scopes present, each with `checkmark` or `xmark` and the word; organizations needing SAML, each with `Authorize` |
| **Repositories** | `folder` | Mode as a radio group: `All repositories except these` / `Only these repositories` (`02` §2.3). Below, the list for the current mode — repositories and organizations, each row with its kind's symbol — with `+` and `−`. `+` opens the picker (FR-73): a search field over `knownRepositories` with the typed `owner/name` offered as the first row; a typed one shows `Checking…`, then is added or reads `Not found, or you don't have access` |
| **Notifications** | `bell` | Permission state: `Allowed`, `Not asked` with `Allow`, or `Off in System Settings` with `Open System Settings` (`02` §9). One toggle per kind (FR-60): `Review requested`, `Review on your pull request`, `Comment on your pull request`, `Reply to your comment`. Bot allowlist (D-16): a list of logins with `+` and `−`, captioned `Bots never notify unless they are listed here.` A **Reminders** group (FR-66, FR-67): `Remind me about pending reviews` (on); `Every` with a pop-up of `15 minutes`, `30 minutes`, `1 hour`, `2 hours`, `4 hours`, `8 hours`; `Quiet hours` toggle with `From` and `To` time pickers (hour and minute), captioned `Reminders pause in this window. Other notifications follow Focus.`; The interval and quiet-hours controls are disabled, not hidden, while reminders are off. A **Focus** group (FR-69): one line, `To hold notifications during a Focus, add Docket's filter to it.`, with `Open Focus Settings`, and the state `Holding since 14:00` or `Not holding`. A **Bots, drafts and stale pull requests** group (FR-37): `Stale after` with `3`, `5`, `7`, `14` or `30 days without human activity`; `Count bot pull requests` (on); `Notify about bot pull requests` (off); `Count and notify stale pull requests` (off); `Count and notify drafts` (off); `Also bots`, a comma-separated list of logins treated as bots |
| **General** | `gearshape` | Menu bar count: `Count review requests` and `Count your pull requests that need you`, captioned with the four statuses of `02` §4. Poll interval: a pop-up of `30 seconds`, `1 minute`, `2 minutes`, `5 minutes` (FR-92), captioned with the estimated hourly cost from `02` §6.2. **Mine**: `List` or `Board`. `Open at login` (FR-90) |
| **AI** | `sparkles` | **Terminal**: `Open in` with `Default for .command files` and each installed terminal Docket knows (Terminal, iTerm, Ghostty, Warp, WezTerm), plus `Choose Terminal`. **Review with AI** and **Summarize with AI**: a monospaced editor each, captioned with the placeholders, `Reset to Default` when changed, and a warning when a placeholder sits inside single quotes, where it does not expand. **Local clones**: `owner/name` and a folder |
| **Updates** | `arrow.down.circle` | As in Lookout: automatic checks, automatic install, `Check Now`, last checked |
| **About** | `info.circle` | Name, version and build; link to the repository; `Show Data Folder` (`~/Library/Application Support/Docket/`); `What's New` |

**Menu bar count and polling share the General tab** rather than taking one tab each as FR-91
lists them: each is one or two controls, and seven tabs for a settings window this small is the
dashboard instinct of §1 again.

## 10. Visual system

### 10.1 Typography

The system font only (SF Pro, through SwiftUI text styles), never a fixed family. Sizes are the
macOS defaults of each style.

| Style | Size | Used for |
|---|---|---|
| `.headline` | 13 pt semibold | Popover title, full-screen titles |
| `.body` | 13 pt | Row titles, full-screen body |
| `.subheadline` | 11 pt | Reference, age, chips, labels, reviewers, section and group headers, banners |
| `.caption` | 10 pt | Settings captions only |
| Monospaced | `.body.monospaced()` | Commands in full screens |

Every number that changes between polls — count, ages, waited times, section counts — uses
`.monospacedDigit()`, so a row does not reflow when `9d` becomes `10d`. Weights are regular and
semibold; nothing else.

### 10.2 Colour

Tokens map to `NSColor` system colours, so light, dark, Increase Contrast and the accent colour
setting are handled by macOS. No hex value appears in the code.

| Token | `NSColor` | Use |
|---|---|---|
| `text.primary` | `labelColor` | Titles, chip text |
| `text.secondary` | `secondaryLabelColor` | Reference, ages, headers, empty states |
| `text.tertiary` | `tertiaryLabelColor` | Counters, `+N not shown` |
| `accent` | `controlAccentColor` | Selected tab and sub-tab, unseen row tint, focus ring |
| `status.blocking` | `systemRed` | `conflict`, `checksFailing` |
| `status.attention` | `systemOrange` | `changesRequested`, ageing dot, warning banners |
| `status.ready` | `systemGreen` | `readyToMerge` |
| `status.running` | `systemYellow` | The `checksRunning` symbol only |
| `status.waiting` | `systemBlue` | `waitingForReview` |
| `status.neutral` | `secondaryLabelColor` | `noReviewers`, draft |
| `fill.tag` | `quaternarySystemFillColor` | Tab and sub-tab background, filter chips, board columns |
| `fill.badge` | `tertiaryLabelColor` at 60% | Count circles |
| `separator` | `separatorColor` | Between sections |

`systemYellow` colours only the `checksRunning` symbol: as text it is unreadable on the light popover material.

**Contrast, stated plainly.** Text is always `text.*` on the popover material, which meets 4.5:1.
The status colours do not all meet the 3:1 of WCAG 1.4.11 as graphics on a light background:
`systemRed` is about 3.5:1 on white, but `systemGreen` and `systemOrange` are about 2.2:1. This is
accepted only because colour is never the carrier — each chip's word is in `text.primary` and each
symbol has its own shape — and Increase Contrast swaps in macOS's darker variants. A chip that
relied on its colour would fail this section.

### 10.3 Space and shape

A 4 pt grid: `2, 4, 6, 8, 12, 16, 20`. Rows 12 × 6 pt padding; section headers 12 pt horizontal,
8 pt above; banners 12 × 8 pt; full screens 20 pt. Chips and labels are capsules. Row separators are
none — rows are separated by spacing and the hover highlight; sections by a `separator` line. Hover
and selection use the system's `.selection` background as a list row would.

### 10.4 Motion

Minimal. The popover's open and close are `NSPopover`'s. Section expand and collapse use the
default SwiftUI animation; rows inserted or removed by a poll appear without animation, because a
list that moves while it is being read loses the reader's place. The refresh symbol rotates with
`.symbolEffect(.rotate)` while a poll runs. With **Reduce Motion** on, the rotation becomes a static
symbol with `Updating…` in the header and the disclosure animation is removed. The count never
animates.

## 11. Accessibility

Each row is one VoiceOver element with the actions of its context menu as custom actions. Its label
is a template in `Localizable.xcstrings`, with clauses omitted when empty:

```
{status}{, draft}. {title}. {owner/name} number {number}.
{Waiting for review for {waited} | Open for {age}}{, ageing | , stale}.
{Requested from team {@org/team}.} {By {author}.}
{Reviewers: {login} approved, {login} requested changes, {login} pending.}
{Labels: {label}, {label}.} {Unseen.}
```

Example: `Conflict, draft. Fix login redirect loop. acme/api number 482. Open for 4 days, ageing.
Reviewers: ana pending, bruno approved. Tags: wip. New activity.` Durations are spoken in full
words (`4 days`, never `4d`), with `DateComponentsFormatter` in `.full` style; `@` is dropped from
spoken logins.

- Section and group headers are headers (`.isHeader`), with their count: `Review requested, 4`.
- Every symbol-only button has a label: `Refresh`, `Settings`, `Clear filter`.
- The status item's label is the tooltip of §4.

**Keyboard.** P0: `⌘R` refreshes, `⌘,` opens settings, `Escape` clears the filter then closes the
popover, `Tab` moves through controls. P1, FR-47: `↑` and `↓` move a focus ring through rows across
sections, `Return` opens the focused row and marks it seen, `←` and `→` move between tabs. FR-48 adds a global shortcut to open the popover.

## 12. Copy rules

- **English**, in `Localizable.xcstrings`, never inline (D-18). Every string has a comment saying
  where it appears.
- **Sentence case** for titles, labels, banners, empty states and notifications: `Review requested`,
  `Sign in to the GitHub CLI`. **Menu items and push buttons use title case** (D-21), as macOS does
  (`Mark All as Seen`, `Try Again`), because §2 makes "shipped with macOS" the test.
- **The vocabulary of `PROJECT.md` §7**: pull request (never "PR" in copy), repository, status,
  label (GitHub's), notification, "needs you".
- **No exclamation marks**, no "Oops", no "please", no "successfully".
- **No trailing `…` on buttons and menu items** (`Settings`, `Check for Updates`, `Choose Folder`), the maintainer's choice, although macOS uses it for an item that asks for more. Only progress text keeps it: `Checking…`, `Loading pull requests…`.
- **Numbers as digits**: `3 reviews requested`, `+2` labels. Ages use the forms of `02` §3.4 in the
  interface and full words for VoiceOver.
- **Logins with `@`**, teams as `@org/team`, references as `owner/name #number` on screen and
  `owner/name#number` when copied.
- **An error names the fix**: the command, the button, or the organization. "Something went wrong"
  is not a message.
- **`…`** (the single character) on a menu item or button that opens further UI, and on titles
  truncated by the app.
- Pull request titles, logins and repository names are quoted verbatim and never translated.

## 13. Review checklist

Run against a screen, or against the PNGs from `Docket --snapshot <directory>`
(`03-architecture.md` §8), which renders the popover, its error screens and the settings tabs in
light and dark appearance with synthetic data. Every item is a yes.

- [ ] It could pass for a first-party macOS panel: system material, system font, SF Symbols, no
      brand colour, no avatars.
- [ ] Light and dark both read correctly; nothing is hard-coded white or black.
- [ ] With Increase Contrast on, every chip and banner is still distinct.
- [ ] In greyscale, every status can be told apart by symbol and word.
- [ ] The count matches `02-activity-detection.md` §4 for the fixture, with no number at 0 and
      `99+` at 100.
- [ ] Section order and row order match §5.3 for the fixture.
- [ ] Every row shows reference, title, the right time (age or waited), status chip, and the draft
      modifier, team, reviewers and labels when they apply; unseen rows are tinted and bold.
- [ ] Ageing and stale ages are distinguishable without colour.
- [ ] Long titles truncate on one line; the second line never wraps and never truncates the status pill.
- [ ] Each account and error condition of §7.1 shows its exact command, and the command copies.
- [ ] Each banner of §7.2 names the organization, the time or the fix.
- [ ] Empty sections show one line, not a blank area.
- [ ] Copy follows §12: sentence case, title-case menu items and buttons, no exclamation marks,
      `PROJECT.md` §7 vocabulary, no "PR".
- [ ] Every string comes from `Localizable.xcstrings`.
- [ ] VoiceOver reads each row with the template of §11, and every icon button has a label.
- [ ] With Reduce Motion on, nothing rotates or slides.
- [ ] Numbers that change between polls use monospaced digits.
