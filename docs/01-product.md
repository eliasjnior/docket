# 01 — Product

Who Docket is for, what it must do, how well, and what it deliberately does not do. Every `FR-xx`
here is delivered by a milestone in [`07-roadmap.md`](07-roadmap.md) and proved by a test named in
the document that specifies it.

## 1. Personas

| Persona | Who they are | What they need | What they hate |
|---|---|---|---|
| **The author** | You, with three to eight pull requests open across a few repositories at any time | To know which of them is blocked on *you* — a conflict, a red check, a change request — without opening each one | Finding out at stand-up that a pull request has been approved since yesterday and is waiting only for a merge |
| **The reviewer** | You again, as a code owner or team member, receiving review requests directly and through teams | To see the queue in one place, oldest first, grouped by repository, and to hear about a new request within a minute | A review request buried between bot comments in the GitHub inbox, and the colleague asking "did you see my PR?" |
| **The participant** | You, having left a question on somebody else's pull request | To know when they answered *that* question | Notifications for every comment on a thread you once touched, so the answer is indistinguishable from noise |
| **The organization** | The GitHub organization whose repositories these are, with third-party application restrictions | Nothing new to approve, audit or revoke | A personal tool asking for organization-wide read access |

## 2. Jobs to be done

- When I sit down to work, I want to see which pull requests need me right now, so that I start
  with the one that unblocks somebody.
- When a colleague requests my review, I want to know within a minute, grouped with other requests
  in the same repository, so that I can batch reviews per codebase.
- When someone reviews my pull request, I want to know what they decided, so that I can address
  changes while the context is fresh.
- When someone answers a comment I left, I want to know that it was an answer to me, so that the
  conversation does not wait a day.
- When I look at a pull request in the list, I want to see how long it has been open and how long
  my review has been requested, so that I notice what is getting old.
- When a review request has sat for an hour and I have not opened it, I want to be reminded, but
  not at night and not about a pull request I have decided to ignore, so that a request made
  between meetings does not wait until the next day.
- When I am in a meeting under a Focus, I want Docket to keep what happened and tell me once when
  the Focus ends, so that I come back to a summary and not to a pile of banners.
- When a pull request lands in my review queue that is not mine to review, I want to ignore it, so
  that the count means what needs me.
- When I am in the middle of a pull request, I want to tag it `wip` without telling anyone, so that
  the list reflects what I am doing.
- When I join a repository or leave a project, I want to choose which repositories Docket watches,
  so that the list contains only what I care about.

## 3. Functional requirements

`P0` ships in v1.0, `P1` in v1.x, `P2` later. Numbered in tens per group so rows can be inserted.

### 3.1 Authentication

| ID | Requirement | Priority |
|---|---|---|
| **FR-10** | Docket obtains its token by running `gh auth token --hostname github.com` and holds it only in memory (D-02) | P0 |
| **FR-11** | Docket locates `gh` at `/opt/homebrew/bin/gh`, `/usr/local/bin/gh`, then the user's login-shell `PATH`, and accepts an explicit path in settings | P0 |
| **FR-12** | When `gh` is missing, not signed in, or its token lacks `repo` or `read:org`, the popover shows a screen naming the exact command that fixes it | P0 |
| **FR-13** | When an organization requires SAML authorization of the token, Docket names the organization and opens the authorization URL GitHub returned; the other organizations keep working | P0 |
| **FR-14** | On a `401`, Docket re-reads the token once before reporting the account as signed out | P0 |

### 3.2 Which pull requests are watched

| ID | Requirement | Priority |
|---|---|---|
| **FR-20** | Open pull requests authored by you are watched with role `authored` | P0 |
| **FR-21** | Open pull requests with a pending review request to you, directly or through a team you belong to, are watched with role `reviewRequested`, and the row says which team | P0 |
| **FR-22** | Open pull requests you have commented on or reviewed, updated in the last 30 days, are watched with role `involved` | P0 |
| **FR-23** | Each pull request has exactly one role, by precedence `authored` > `reviewRequested` > `involved` | P0 |
| **FR-24** | Archived repositories are never watched | P0 |

The rules are in [`02-activity-detection.md`](02-activity-detection.md) §2.

### 3.3 Status and age

| ID | Requirement | Priority |
|---|---|---|
| **FR-30** | Each pull request shows exactly one status, chosen by the precedence in `02-activity-detection.md` §3 | P0 |
| **FR-31** | Draft is shown as a modifier beside the status, not as a status | P0 |
| **FR-32** | Each pull request shows its age since creation, formatted per `02-activity-detection.md` §3.4 | P0 |
| **FR-33** | Each review request shows how long the request has waited, measured from the latest request to you | P0 |
| **FR-34** | Ages past 3 days are marked as ageing and past 7 days as stale, by a style that does not rely on colour alone | P0 |
| **FR-35** | Authored pull requests show the requested reviewers and the latest decision of each reviewer | P0 |
| **FR-36** | *Review requested* splits into **Humans**, **Bots** and **Stale** (`02-activity-detection.md` §3.6); every request is in exactly one | P0 |
| **FR-37** | Whether Bots and Stale count in the menu bar and notify is a setting each; by default bots count and stale pull requests do not | P0 |

### 3.4 Menu bar and popover

| ID | Requirement | Priority |
|---|---|---|
| **FR-40** | One status item shows the "needs you" count (`02-activity-detection.md` §4), and no number when it is zero | P0 |
| **FR-41** | The popover has three sections — *Review requested* grouped by repository, *Mine*, *Involved* collapsed by default — each sorted as in `05-design.md` | P0 |
| **FR-42** | Clicking a row opens the pull request in the default browser | P0 |
| **FR-43** | A row's context menu copies the URL and `owner/name#number`, filters to the row's repository, and edits tags | P0 |
| **FR-44** | The popover shows the last cached snapshot immediately, with "updated N min ago" when it is older than two poll intervals | P0 |
| **FR-45** | A refresh button and `⌘R` run a poll immediately | P0 |
| **FR-46** | Each row is **seen** or **unseen**: unseen until you open it from Docket, and unseen again after a human other than you comments, reviews, requests or pushes. Bot activity never makes a row unseen. *Mark All as Seen* clears the visible list | P0 |
| **FR-47** | Keyboard navigation of the popover: arrows move, `Return` opens, `T` edits tags | P1 |
| **FR-48** | A global shortcut opens the popover | P1 |
| **FR-49** | A pull request can be ignored: it leaves the count, moves to a collapsed **Ignored** section at the end of the popover, and never notifies or reminds, until `Stop Ignoring` (D-27, `02-activity-detection.md` §5.8) | P0 |

### 3.5 Notifications

| ID | Requirement | Priority |
|---|---|---|
| **FR-50** | A new review request to you notifies, one notification per request, including a re-request after you reviewed | P0 |
| **FR-51** | A review submitted on your pull request notifies with its decision: approved, changes requested, commented | P0 |
| **FR-52** | A new comment on your pull request, outside a review already notified, notifies | P0 |
| **FR-53** | A reply in a review thread where you have a comment notifies, on any watched pull request | P0 |
| **FR-54** | Notifications of one repository share a macOS thread, so Notification Center stacks them per repository | P0 |
| **FR-55** | Events of the same kind in the same repository in the same poll become one notification, and one poll delivers at most five notifications | P0 |
| **FR-56** | Your own actions never notify | P0 |
| **FR-57** | Bot authors never notify, unless their login is in the bot allowlist (D-16) | P0 |
| **FR-58** | No event notifies twice, across polls, restarts, sleep and reinstalls that keep `state.json` | P0 |
| **FR-59** | Clicking a notification opens the pull request; clicking a grouped one opens the popover filtered to that repository | P0 |
| **FR-60** | Each event kind can be turned off in settings | P0 |
| **FR-61** | Checks failing on your pull request notify, once per head commit | P1 |
| **FR-62** | Your pull request merged or closed by somebody else notifies | P1 |
| **FR-63** | A single pull request can be muted, from its context menu or from a reminder, in one of two scopes: **reminders only**, or **all notifications**. It stays in the list and in the count, and the mute holds until it is undone (`02-activity-detection.md` §5.7) | P0 |
| **FR-64** | A mention of you in a comment is its own event kind | P1 |
| **FR-65** | A review request still pending one reminder interval after it was made sends a reminder, and so does every further interval while it stays pending (D-23, `02` §5.7) | P0 |
| **FR-66** | Reminders have a global switch and a configurable interval — `15 minutes` to `8 hours` — on by default at `1 hour` | P0 |
| **FR-67** | Reminder quiet hours: a daily window in local time, which may cross midnight, during which no reminder is sent; a reminder due inside it is sent at the first poll after it ends. Off by default, `22:00`–`08:00` when first turned on (D-24) | P0 |
| **FR-69** | A Docket Focus filter, added by the user to any Focus in System Settings, holds notifications while that Focus is on and delivers them when it ends as one digest per repository; reminders are not sent while holding (D-25, `02` §7.5) | P1 |

The rules are in [`02-activity-detection.md`](02-activity-detection.md) §5 and §7.

### 3.6 Selection

| ID | Requirement | Priority |
|---|---|---|
| **FR-70** | By default every repository is watched | P0 |
| **FR-71** | In *all* mode, repositories and organizations can be excluded | P0 |
| **FR-72** | In *only* mode, only the listed repositories and organizations are watched | P0 |
| **FR-73** | The picker lists the repositories seen in the last 90 days of your pull request activity and accepts a typed `owner/name`, which is checked against the API | P0 |
| **FR-74** | Selection applies to the list, the count and notifications alike | P0 |

### 3.7 Tags

| ID | Requirement | Priority |
|---|---|---|
| **FR-80** | Any watched pull request can carry up to five tags, added and removed from the row | P0 |
| **FR-81** | Tags are normalized: lower case, `[a-z0-9-]`, 1–24 characters; anything else is rejected with the reason | P0 |
| **FR-82** | The popover filters by one tag and by one repository, separately or together | P0 |
| **FR-83** | The tag editor suggests tags already in use, most used first, and `wip` when none are | P0 |
| **FR-84** | A tag survives its pull request closing for 30 days, so a reopened pull request keeps it | P0 |
| **FR-85** | Tags never leave the Mac and are never written to GitHub | P0 |

### 3.8 The app

| ID | Requirement | Priority |
|---|---|---|
| **FR-90** | Launch at login, offered on first run and on by default once accepted | P0 |
| **FR-91** | Settings in six sections: General (menu bar count, poll interval, launch at login), Account, Repositories, Notifications (kinds, bot allowlist, permission), Updates, About | P0 |
| **FR-92** | Poll interval of 30 s, 60 s (default), 2 min or 5 min | P0 |
| **FR-93** | Self-update from GitHub Releases, as in Lookout (D-14) | P0 |
| **FR-94** | What's New after an update, from the bundled changelog | P0 |
| **FR-95** | Polling pauses while the Mac sleeps or is offline and runs once on wake or reconnect | P0 |
| **FR-96** | `config.json` can be exported to and imported from a file | P1 |

## 4. Non-functional requirements

| ID | Requirement | Target |
|---|---|---|
| **NFR-01** | Poll cost when nothing changed | ≤ 4 GraphQL points per poll with ≤ 100 watched pull requests, read from `rateLimit { cost }` |
| **NFR-02** | Poll cost when pull requests changed | ≤ 4 + ⌈changed ÷ 10⌉ × 4 points |
| **NFR-03** | Rate-limit headroom | Docket never polls while `remaining` < 20% of `limit`, and stretches the interval below 30% (`02-activity-detection.md` §6) |
| **NFR-04** | Detection latency | p95 ≤ poll interval + 15 s from the event on GitHub to the notification |
| **NFR-05** | Duplicate notifications | 0, asserted by the restart and sleep cases in `02-activity-detection.md` §8 |
| **NFR-06** | Popover open | p95 ≤ 100 ms from click to rendered rows from cache, measured in a Debug build with 100 pull requests |
| **NFR-07** | Idle cost | ≤ 0.5% CPU averaged over 10 minutes; ≤ 80 MB resident memory with 100 pull requests |
| **NFR-08** | First data after launch | ≤ 3 s with the network up and `gh` signed in |
| **NFR-09** | Test coverage | `DocketActivity` ≥ 90% lines and `DocketKit` overall ≥ 75%, enforced by `scripts/ci.sh` |
| **NFR-10** | Network surface | Only GitHub hosts: `api.github.com` for every query and release lookup, and the asset host `api.github.com` redirects a release download to (`release-assets.githubusercontent.com` or `objects.githubusercontent.com`); `github.com` only opens in the browser |
| **NFR-11** | Accessibility | Every row and chip has a VoiceOver label; no status is conveyed by colour alone |

## 5. Success metrics

Docket has one user and no telemetry (PROJECT.md principle 4), so metrics are measured from GitHub
after the fact by `docket-cli stats`, which reads your own review history and stores nothing.

| Metric | Baseline | Target |
|---|---|---|
| Median time from a review request to your first review | Measured by `docket-cli stats` over the 30 days before first install | Half the baseline after 30 days of use |
| Review requests older than 2 working days, at any moment | Measured the same way | 0 on most days |
| Your pull requests approved and green but not merged for more than 4 hours | Measured the same way | Half the baseline |

**Anti-metrics** — signs that Docket made things worse:

- You turn Docket's notifications off in System Settings. That is principle 1 failing, and the fix
  is in the rules of `02-activity-detection.md` §5, not in a setting.
- You open GitHub's inbox to check whether Docket missed something. One confirmed miss is a bug,
  and it becomes a test case in `02-activity-detection.md` §8.
- A notification arrives for something you did yourself.

## 6. Explicit non-goals

- **Acting on GitHub.** No approve, merge, comment or re-request (PROJECT.md principle 3).
- **Replacing the GitHub inbox.** Issues, discussions, releases and Actions failures on branches
  that are not your pull requests stay where they are.
- **Team dashboards.** Docket shows what needs *you*. It never lists a colleague's queue.
- **Reading the diff.** No file lists, no code, no line counts beyond what the row needs — the
  browser is where review happens.
- **Shared tags.** Tags are private by design (D-17); a team that wants shared markers has labels.
