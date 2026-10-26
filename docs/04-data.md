# 04 — Data

Every file Docket writes, its schema, what keeps it correct, when it is deleted, what is
deliberately never stored, and how the token is held. There is no database (D-10): three locations
under `~/Library/Application Support/Docket/`, written only by `DocketPersistence`. The fourth thing
there, `bin/gh`, is the GitHub CLI the setup window installs (FR-15), written only by
`DocketUpdate.GhInstaller` after its checksum and signature checks; deleting it only brings the setup
window back.

## 1. Conventions

| Rule | Why |
|---|---|
| JSON, UTF-8, pretty-printed with sorted keys | A file a person can read and diff when something looks wrong |
| Top-level `version` integer in every file | Decoding switches on it; a file with a higher `version` than the app knows is left untouched and the app runs read-only for it |
| Keys `camelCase`, matching the Swift property names | One name per field from decoder to view; no mapping layer |
| Timestamps ISO 8601 in UTC with `Z` (`2026-10-21T14:03:00Z`) | Server timestamps arrive in UTC; local time exists only in the view |
| Pull requests keyed by GraphQL node ID; `owner/name#number` stored beside it as `ref` | D-09: the ID survives a rename, the ref is for people |
| Repositories as `owner/name`, compared case-insensitively | D-05 |
| Writes are atomic: a temporary file in the same directory, then `rename(2)` (`Data.write(options: .atomic)`) | A crash mid-write leaves the previous file, never half of one |
| Directory mode `0700`, files `0600` | Titles and logins from private repositories are readable by this user only |
| Unknown keys are ignored on read and dropped on the next write | A downgrade does not crash; it loses only fields it does not know |

## 2. Files

### 2.1 `config.json` — what you decided

Written when you change a setting or a tag, and by retention when it deletes a tag (§4). Never
written by a poll.

| Field | Type | Default | Meaning |
|---|---|---|---|
| `version` | integer | `1` | §1 |
| `selection.mode` | `"all"` \| `"only"` | `"all"` | `02-activity-detection.md` §2.3 |
| `selection.includedRepositories` | `[String]` | `[]` | `owner/name`, used in `only` mode |
| `selection.includedOwners` | `[String]` | `[]` | Organization or user logins, used in `only` mode |
| `selection.excludedRepositories` | `[String]` | `[]` | Used in `all` mode |
| `selection.excludedOwners` | `[String]` | `[]` | Used in `all` mode |
| `polling.intervalSeconds` | `30` \| `60` \| `120` \| `300` | `60` | FR-92 |
| `count.includeReviewRequests` | Bool | `true` | `02` §4 |
| `count.includeBlockedAuthored` | Bool | `true` | `02` §4 |
| `triage.staleAfterDays` | `3` \| `5` \| `7` \| `14` \| `30` | `7` | `02` §3.6 |
| `triage.extraBotLogins` | `[String]` | `[]` | Logins treated as bots, `02` §3.5 |
| `triage.countBots` | Bool | `true` | `02` §3.6 |
| `triage.countStale` | Bool | `false` | `02` §3.6 |
| `triage.countDrafts` | Bool | `false` | `02` §3.6 |
| `triage.notifyBots` | Bool | `false` | Review-request notifications and reminders for bot pull requests, `02` §3.6 |
| `mineLayout` | `"list"` \| `"board"` | `"list"` | How *Mine* is shown, `05-design.md` §5.3 |
| `popoverLayout` | `"tabs"` \| `"columns"` | `"tabs"` | The sections one at a time, or side by side in a wider popover, `05-design.md` §5.1 |
| `conflictedDrafts` | `"draft"` \| `"blocked"` | `"draft"` | Which *Mine* group a draft with a conflict goes to, `05-design.md` §5.3 |
| `integrations.terminalApp` | String \| null | `null` | Path of the terminal app; `null` uses the `.command` handler (FR-87) |
| `integrations.reviewCommand` | String | A `claude` command | The template of *Review with AI*; `{url}`, `{repo}`, `{number}`, `{title}`, `{branch}` |
| `integrations.summarizeCommand` | String | A `claude` command | The template of *Summarize with AI* |
| `integrations.clones` | `{owner/name: path}` | `{}` | Local clones the commands run in |
| `notifications.style` | `"card"` \| `"system"` | `"card"` | FR-68: Docket's cards or Notification Center, `05-design.md` §8.1 |
| `notifications.sound` | Bool | `true` | A sound with each new card; Notification Center's sound follows the system settings |
| `notifications.keepCardsUntilActedOn` | Bool | `false` | Review requests, reminders and mentions stay as cards until acted on; off, every card leaves by itself, `05-design.md` §8.1 |
| `notifications.cardSeconds` | `6` \| `10` \| `15` \| `30` | `10` | How long a card stays before it leaves by itself |
| `notifications.reviewRequested` | Bool | `true` | FR-60, one per kind of `02` §5.3 |
| `notifications.reviewSubmitted` | Bool | `true` | |
| `notifications.commentAdded` | Bool | `true` | |
| `notifications.threadReply` | Bool | `true` | |
| `notifications.checksFailed`, `.closedByOther`, `.mention` | Bool | `true` | The P1 kinds (FR-61, FR-62, FR-64); read only once they ship |
| `reminders.enabled` | Bool | `false` | FR-66 |
| `reminders.intervalMinutes` | `15` \| `30` \| `60` \| `120` \| `240` \| `480` | `60` | FR-66 |
| `reminders.quietHours.enabled` | Bool | `false` | FR-67 |
| `reminders.quietHours.start` | `"HH:mm"` | `"22:00"` | Local time, 24-hour; must differ from `end` (`02` §5.7) |
| `reminders.quietHours.end` | `"HH:mm"` | `"08:00"` | May be earlier than `start`: the window crosses midnight |
| `ignored` | `{nodeID: IgnoreEntry}` | `{}` | FR-49; `IgnoreEntry` is `{ref, ignoredAt}`; `Stop Ignoring` deletes it |
| `botAllowlist` | `[String]` | `[]` | Bot logins that may notify (D-16) |
| `ghPath` | String \| null | `null` | Explicit path to `gh` (FR-11) |
| `launchAtLogin` | Bool | `true` once accepted | FR-90; mirrors `SMAppService` and is reconciled with it at launch |
| `updates.automaticChecks` | Bool | `true` | As in Lookout |
| `updates.automaticInstall` | Bool | `false` | As in Lookout |
| `tags` | `{nodeID: TagEntry}` | `{}` | Below |
| `mutes` | `{nodeID: MuteEntry}` | `{}` | FR-63, below |
| `shortcut` | `"off"` \| `"controlOptionCommandD"` \| `"optionCommandD"` \| `"controlOptionD"` | `"controlOptionCommandD"` | The global shortcut that opens the popover (FR-48) |

`TagEntry`:

| Field | Type | Constraint |
|---|---|---|
| `ref` | String | `owner/name#number` at the time of the last edit; refreshed from the snapshot on display |
| `tags` | `[String]` | 1–5 entries; each matches `^[a-z0-9-]{1,24}$`; unique; kept in insertion order (FR-80, FR-81) |
| `updatedAt` | timestamp | Last edit |

`MuteEntry`:

| Field | Type | Constraint |
|---|---|---|
| `ref` | String | As in `TagEntry` |
| `scope` | `"reminders"` \| `"all"` | `02-activity-detection.md` §5.7 |
| `mutedAt` | timestamp | When it was set |

Unmuting deletes the entry. Changing scope replaces it. Ignoring a pull request deletes its mute
entry (`02-activity-detection.md` §5.8).

An entry with zero tags is deleted, not stored empty. Input is normalized before validation —
trimmed, lower-cased, spaces and underscores turned into `-` — so `WIP` and ` wip ` both become
`wip`; anything still outside the pattern is rejected with the reason.

Example:

```json
{
  "botAllowlist": ["copilot-pull-request-reviewer"],
  "count": { "includeBlockedAuthored": true, "includeReviewRequests": true },
  "ghPath": null,
  "ignored": {},
  "launchAtLogin": true,
  "mutes": {
    "PR_kwDOAbc456": { "mutedAt": "2026-10-20T09:12:00Z", "ref": "acme/web#91", "scope": "reminders" }
  },
  "notifications": { "commentAdded": true, "reviewRequested": true, "reviewSubmitted": true, "threadReply": true },
  "polling": { "intervalSeconds": 60 },
  "reminders": {
    "enabled": false,
    "intervalMinutes": 60,
    "quietHours": { "enabled": false, "end": "08:00", "start": "22:00" }
  },
  "selection": {
    "excludedOwners": [],
    "excludedRepositories": ["acme/legacy-monolith"],
    "includedOwners": [],
    "includedRepositories": [],
    "mode": "all"
  },
  "tags": {
    "PR_kwDOAbc123": { "ref": "acme/api#482", "tags": ["wip"], "updatedAt": "2026-10-21T14:03:00Z" }
  },
  "updates": { "automaticChecks": true, "automaticInstall": false },
  "version": 1
}
```

### 2.2 `state.json` — what the app decided

Written by every poll that reaches step 8 of `02-activity-detection.md` §1, and by bookkeeping
(popover opened, update checked). Losing it costs one fresh baseline and nothing you chose.

| Field | Type | Meaning |
|---|---|---|
| `version` | integer | §1 |
| `viewerLogin` | String | The login the cursors belong to. A different login at launch (after `gh auth switch`) discards cursors and ledger and starts a fresh baseline |
| `baselineAt` | timestamp \| null | When the first baseline was established; `null` means the next poll is a baseline (D-19) |
| `cursors` | `{nodeID: Cursor}` | `02` §5.1 |
| `delivered` | `{eventID: timestamp}` | Events handed to macOS, for 14 days (`02` §5.6) |
| `reminders` | `{nodeID: ReminderRecord}` | One per pending review request: `requestedAt` and `lastRemindedAt` (timestamp \| null), `02` §5.7 |
| `focusHold` | `{since: timestamp}` \| null | Set while a Focus hold is on (`02` §7.5); `null` otherwise |
| `held` | `[HeldEvent]` | Events committed during a hold, awaiting the digest: `{eventID, kind, nodeID, ref, actor, decision, at}`, at most 500, oldest dropped first |
| `marked` | `[nodeID]` | Pull requests with an event since the popover was last opened (FR-46) |
| `popoverOpenedAt` | timestamp \| null | Clears `marked` |
| `teams` | `{owner: {slugs: [String], fetchedAt: timestamp}}` | Your team slugs per organization, refreshed hourly (`02` §2.2) |
| `unauthorizedOwners` | `[String]` | Organizations needing SAML authorization (FR-13) |
| `lastPoll` | `{at, cost, remaining, limit, resetAt, serverTimeOffset}` | Rate budget and clock offset (`02` §3.4, §6.3) |
| `lastShownVersion` | String | For What's New |
| `skippedVersion` | String \| null | Update the user chose to skip |
| `lastUpdateCheckAt` | timestamp \| null | Update cadence |
| `baselineNoticeDismissed` | Bool | The first-run banner of `05-design.md` §7.2 was dismissed with `OK` |
| `seen` | `{nodeID: timestamp}` | When you last opened each pull request from Docket, or marked it seen. A row is unseen when it has no entry, or a human other than you acted on it after (`02` §3.5) |
| `seenBaselineAt` | timestamp \| null | The first poll with seen state, which marked everything then listed as seen, so an upgrade does not light up every row |

`Cursor`:

| Field | Type | Constraint |
|---|---|---|
| `ref` | String | Display only |
| `role` | `"authored"` \| `"reviewRequested"` \| `"involved"` \| null | `null` once the pull request has left the watch set |
| `updatedAt` | timestamp | The summary's `updatedAt` at the last detail read |
| `enteredAt` | timestamp | §5.1 of `02` |
| `leftAt` | timestamp \| null | Set when it leaves the watch set; cleared if it returns |
| `seen` | `[String]` | At most 500 IDs, oldest dropped first |
| `lastMergeable` | `"MERGEABLE"` \| `"CONFLICTING"` \| null | `02` §3.1 |
| `notifiedFailingHead` | String \| null | The head commit whose failing checks were last notified (FR-61); absent in files written before 1.1 and read as `null` |

**Event IDs** are derived, not GitHub's: `<kind>:<item node ID>` for single items, so the ledger
key of `@ana approved` is `reviewSubmitted:PRR_kw…`. A folded event uses the ID of the item that
carries it.

### 2.3 `cache/snapshot.json` — what GitHub said last

The last successful poll's summaries, so the popover renders immediately at launch and offline
(FR-44). Statuses, roles and the count are **not** cached: they are recomputed from the cached
summaries by `DocketActivity`, so a rule change in an update applies to cached data too.

| Field | Type | Meaning |
|---|---|---|
| `version` | integer | §1 |
| `fetchedAt` | timestamp | Drives "updated N min ago" |
| `viewerLogin` | String | A mismatch with `state.json` discards the cache |
| `pullRequests` | `[PullRequestSummary]` | The fields of the summary query in `02` §6.1, `pendingChecks` from the checks query while the rollup is pending, plus each pull request's latest review-request time and requester for display, and `activity`: the latest review, comment or request per actor from the last detail read, with `activityRead` once a detail was read (`02` §3.5); `links` from the description, and `botLinks` from bots' comments with `linksRead` once a detail was read since they existed, so the next poll reads each detail once (`05-design.md` §6.5) |
| `knownRepositories` | `[{name, lastSeenAt}]` | Repositories seen in the last 90 days, for the selection picker (FR-73) |

`cache/` is marked `isExcludedFromBackup`: it is rebuilt by one poll and holds titles from private
repositories that do not need to be in Time Machine.

## 3. Derived data

Nothing is derived and stored except where the derivation needs history:

| Value | Derived from | Stored? |
|---|---|---|
| Role, status, age, count, reviewer list | Summary + config + now | No — recomputed per render |
| Events | Detail + cursor | No — only their IDs, in `delivered` |
| `marked` | Events since `popoverOpenedAt` | Yes, because the events themselves are not kept |
| `lastMergeable` | Previous summaries | Yes, because `UNKNOWN` needs a previous value (`02` §3.1) |
| `lastRemindedAt` | Reminders delivered | Yes, because the next due time is relative to the last reminder (`02` §5.7) |
| Team slugs | `organization.teams` | Yes, an hourly cache, because they change rarely and cost a query per organization |

## 4. Retention

Run once at launch and then daily, in `DocketPersistence.Retention`, as a pure function over the
files and `now`.

| Data | Deleted when |
|---|---|
| A cursor | 30 days after `leftAt` |
| A tag entry | When its pull request has neither a role in the current snapshot nor a cursor — which is 30 days after it left the watch set (FR-84) |
| A mute entry, an ignore entry | Same rule as a tag entry |
| `held` entries | When the digest is delivered, or when their pull request leaves the watch set or is muted or ignored |
| A reminder record | When its pull request stops being pending (`02` §5.7) |
| A `delivered` entry | 14 days after its timestamp |
| `marked` entries | When the popover opens, and when the pull request leaves the watch set |
| `seen` entries | With the pull request's cursor, like a mute |
| `teams` for an organization | When no watched pull request belongs to it for 30 days |
| `knownRepositories` entries | 90 days after `lastSeenAt` |
| `state.corrupt-*.json` | 7 days after it was set aside |

Deleting the whole folder is always safe: the next launch is a first launch (D-19) and you lose
your selection and tags, nothing else.

## 5. What is deliberately not stored

| Not stored | Why |
|---|---|
| **The token** | Read from `gh` at launch and on `401` (D-02). A second copy would be a second thing to revoke and a second place to leak from |
| **Comment and review bodies** | The notification is a pointer to the conversation, not a copy of it. Review `body` is read only to test emptiness (`02` §5.5) and discarded; comment and review text is read only to extract the logins it mentions (`02` §5.3 `mention`) and, for a bot's conversation comment, the links in it (`PR Links`, at most 8 per bot), and discarded the same way |
| **Diffs, file names, code** | Docket does not read them at all (`01-product.md` §6) |
| **Notification history** | Only event IDs for deduplication. A history would be a second inbox, which is what Docket replaces |
| **Avatars** | Logins are shown as text (`05-design.md`). Avatars would add an image host, a cache and colleagues' faces on disk for no decision they change |
| **E-mail addresses, names, other profile fields** | Not queried, except the head commit's git author name, read only to tell a bot's commit (`dependabot[bot]`) and discarded |
| **Pull request bodies** | Read only to extract issue links for *Open in Jira* (`02` §6.1) and the links for `PR Links` (at most 10, images and badges left out); the links and their own text are kept, the rest is discarded |
| **GitHub's notification inbox** | Never read (D-07) |
| **Anything about pull requests outside the watch set** | Discovery returns IDs; only watched ones are summarized |

## 6. Security

- **The token** lives in one actor property for the life of the process. It is sent only to
  `api.github.com` (and to GitHub's release asset hosts by the updater), never logged in any form,
  never passed in a child process's environment or arguments, never written to disk or the
  pasteboard. `gh` keeps the long-lived copy in the macOS Keychain; that is `gh`'s storage, not
  Docket's.
- **Files** are `0600` in a `0700` directory (§1). Docket does not use the Keychain itself.
- **No listener.** Docket opens no port and has no URL scheme that acts on data; notification
  clicks only open GitHub URLs or the popover.
- **Repository hygiene.** Fixtures are synthetic; real logins, organizations, repository names and
  titles are never committed, and gitleaks runs on staged files and on pull requests
  (`06-engineering-practices.md`). The repository is private now and is written as if it were
  public.

## 7. Privacy

Docket is a personal tool on your own Mac. What it stores about other people is what any GitHub
client shows you — logins and pull request titles from repositories you can read — and it stores it
only locally, under §1's permissions, for the retention of §4.

That data still belongs to whoever owns those repositories, usually an employer. Their policy on
local copies of private repository metadata applies to Docket exactly as it applies to a browser
cache. No LGPD processing takes place beyond that: nothing leaves the Mac (PROJECT.md
principle 4), and there is no second party to send a request to.

**Deletion path:** quit Docket, delete `~/Library/Application Support/Docket/`, and remove the app.
Notification Center's delivered notifications are removed by macOS with the app.
