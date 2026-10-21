# 05 — Design

How Docket looks and reads: the status item, the popover and its rows, the status chips, the tag
editor, every account and error screen, notification composition, settings, and the checklist a
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
| Lists, chips, banners, tag editor | SwiftUI | Declarative state from `WatchStore` (`03-architecture.md` §4) |
| Settings | SwiftUI `Settings` scene with a toolbar-style `TabView` and grouped `Form`s | The System Settings look with no custom layout |
| Icons | SF Symbols only | Matches the menu bar's own glyphs at every weight and scale |
| Notifications | `UNUserNotificationCenter` through `DocketNotify` | `03-architecture.md` §3 |

**`NSMenu` with custom item views was the alternative** for the list, and many menu bar apps use
it. It lost on the tag editor: a menu cannot host a text field that keeps focus, a context menu
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
`Refresh` (`⌘R`), `Settings…` (`⌘,`) and `Quit Docket` (`⌘Q`), so the app can be quit without
opening the popover.

## 5. The popover

### 5.1 Frame

| Property | Value | Why |
|---|---|---|
| Width | 380 pt, fixed | Fits `owner/name #number`, a status chip and an age on one line with a 40-character repository name; Lookout's popovers are 340 and 400 pt |
| Height | Content height, at most 600 pt or the screen's visible height minus 40 pt, whichever is smaller | A short list does not leave an empty panel; a long one never runs off a 13-inch screen |
| Scrolling | The section area scrolls; the header and banners stay fixed | Refresh and the filter are always reachable |
| Background | The popover's own material; no fill of ours | §2 |

### 5.2 Layout

```
┌──────────────────────────────────────────────────── 380 pt ┐
│  Docket                                         ⟳     ⚙    │  header
│  [ All repositories ⌄ ]  [ All tags ⌄ ]                     │  filters
│  Updated 12 min ago                                         │  only when stale (FR-44)
│  [ acme/api  ✕ ]                                            │  only when filtered (FR-59)
├─────────────────────────────────────────────────────────────┤
│  ⚠  acme requires SAML authorization.        [Authorize]   │  banners, §7.2
├─────────────────────────────────────────────────────────────┤
│  (Review requested 4 ●)  Mine 5   Involved 8 ●   Ignored 1  │  tabs; ● = marked rows inside
├─────────────────────────────────────────────────────────────┤
│     acme/api                                           3    │  repository group header
│     ● row                                                   │
│     ─────────────────────────────────────────────           │  separator between rows
│     row                                                     │
│     acme/web                                           1    │
│     row                                                     │
└─────────────────────────────────────────────────────────────┘
```

**Header.** The word `Docket` in `.headline`; a tag filter as a borderless pop-up button reading
`All tags` or the selected tag, listing tags in use most used first (FR-82, one tag at a time); a
refresh button with `arrow.clockwise` (FR-45, `⌘R`); a settings button with `gearshape` that opens a
menu of `Settings…`, `Check for Updates…` and `Quit Docket`. The line `Updated N min ago` appears
only when the snapshot is older than two poll intervals (FR-44), in `.subheadline` and
`text.secondary`; while a poll runs it reads `Updating…` instead.

**Filters.** A second header line holds two borderless pop-ups: the repository, listing the
repositories in the list with their row counts, most rows first, and the tag. A click on a grouped
notification opens the popover with the repository filter set (FR-59); `Escape` clears the
repository filter, then the tag filter. The two combine (FR-82).

### 5.3 Sections and order

The sections are **tabs** under the filters, so a long list of one role never pushes the others off
screen: *Review requested*, *Mine* and *Involved* always, and **Ignored** only while something is
ignored. Each tab shows its row count and the marked dot when a row inside is marked, so a reply in
another tab is not missed. The selected tab is kept for the life of the process, not stored, and
opens on *Review requested*. Rows are separated by a hairline inset to the text. The user chose
tabs over collapsible sections and newest-first over oldest-first after using 0.2.0.

| Section | Contains (role, `02` §2.2) | Default | Order |
|---|---|---|---|
| **Review requested** | `reviewRequested` | The default tab | Grouped by repository. Groups ordered by their newest request, newest first; rows inside a group by request time, newest first. Ties by `owner/name`, then `#number` |
| **Mine** | `authored` | Tab | By status in the precedence order of `02-activity-detection.md` §3.2 — `conflict` first, `noReviewers` last — then newest first. A draft sorts with its status (FR-31) |
| **Involved** | `involved` | Tab (FR-41) | By `updatedAt`, most recent first |
| **Ignored** | Any role, ignored (FR-49) | Tab, only while something is ignored | By `ignoredAt`, most recent first. Rows in `text.secondary`, no marked dot, no status colour: nothing here asks for attention |

A repository group header reads `acme/api` in `.subheadline` with its row count on the right. Only
*Review requested* is grouped: it is the section the reviewer batches per codebase (`01-product.md`
§2); *Mine* is short enough that grouping would add a header per row.

When a section holds more than its search returned, its last line reads `+N not shown`
(`02-activity-detection.md` §2.1) in `text.tertiary`.

A tab whose rows include a marked one (FR-46) shows the marked dot after its count, so a reply in
*Involved* is visible from *Review requested*.

## 6. The row

### 6.1 Anatomy

A row is three lines, 12 pt horizontal padding, 6 pt vertical, with the marked dot in a 12 pt
leading gutter. The whole row is the click target (FR-42).

*Mine* and *Involved* — status first (`02` §3.2):

```
┌─────────────────────────────────────────────────────────────┐
│ ● acme/api #482                                     ● 4d    │  ref · age
│   Fix login redirect loop after the SSO session expi…       │  title, one line
│   ⚠ Conflict  ✎ Draft   ○ @ana  ✓ @bruno   [wip] [infra]    │  chips · reviewers · tags
└─────────────────────────────────────────────────────────────┘
  │                                                  │
  marked (FR-46)                         ageing dot (02 §3.4)
```

*Review requested* — waited time first, status secondary:

```
┌─────────────────────────────────────────────────────────────┐
│   acme/web #88                            waited ● 9d       │  ref · waited time, stale
│   Move checkout to the new payments client                  │
│   by @carla · via @acme/frontend   ✓ Ready · 12d   [after]  │  author · team · status · age · tags
└─────────────────────────────────────────────────────────────┘
```

| Element | Content | Style |
|---|---|---|
| Marked dot | Present when the pull request has an event since the popover was last opened (FR-46) | 8 pt `circle.fill` in `accent.marked`, in the leading gutter |
| Reference | `owner/name #number` | `.subheadline`, `text.secondary`, monospaced digits |
| Title | The pull request title, verbatim | `.body`, `text.primary`, one line, truncated at the tail with `…`; the full title is the tooltip |
| Age | `createdAt` age, formatted by `02` §3.4 | `.subheadline`, monospaced digits, `text.secondary`; ageing and stale per §6.2 |
| Waited time | Review requested only: `waited 4d` (FR-33) | Same as age; replaces the age on line 1, and the age moves to line 3 as `· 12d` |
| Status chip | §6.3 | Line 3, first; secondary style in *Review requested* |
| Draft modifier | `✎ Draft` with `pencil`, after the status chip (FR-31) | `status.neutral` |
| Author | Review requested and involved only: `by @carla` | `.subheadline`, `text.secondary` |
| Team | `via @acme/frontend` when the request reached you through a team (FR-21); `via a team` without `read:org` (`02` §2.2) | `.subheadline`, `text.secondary` |
| Reviewers | Authored only, order of `02` §3.3: `○ @ana` pending (`circle.dashed`), `✓ @bruno` approved (`checkmark`), `↺ @carla` changes requested (`arrow.uturn.backward`), `@dave` commented with `text.bubble`, `@dave re-requested` when both | `.subheadline`; logins as text, no avatars (`04-data.md` §5); after three reviewers, `+N` |
| Tags | Up to five chips, insertion order (FR-80) | §6.4 |

Line 3 never wraps. When it overflows, reviewers collapse to `+N` first, then tags to `+N`; the
status chip and draft modifier are never truncated.

**Two dots, honestly.** The marked dot and the ageing dot are both dots. They differ by position
(leading gutter versus beside the age), size (8 pt versus 5 pt) and colour (`accent.marked` versus
`status.attention`), and by VoiceOver wording (§11). If testing shows people confuse them, the
ageing marker is the one to change, because `02` §3.4 only needs it not to rely on colour.

### 6.2 Age styles

The thresholds are in `02-activity-detection.md` §3.4; here is the rendering.

| Style | Rendering | VoiceOver adds |
|---|---|---|
| Normal | `4h` | — |
| Ageing | 5 pt `circle.fill` in `status.attention`, then `4d` | `ageing` |
| Stale | The dot, then `9d` in `.semibold` | `stale` |

The same styles apply to the waited time of a review request.

### 6.3 Status chips

One chip per row, for the status of `02-activity-detection.md` §3.2. A chip is the symbol in its
colour token followed by the short text in `text.primary`, on a capsule filled with the token at
12% opacity, `.subheadline` medium, 4 pt × 2 pt padding.

| Status | SF Symbol | Text | Colour token |
|---|---|---|---|
| `conflict` | `exclamationmark.triangle.fill` | `Conflict` | `status.blocking` |
| `checksFailing` | `xmark.circle.fill` | `Checks failing` | `status.blocking` |
| `changesRequested` | `arrow.uturn.backward.circle.fill` | `Changes requested` | `status.attention` |
| `checksRunning` | `hourglass` | `Checks running` | `status.neutral` |
| `readyToMerge` | `checkmark.circle.fill` | `Ready to merge` | `status.ready` |
| `waitingForReview` | `eye` | `Waiting for review` | `status.neutral` |
| `noReviewers` | `person.crop.circle.badge.questionmark` | `No reviewers` | `status.neutral` |
| Draft modifier | `pencil` | `Draft` | `status.neutral` |

In *Review requested* the chip is secondary: no fill, `text.secondary` text, the symbol still in its
colour, and `Ready to merge` shortens to `Ready`. The two red statuses differ in symbol and word,
because they need different actions.

### 6.4 Tag chips

`wip` in `.subheadline` medium, in the tag's colour, on a capsule of the same colour at 18% opacity,
6 pt × 2 pt padding. The colour comes from the tag's name (an FNV-1a hash into blue, purple, pink,
teal, indigo, cyan, brown and mint), so a tag keeps its colour across launches and pull requests;
red, orange and green are left to status. A first version had no colour per tag, and tags were hard
to spot among many pull requests. A tag chip is clickable and sets the popover's tag filter to it.

### 6.5 Context menu

Right click on a row (FR-43):

| Item | Action |
|---|---|
| `Open in Browser` | The pull request's `url` (same as a click) |
| `Copy URL` | The `url` |
| `Copy Reference` | `owner/name#number`, without the space the row shows, so it pastes as a GitHub reference |
| — | |
| `Edit Tags…` | The tag editor, §6.6 (`T` with FR-47) |
| `Filter to acme/api` | The repository filter of §5.2 |
| — | |
| `Mute Reminders` / `Unmute Reminders` | Scope `reminders` (FR-63, `02` §5.7). Shown only on a `reviewRequested` row, with a checkmark when set |
| `Mute Notifications` / `Unmute Notifications` | Scope `all`. With a checkmark when set; setting it replaces a `reminders` mute |
| `Ignore` / `Stop Ignoring` | FR-49, `02` §5.8. Hides both mute entries while ignored |

A row muted with scope `all` shows `bell.slash` in the secondary colour after the age, labelled
`Muted` for VoiceOver. A `reminders` mute has no marker on the row: it changes nothing you would
act on in the list, and the context menu's checkmark shows it.

### 6.6 The tag editor

`Edit Tags…` opens a SwiftUI `.popover` anchored to the row, 260 pt wide, over the main popover.

```
┌──────────────────────────────── 260 pt ┐
│  [wip ✕] [infra ✕]  after Release│       │  token field
│  Saved as after-release                 │  normalization feedback
│  ───────────────────────────────────    │
│  Suggestions                            │
│  blocked   after-release   wip          │  in use, most used first (FR-83)
│                               2 of 5    │
└─────────────────────────────────────────┘
```

- `Return` or `,` adds the typed tag; `Backspace` in an empty field removes the last; `Escape`
  closes. Every change is saved immediately; there is no Save button.
- Below the field, live feedback on the normalization of `04-data.md` §2.1. When the input changes
  under normalization: `Saved as after-release`. When it is still invalid, the reason, in
  `text.secondary` with `exclamationmark.circle`:

  | Reason | Message |
  |---|---|
  | Characters outside `[a-z0-9-]` after normalization | `Tags use letters, digits and hyphens` |
  | Longer than 24 characters | `Tags are up to 24 characters` |
  | Already on this pull request | `Already added` |
  | Five tags already | `Up to 5 tags per pull request` |

- Suggestions are the tags in use, most used first, filtered by prefix as the user types, at most
  six; `wip` when no tag is in use (FR-83). A click adds one.
- The counter `2 of 5` sits bottom right in `text.tertiary`.

## 7. Account, error and empty screens

### 7.1 Full screens

When no poll can run, the section area is replaced by one centred screen: an SF Symbol at 28 pt in
`text.secondary`, a title in `.headline`, one or two sentences in `.body` `text.secondary`, the
fixing command in a monospaced, selectable box with a `Copy` button, and the actions. The header
stays, so refresh and settings remain.

| Condition (FR-12) | Symbol | Title | Body and command | Actions |
|---|---|---|---|---|
| `gh` not found | `terminal` | `GitHub CLI not found` | Docket reads your account through the GitHub CLI. Install it, then sign in. `brew install gh` | `Copy`, `Choose Location…` (FR-11), `Try Again` |
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
| A tag filter with no rows | `No pull requests tagged wip.` with `Clear Filter` |
| Selection in `only` mode with nothing selected | `No repositories selected.` with `Choose Repositories…` |

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

A `Settings` scene, 520 pt wide, toolbar tabs with SF Symbols, each tab a grouped `Form`. Every
control writes `config.json` on change (`04-data.md` §2.1); there is no Apply button.

| Tab | Symbol | Contents |
|---|---|---|
| **Account** | `person.crop.circle` | Signed-in login; `gh` path with `Choose Location…` and `Use Default` (FR-11); scopes present, each with `checkmark` or `xmark` and the word; organizations needing SAML, each with `Authorize` |
| **Repositories** | `folder` | Mode as a radio group: `All repositories, except…` / `Only these repositories` (`02` §2.3). Below, the list for the current mode — repositories and organizations, each row with its kind's symbol — with `+` and `−`. `+` opens the picker (FR-73): a search field over `knownRepositories` with the typed `owner/name` offered as the first row; a typed one shows `Checking…`, then is added or reads `Not found, or you don't have access` |
| **Notifications** | `bell` | Permission state: `Allowed`, `Not asked` with `Allow…`, or `Off in System Settings` with `Open System Settings` (`02` §9). One toggle per kind (FR-60): `Review requested`, `Review on your pull request`, `Comment on your pull request`, `Reply to your comment`. Bot allowlist (D-16): a list of logins with `+` and `−`, captioned `Bots never notify unless they are listed here.` A **Reminders** group (FR-66, FR-67): `Remind me about pending reviews` (on); `Every` with a pop-up of `15 minutes`, `30 minutes`, `1 hour`, `2 hours`, `4 hours`, `8 hours`; `Quiet hours` toggle with `From` and `To` time pickers (hour and minute), captioned `Reminders pause in this window. Other notifications follow Focus.`; The interval and quiet-hours controls are disabled, not hidden, while reminders are off. A **Focus** group (FR-69): one line, `To hold notifications during a Focus, add Docket's filter to it.`, with `Open Focus Settings`, and the state `Holding since 14:00` or `Not holding` |
| **General** | `gearshape` | Menu bar count: `Count review requests` and `Count your pull requests that need you`, captioned with the four statuses of `02` §4. Poll interval: a pop-up of `30 seconds`, `1 minute`, `2 minutes`, `5 minutes` (FR-92), captioned with the estimated hourly cost from `02` §6.2. `Open at login` (FR-90) |
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
| `.subheadline` | 11 pt | Reference, age, chips, tags, reviewers, section and group headers, banners |
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
| `accent.marked` | `controlAccentColor` | Marked dot |
| `status.blocking` | `systemRed` | `conflict`, `checksFailing` |
| `status.attention` | `systemOrange` | `changesRequested`, ageing dot, warning banners |
| `status.ready` | `systemGreen` | `readyToMerge` |
| `status.neutral` | `secondaryLabelColor` | `checksRunning`, `waitingForReview`, `noReviewers`, draft |
| `fill.tag` | `quaternarySystemFillColor` | Tag chips |
| `separator` | `separatorColor` | Between sections |

`systemYellow` is not used: it is unreadable on the light popover material.

**Contrast, stated plainly.** Text is always `text.*` on the popover material, which meets 4.5:1.
The status colours do not all meet the 3:1 of WCAG 1.4.11 as graphics on a light background:
`systemRed` is about 3.5:1 on white, but `systemGreen` and `systemOrange` are about 2.2:1. This is
accepted only because colour is never the carrier — each chip's word is in `text.primary` and each
symbol has its own shape — and Increase Contrast swaps in macOS's darker variants. A chip that
relied on its colour would fail this section.

### 10.3 Space and shape

A 4 pt grid: `2, 4, 6, 8, 12, 16, 20`. Rows 12 × 6 pt padding; section headers 12 pt horizontal,
8 pt above; banners 12 × 8 pt; full screens 20 pt. Chips and tags are capsules. Row separators are
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
{Tags: {tag}, {tag}.} {New activity.}
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
sections, `Return` opens the focused row, `T` opens its tag editor, `←` and `→` move between tabs. FR-48 adds a global shortcut to open the popover.

## 12. Copy rules

- **English**, in `Localizable.xcstrings`, never inline (D-18). Every string has a comment saying
  where it appears.
- **Sentence case** for titles, labels, banners, empty states and notifications: `Review requested`,
  `Sign in to the GitHub CLI`. **Menu items and push buttons use title case** (D-21), as macOS does
  (`Edit Tags…`, `Try Again`), because §2 makes "shipped with macOS" the test.
- **The vocabulary of `PROJECT.md` §7**: pull request (never "PR" in copy), repository, status,
  tag, notification, "needs you". A GitHub label is never called a tag, and a tag never a label.
- **No exclamation marks**, no "Oops", no "please", no "successfully".
- **Numbers as digits**: `3 reviews requested`, `5 tags`. Ages use the forms of `02` §3.4 in the
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
      modifier, team, reviewers and tags when they apply.
- [ ] Ageing and stale ages are distinguishable without colour.
- [ ] Long titles truncate on one line; line 3 never wraps and never truncates the status chip.
- [ ] Each account and error condition of §7.1 shows its exact command, and the command copies.
- [ ] Each banner of §7.2 names the organization, the time or the fix.
- [ ] Empty sections show one line, not a blank area.
- [ ] Copy follows §12: sentence case, title-case menu items and buttons, no exclamation marks,
      `PROJECT.md` §7 vocabulary, no "PR".
- [ ] Every string comes from `Localizable.xcstrings`.
- [ ] VoiceOver reads each row with the template of §11, and every icon button has a label.
- [ ] With Reduce Motion on, nothing rotates or slides.
- [ ] Numbers that change between polls use monospaced digits.
