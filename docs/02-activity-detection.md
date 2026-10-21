# 02 — Activity detection

How a poll turns GitHub's current state into the watch set, a status per pull request, the "needs
you" count, and the few notifications worth sending. If Docket gets exactly one thing right, it is
this: every rule here is a pure function in `DocketActivity` (`03-architecture.md` §3), and every
worked example in §8 is a test case verbatim.

## 1. The flow end to end

One poll, in order. After each step, what is true.

1. **Discover.** Four GraphQL searches return the node IDs of candidate pull requests (§2.1).
   *True after:* Docket knows every open pull request GitHub's search index associates with you —
   possibly a minute behind (§9).
2. **Summarize.** One `nodes(ids:)` query per 100 IDs reads the summary of every candidate **and**
   every pull request already in the watch set (§6.1). *True after:* Docket knows the current
   author, review requests, decision, mergeability, checks and `updatedAt` of each, read by ID and
   therefore not subject to search lag.
3. **Assign roles and apply the selection.** Each pull request gets one role or none (§2.2), and
   the selection removes the ones you do not watch (§2.3). *True after:* the watch set for this
   poll is final.
4. **Detail.** One `nodes(ids:)` query per 10 pull requests reads reviews, comments, review threads
   and review-request events — only for pull requests that entered the watch set or whose
   `updatedAt` differs from their cursor (§6.1). *True after:* every pull request that changed has
   its items in hand.
5. **Derive.** Status per pull request (§3), age (§3.4), the count (§4). *True after:* the popover
   and the status item can render.
6. **Diff.** Each changed pull request's items are compared with its cursor, producing events (§5).
   Every pending review request is compared with the clock, producing reminders (§5.7).
   *True after:* Docket knows what is new, who did it, and what has waited too long.
7. **Compose.** Events are filtered (§5.4), folded (§5.5); events and reminders are coalesced by
   repository and kind, and capped (§7). *True after:* at most five notifications are ready.
8. **Commit, then deliver.** The new snapshot, the advanced cursors, the reminder records and the
   delivered-event ledger are written to disk atomically, **then** the notifications are handed to
   macOS (§5.6).

A poll that fails at any step before 8 writes nothing and changes nothing; the next poll repeats it
from step 1 (PROJECT.md principle 2).

## 2. The watch set

### 2.1 Discovery

Four searches, in one GraphQL document, with `first: 50` each and only `id` and `updatedAt`
requested, so discovery costs one point (§6.2). `<login>` is the viewer's login, read once per
launch from `viewer { login }`; `<since>` is today minus 30 days in UTC, as `YYYY-MM-DD`.

| Alias | Query string | Finds |
|---|---|---|
| `authored` | `is:pr is:open archived:false author:<login>` | Pull requests you wrote |
| `requested` | `is:pr is:open archived:false review-requested:<login>` | Pending review requests to you or to a team you are in |
| `commented` | `is:pr is:open archived:false commenter:<login> -author:<login> updated:>=<since>` | Pull requests you commented on |
| `reviewed` | `is:pr is:open archived:false reviewed-by:<login> -author:<login> updated:>=<since>` | Pull requests you reviewed |

A search with more than 50 results is paginated up to 150. Beyond that, the section shows
"+N not shown" and the overflow is not watched; at that volume the selection is the tool.

Search finds candidates; it does **not** decide roles. Roles come from the summary of step 2,
which is read by ID and is current even when the index is not.

### 2.2 Roles

Exactly one role per pull request, by precedence (D-08):

| Role | Condition, evaluated on the summary |
|---|---|
| `authored` | `author.login` equals your login (case-insensitive) |
| `reviewRequested` | `reviewRequests` contains you, **or** contains a team you belong to and you have not submitted a review after the latest request to that team |
| `involved` | Found by `commented` or `reviewed` in this poll, or already `involved` in the previous snapshot and `updatedAt` within 30 days |
| none | Anything else; the pull request leaves the watch set |

A pull request that is closed or merged has no role, whatever else is true.

**Team membership** is read once per hour per organization with
`organization(login:) { teams(first: 100, userLogins: [<login>]) { nodes { slug } } }`, which
needs `read:org`. Without it, a team request counts as yours when the `requested` search returned
the pull request, and the row says "via a team" instead of naming it.

**Why the team rule has a second clause.** Whether GitHub keeps a team's request pending after one
member reviews depends on the repository's settings, so the summary alone cannot say whether the
request still needs *you*. If you reviewed after the latest request to the team, it does not, and
the pull request drops to `involved`.

### 2.3 Selection

The selection is applied after roles, to the list, the count and notifications alike (FR-74).

| Mode | Watched |
|---|---|
| `all` (default) | Every repository, except those in `excludedRepositories` and those whose owner is in `excludedOwners` |
| `only` | Only repositories in `includedRepositories` and repositories whose owner is in `includedOwners` |

Comparison is case-insensitive on `owner/name`. A repository excluded and later included again
keeps its cursors for 30 days (`04-data.md` §4), so re-including it does not re-notify old items.

### 2.4 Entering and leaving

A pull request **enters** the watch set when it gains a role. On entry its cursor is seeded with
every item currently visible, so its history never notifies (§5.2). The one exception is the
review request that caused the entry, when it is newer than the previous poll: a request made while
Docket was closed notifies (§8 #2), one made while the repository was excluded does not (§8 #18).

A pull request **leaves** when it loses its role, is closed or merged, is excluded by the
selection, or returns `NOT_FOUND` because access was lost. Its cursor and tags are kept for 30
days.

## 3. Status

### 3.1 Inputs

| Field | Source | Values |
|---|---|---|
| `mergeable` | `PullRequest.mergeable` | `MERGEABLE`, `CONFLICTING`, `UNKNOWN` |
| `checks` | `commits(last: 1).nodes[0].commit.statusCheckRollup.state` | `SUCCESS`, `FAILURE`, `ERROR`, `PENDING`, `EXPECTED`, or `null` when there are no checks |
| `decision` | `PullRequest.reviewDecision` | `APPROVED`, `CHANGES_REQUESTED`, `REVIEW_REQUIRED`, or `null` when no rule requires a review |
| `latestReviews` | `latestOpinionatedReviews(first: 10)` | Each reviewer's latest `APPROVED` or `CHANGES_REQUESTED` |
| `pendingRequests` | `reviewRequests(first: 10)` | Users and teams |
| `isDraft` | `PullRequest.isDraft` | — |

`UNKNOWN` mergeability means GitHub is still computing it, usually for a few seconds after a push.
It is replaced by the last known value from the previous snapshot, or treated as `MERGEABLE` when
there is none.

**Approved** means `decision == APPROVED`, or `decision == null` with at least one `APPROVED` in
`latestReviews` and no `CHANGES_REQUESTED`. **Changes requested** means `decision ==
CHANGES_REQUESTED`, or `decision == null` with a `CHANGES_REQUESTED` in `latestReviews`. The
`null` clauses exist because most repositories without branch rules still get reviews.

### 3.2 Precedence

The first row that matches is the status. The order is "what you must do first":

| # | Status | Condition | Why here |
|---|---|---|---|
| 1 | `conflict` | `mergeable == CONFLICTING` | Nothing else can land until you rebase; checks and reviews may be redone after it |
| 2 | `checksFailing` | `checks` is `FAILURE` or `ERROR` | Yours to fix, and reviewers often wait for green |
| 3 | `changesRequested` | Changes requested | A person is waiting on you |
| 4 | `checksRunning` | `checks` is `PENDING` or `EXPECTED` | Nobody can act yet; above `readyToMerge` so an approval with running checks is not called ready |
| 5 | `readyToMerge` | Approved and `checks` is `SUCCESS` or `null` | Yours to merge |
| 6 | `waitingForReview` | `pendingRequests` is not empty | Somebody else's move |
| 7 | `noReviewers` | None of the above | Nobody has been asked |

`isDraft` never changes the status. It is a modifier shown beside it (FR-31) and it removes the
pull request from the count (§4).

Rows in *Review requested* show the waited time first and the status as a secondary chip, because
the action is yours either way. Rows in *Mine* and *Involved* show the status first.

### 3.3 Reviewers

For authored pull requests (FR-35), the row lists each reviewer once: pending requests first, then
reviewers from `latestReviews` with their decision, then reviewers whose only reviews are
`COMMENTED`. A reviewer both requested and with a decision shows the decision, with "re-requested".

### 3.4 Age

Ages are computed from server timestamps against the Mac's clock corrected by the offset to the
`Date` header of the last API response, so a Mac whose clock is off by minutes still shows the
right age.

| Elapsed | Shown |
|---|---|
| < 1 min | `now` |
| < 60 min | `Nm` |
| < 24 h | `Nh` |
| < 14 d | `Nd` |
| ≥ 14 d | `Nw` |

Always rounded down: 59 min 59 s is `59m`; 13 d 23 h is `13d`; 14 d is `2w`.

| Age | Style |
|---|---|
| ≤ 72 h | Normal |
| > 72 h | Ageing — a filled dot before the age |
| > 7 d | Stale — a filled dot and the age in bold |

The age of a pull request runs from `createdAt` (FR-32). The waited time of a review request runs
from the `createdAt` of the latest `ReviewRequestedEvent` addressed to you or to a team you belong
to (FR-33); when no such event is visible in the last 20 timeline items, from `createdAt` of the
pull request.

**What this gets wrong:** ages are calendar time. A request made on Friday at 17:00 is `3d` on
Monday morning and marked ageing. Working hours would need a calendar and a timezone per
colleague; **revisit if** weekends make the ageing marker useless in practice.

## 4. The "needs you" count

The number in the menu bar (FR-40) is the sum of:

- every pull request with role `reviewRequested`; and
- every pull request with role `authored`, not a draft, whose status is `conflict`,
  `checksFailing`, `changesRequested` or `readyToMerge`;

in both cases excluding pull requests you ignored (§5.8).

`involved` pull requests never count: nothing in them is waiting on you by definition. A draft
never counts, because a draft is a pull request you have said is not ready. Each half can be turned
off in settings; with both off, the item shows only the icon.

## 5. Events

### 5.1 The cursor

One cursor per watched pull request, persisted in `state.json` (`04-data.md` §2.2):

| Field | Meaning |
|---|---|
| `updatedAt` | The summary's `updatedAt` when the details were last read. Different from the summary → fetch details |
| `seen` | IDs of every review, comment, review-thread comment and review-request event already processed, at most 500, oldest dropped first |
| `enteredAt` | When the pull request entered the watch set |
| `lastMergeable` | Last known non-`UNKNOWN` mergeability |

An item is **new** when its ID is not in `seen` and its `createdAt` (or `submittedAt`) is after
`enteredAt`. The second clause protects against an old item sliding back into the `last: 30`
window after newer items are deleted.

### 5.2 Baseline

- **Fresh install** (no `state.json`): the first successful poll seeds every cursor and emits no
  events (D-19). The count and the list are complete from that first poll.
- **Later launches:** the saved cursors are the baseline. What happened while Docket was closed is
  new, and is coalesced and capped like any other poll.
- **Entering the watch set** (§2.4): `seen` is seeded with every visible item, so only the request
  that caused the entry can notify.

### 5.3 Event kinds

Evaluated per new item. Each kind can be turned off in settings (FR-60).

| Kind | Fires when | FR |
|---|---|---|
| `reviewRequested` | A new `ReviewRequestedEvent` whose `requestedReviewer` is you or a team you belong to, and the pull request's role is `reviewRequested` at this poll | FR-50 |
| `reviewSubmitted` | A new review on an `authored` pull request, state `APPROVED`, `CHANGES_REQUESTED` or `COMMENTED` | FR-51 |
| `commentAdded` | A new conversation comment (`PullRequest.comments`) on an `authored` pull request | FR-52 |
| `threadReply` | A new review-thread comment, on a pull request of any role, in a thread where an earlier comment is yours | FR-53 |
| `checksFailed` | An `authored` pull request whose `checks` is `FAILURE` or `ERROR` on a head commit other than the cursor's `notifiedFailingHead`; the cursor then records that head. On entry and on the baseline the head is recorded without notifying | FR-61 |
| `closedByOther` | An `authored` pull request leaves the watch set as `MERGED` or `CLOSED`, and the actor who merged it (`mergedBy`) or closed it (the latest `ClosedEvent`) is not you | FR-62 |
| `mention` | A new conversation comment, review or review-thread comment by someone else whose text contains `@<your login>` as a whole word, on a pull request of any role. It replaces the `commentAdded` or `threadReply` the same item would have fired, because it says more | FR-64 |

Reviews in state `PENDING` (unsubmitted drafts) and `DISMISSED` never fire.

**A conversation comment on a pull request that is not yours never fires.** The conversation tab
has no reply structure, so every comment after yours would count as a reply, which is the noise of
PROJECT.md §1. A comment that mentions you is the P1 `mention` kind (FR-64).

**Mentions are matched, never stored.** The detail query reads the text of comments and reviews;
the client keeps only the logins mentioned in each and discards the text (`04-data.md` §5). A team
mention (`@acme/backend`) is not a mention of you. Your own items never mention you (§5.4).

**A request removed before the poll sees it never fires.** The role check is part of the
condition, so a request made and withdrawn between two polls is invisible, which is correct.

### 5.4 Who never notifies

Applied before folding:

1. **You.** Any item whose author's login is yours (FR-56).
2. **Bots.** Any item whose author's `__typename` is `Bot`, or whose login ends in `[bot]`, unless
   that login is in `botAllowlist` (FR-57, D-16).
3. **Muted pull requests** with scope `all` (FR-63, §5.7), and **ignored** pull requests (FR-49,
   §5.8). A mute with scope `reminders` does not filter events.

### 5.5 Folding

One action on GitHub can produce several new items. They are folded so the action notifies once:

1. **A review and its inline comments are one event.** Review-thread comments whose
   `pullRequestReview.id` is a review that fired `reviewSubmitted` in this poll are absorbed into
   it.
2. **A reply-only review is a reply, not a review.** A `COMMENTED` review on an authored pull
   request whose `body` is empty and whose every comment is a reply in a thread with a comment of
   yours becomes `threadReply` events instead of a `reviewSubmitted`. This is how GitHub records
   "they answered your comment on your own pull request", and calling it "commented" would hide
   what happened.
3. **One reviewer, several reviews in one poll** — for example a comment and then an approval —
   folds into the latest one, which carries the decision.

### 5.6 Delivery is at most once

The poll writes the advanced cursors and the IDs of the events it is about to deliver, then hands
the notifications to macOS. If the app dies between the two, those events are lost, not repeated.
That is principle 1 applied: a missed notification costs a delay and the item is still in the list,
marked; a duplicate teaches the user to ignore Docket. The `delivered` ledger (`04-data.md` §2.2)
keeps event IDs for 14 days as a second guard against a cursor being rebuilt.

### 5.7 Reminders

A reminder is not an event: nothing changed on GitHub. It is derived from a review request that is
still pending and from the clock, so it has its own rule and its own record in `state.json`
(`04-data.md` §2.2), one per pull request.

**Pending.** A pull request is pending when its role is `reviewRequested` (§2.2), it is not a draft,
it is in the selection, and it is neither muted (below) nor ignored (§5.8). `requestedAt` is the
start of the waited time of §3.4: the latest `ReviewRequestedEvent` addressed to you or a team you
belong to. Reviewing removes you from `reviewRequests`, so a review ends the reminders by ending the
role.

**Due.** With `interval` from `config.json` and `now` corrected as in §3.4:

```
due ⇔ reminders.enabled
    ∧ pending
    ∧ now ≥ (lastRemindedAt ?? requestedAt) + interval
    ∧ ¬ inQuietHours(now, timeZone)
    ∧ ¬ holding
```

`holding` is the Focus hold of §7.5. Presence is not an input: a reminder is sent when due
whether or not anybody is at the Mac, and nothing extra makes up for one nobody saw (D-26).

A reminder that is delivered sets `lastRemindedAt = now`. So the first reminder comes one interval
after the request, and each further one an interval after the previous reminder (D-23) — never two
in a row to catch up on time Docket missed asleep, closed or inside quiet hours.

**The record** is keyed by the pull request's node ID and holds `requestedAt` and
`lastRemindedAt`:

| Situation | Record |
|---|---|
| `requestedAt` differs from the record's — a re-request after you reviewed — and its event is not visible | Replaced: `requestedAt` is the new one, `lastRemindedAt = null` |
| Created on the fresh-install baseline (D-19), or for a request older than the poll that first sees it — the repository was just included again, the team membership was just learned | `lastRemindedAt = now`, nothing delivered: the first reminder is one interval away, so neither launching nor changing the selection produces a burst |
| Created or replaced for a request whose `ReviewRequestedEvent` is new in this poll (§5.1) | `lastRemindedAt = now`: the `reviewRequested` event notifies now and counts as the first notice, so the reminder is one interval later even when the request was made while Docket was closed |
| The pull request stops being pending | Deleted |
| `interval` changed in settings | Nothing: the next due time is recomputed from the record with the new interval, so shortening it can make a reminder due at the next poll — one, not one per missed interval |

**Quiet hours** (FR-67, D-24) are `start` and `end` in local time, `HH:mm`. `now` is inside when
`start < end` and `start ≤ local(now) < end`, or when `start > end` (the window crosses midnight)
and `local(now) ≥ start ∨ local(now) < end`. `start == end` is rejected by the settings control.
The time zone is an argument, like `now` (`03-architecture.md` §3), so a trip across time zones
moves the window with the Mac's clock, and the DST changeover is a test case. Quiet hours apply to
reminders only: events still notify, and Focus decides how (D-22).

**Mute** (FR-63) has two scopes, stored in `config.json` (`04-data.md` §2.1):

| Scope | Events | Reminders | Undone by |
|---|---|---|---|
| `reminders` | Notify | Never | `Unmute Reminders` in the context menu |
| `all` | Never (§5.4 rule 3) | Never | `Unmute Notifications` in the context menu |

A mute is on the pull request, not on one request: a re-request does not undo it. A muted pull
request stays in the list and in the count, because mute is about being told, not about what needs
you. The reminder notification's `Mute Reminders` action (`05-design.md` §8) writes scope
`reminders` for that pull request.

### 5.8 Ignoring

**Ignore** (FR-49, D-27) is the strongest of the three per-pull-request choices:

| Choice | Notifies | Reminds | In the count | In the list |
|---|---|---|---|---|
| Mute, scope `reminders` | Yes | No | Yes | Its section |
| Mute, scope `all` | No | No | Yes | Its section, with `bell.slash` |
| Ignore | No | No | **No** | The collapsed **Ignored** section, last |

An ignored pull request keeps its role, cursor and tags: its cursor still advances at every poll,
so nothing that happened while it was ignored notifies when it stops being ignored. Ignoring
replaces a mute; `Stop Ignoring` restores nothing but the default, so a pull request that was muted
before being ignored is unmuted after.

**Ignore holds until it is undone, or until the pull request leaves the watch set for 30 days**
(the retention of a tag, `04-data.md` §4). A re-request does not end it: the point of ignoring is
that this pull request's requests are not yours to act on, and a re-request is the most common one.

### 5.9 Reminder delivery

**Delivery** follows §5.6: `lastRemindedAt` is committed before the notification is handed to
macOS. A reminder folded into the overflow notification of §7.3 counts as delivered, so a capped
reminder does not come back at every poll.

## 6. Polling and the rate budget

### 6.1 Queries

Every query includes `rateLimit { cost remaining limit resetAt }`, and the cost is logged.

**Summary**, per batch of up to 100 IDs:

```graphql
nodes(ids: $ids) {
  ... on PullRequest {
    id number title url state isDraft createdAt updatedAt
    author { __typename login }
    repository { nameWithOwner isArchived }
    mergeable reviewDecision
    commits(last: 1) { nodes { commit { oid statusCheckRollup { state } } } }
    reviewRequests(first: 10) {
      nodes { requestedReviewer { __typename ... on User { login } ... on Team { slug organization { login } } } }
    }
    latestOpinionatedReviews(first: 10) { nodes { author { login } state } }
  }
}
```

**Detail**, per batch of up to 10 IDs:

```graphql
nodes(ids: $ids) {
  ... on PullRequest {
    id
    reviews(last: 30) { nodes { id state body submittedAt author { __typename login } } }
    comments(last: 30) { nodes { id url createdAt author { __typename login } } }
    reviewThreads(last: 30) {
      nodes { id comments(last: 20) { nodes { id url createdAt author { __typename login } pullRequestReview { id } } } }
    }
    timelineItems(last: 20, itemTypes: [REVIEW_REQUESTED_EVENT]) {
      nodes { ... on ReviewRequestedEvent { id createdAt actor { __typename login }
        requestedReviewer { __typename ... on User { login } ... on Team { slug organization { login } } } } }
    }
  }
}
```

Review `body` is read only to decide whether it is empty (§5.5) and is never stored or shown
(`04-data.md` §5).

### 6.2 Cost

GitHub computes a query's cost from the page sizes it asks for, not from what comes back: one
request per connection plus one per nested connection per parent, divided by 100.

| Query | Requests | Points |
|---|---|---|
| Discovery: 4 searches × `first: 50`, no nested connections | 4 | 1 |
| Summary: 100 IDs × 3 nested connections | ~300 | 3 |
| Detail: 10 IDs × (4 connections + 30 threads' comments) | ~340 | 4 |

A quiet poll with up to 100 watched pull requests costs about 4 points; at the default 60 s
interval that is about 240 points an hour, under 5% of the 5000-point budget, which is what NFR-01
and D-06 rest on. These are estimates from GitHub's published formula. **The logged
`rateLimit.cost` is the authority**, and `docket-cli poll` prints it so the estimate can be checked
against a real account.

### 6.3 Cadence and backoff

| Condition | Behaviour |
|---|---|
| Normal | Poll every interval (FR-92), with ±10% jitter |
| `remaining` < 30% of `limit` | Double the interval until `resetAt` |
| `remaining` < 20% of `limit` | No poll until `resetAt` (NFR-03); the popover says until when |
| `403`/`429` with `Retry-After` (secondary limit) | Wait exactly that long, then resume |
| Network error | Retry after 15 s, 30 s, 60 s, then the normal interval |
| Mac asleep | No poll; one poll on wake (FR-95) |
| Offline (`NWPathMonitor`) | No poll; one poll on reconnect |
| Popover opened, last poll older than 30 s | One poll now |
| A Focus hold ends (§7.5) | One poll now, then the digest |

Two polls never overlap: the poller is an actor and a poll requested while one is running is
dropped, not queued.

## 7. Notifications

### 7.1 Coalescing

Events left after §5.4 and §5.5 are grouped by `(repository, kind)`. Each group becomes one
notification. Within a group, items are ordered oldest first.

| Group size | Title | Subtitle | Body |
|---|---|---|---|
| 1 × `reviewRequested` | `Review requested by @ana` | `acme/api #482` | `Fix login redirect loop` · `via @acme/backend` when through a team |
| n × `reviewRequested` | `3 reviews requested` | `acme/api` | One line per pull request: `#482 Fix login redirect loop` |
| 1 × `reviewSubmitted` | `@bruno approved` / `@bruno requested changes` / `@bruno commented` | `acme/api #470` | The pull request title |
| n × `reviewSubmitted` | `2 reviews on your pull requests` | `acme/api` | `@bruno approved #470`, `@carla requested changes #471` |
| 1 × `threadReply` | `@carla replied to your comment` | `acme/web #88` | The pull request title |
| n × `threadReply` | `3 replies to your comments` | `acme/web` | `@carla on #88`, `@dave on #91` |
| 1 × `commentAdded` | `@dave commented` | `acme/api #470` | The pull request title |
| n × `commentAdded` | `4 comments on your pull requests` | `acme/api` | `@dave on #470` |
| 1 × `reviewReminder` | `Your review is still waiting` | `acme/api #482` | `Fix login redirect loop` · `requested 2h ago by @ana` |
| n × `reviewReminder` | `3 reviews still waiting for you` | `acme/api` | One line per pull request: `#482 Fix login redirect loop · 2h` |
| 1 × `checksFailed` | `Checks failed` | `acme/api #470` | The pull request title |
| n × `checksFailed` | `Checks failed on 2 pull requests` | `acme/api` | One line per pull request: `#470 Cache the account lookup` |
| 1 × `closedByOther` | `@bruno merged your pull request` / `@bruno closed your pull request` | `acme/api #470` | The pull request title |
| n × `closedByOther` | `2 pull requests closed` | `acme/api` | One line per pull request |
| 1 × `mention` | `@carla mentioned you` | `acme/web #88` | The pull request title |
| n × `mention` | `3 mentions` | `acme/web` | `@carla on #88` |

Copy lives in `Localizable.xcstrings` (D-18); the strings above are the English source values and
the exact composition is in `05-design.md`.

### 7.2 Grouping in Notification Center

Every notification carries `threadIdentifier = "repo:<owner/name>"` and the repository name as its
summary argument, so macOS stacks one repository's notifications together (FR-54).

### 7.3 The cap

At most five notifications per poll (FR-55). When there are more groups, the four with the highest
priority are delivered and the fifth says `N more updates in M repositories` and opens the popover.

Priority, highest first: `reviewRequested`, then `reviewSubmitted` with changes requested and
`checksFailed`, `reviewSubmitted` approved and `closedByOther`, `threadReply` and `mention`,
`reviewSubmitted` commented, `commentAdded`, `reviewReminder`. Ties are broken by the oldest event in the group. Reminders come last because
they repeat what the list already says; something that happened outranks something that is still
true.

### 7.4 What a click opens

| Notification | Opens |
|---|---|
| One `threadReply` or `commentAdded` | The comment's `url` |
| Any other single event, or one reminder | The pull request's `url` |
| A group, or the "more updates" one | The popover, filtered to that repository (FR-59) |

### 7.5 Holding during Focus

macOS gives an app no notification when a Focus starts or ends, and the API that reports whether
one is on (`INFocusStatusCenter`) needs an entitlement a self-signed app cannot carry (D-25).
What it does give is a **Focus filter**: an App Intent (`SetFocusFilterIntent`) the user adds to a
Focus in **System Settings → Focus → *a Focus* → Focus Filters**. Docket's filter has one parameter,
`Hold notifications until this Focus ends`, default off; the user turns it on when adding the
filter. macOS calls the intent with the configured value when that Focus turns on, and again with
the default when its values stop applying — which is when the Focus ends.

| State | Events | Reminders |
|---|---|---|
| Not holding | Delivered as in §7.1–§7.3 | §5.7 |
| Holding | Diffed, filtered and folded as usual, then appended to `held` in `state.json` instead of being delivered; rows are marked (FR-46) | Not sent and not queued: the digest says what is pending |
| Hold ends | One poll, then the **digest** | Resume from their records; nothing is due merely because the hold ended |

**The digest** is one notification per repository with held events, whatever their kinds:

| Title | Subtitle | Body |
|---|---|---|
| `While you were in Focus` | `acme/api` | One line per kind present, in the priority order of §7.3: `2 reviews requested`, `@bruno approved #470`, `1 reply to your comments` |

The cap of five holds: four repositories, then `N more updates in M repositories`. Held events are
committed as held, and moved to `delivered` in the same write that precedes the digest, so a crash
loses a digest rather than repeating it (§5.6). A held event whose pull request has since left the
watch set, or was muted or ignored, is dropped from the digest.

**Safety.** A hold that started more than 12 hours ago ends by itself, because the end of a Focus
is the one call macOS might not make — on macOS 26.5, `perform` of a Focus filter is reported not
to be called at all (`07-roadmap.md` §11). The popover shows the hold as a banner with
`Deliver Now` (`05-design.md` §7.2). Without the filter in any Focus, nothing in this section
happens and Focus treats Docket's notifications like any other app's (D-22).

## 8. Worked examples

Each row is a test in `DocketActivityTests`, built from synthetic snapshots. Logins: you are
`you`; colleagues are `ana`, `bruno`, `carla`, `dave`.

| # | Given | Expected | Why |
|---|---|---|---|
| 1 | Fresh install; 4 pending review requests in 2 repositories | 0 notifications; count 4 | D-19. The naive answer — 4 notifications, or 2 grouped — makes the first launch a burst of things you already knew |
| 2 | Saved state; Docket quit for 2 h; `ana` requested your review on `acme/api#482` meanwhile | 1 notification, `Review requested by @ana` | The saved cursors are the baseline, so time closed is not time lost |
| 3 | You reviewed `acme/api#482`; `ana` re-requests | 1 `reviewRequested` | A new `ReviewRequestedEvent` ID, and the role is `reviewRequested` again |
| 4 | `ana` requests and withdraws your review between two polls | 0 notifications | The role check fails at the poll that sees the event |
| 5 | `ana` approves your `acme/api#470` with 3 inline comments | 1 notification, `@ana approved` | §5.5 rule 1. The naive answer is 4 |
| 6 | `bruno` answers your inline comment on your own `acme/api#470`; GitHub records a `COMMENTED` review with an empty body and one reply | 1 `threadReply`, `@bruno replied to your comment` | §5.5 rule 2. The naive answer is `@bruno commented`, which hides that it was an answer |
| 7 | On `carla`'s `acme/web#88` (role `involved`), `carla` replies in a thread you started; `dave` adds a conversation comment | 1 `threadReply` from `carla`; nothing for `dave` | §5.3: conversation comments on others' pull requests never fire |
| 8 | You comment on your own pull request; `dependabot[bot]` comments on it | 0 notifications | §5.4 rules 1 and 2 |
| 9 | `copilot-pull-request-reviewer` (typed `Bot`) reviews your pull request, and its login is in `botAllowlist` | 1 `reviewSubmitted` | D-16's allowlist |
| 10 | After a night asleep: 12 review requests in 4 repositories, and reviews on your pull requests in 2 repositories | 5 notifications: 4 `reviewRequested` groups, then `N more updates in 2 repositories` | §7.3: requests outrank reviews; the cap holds after any gap |
| 11 | Your pull request was `CONFLICTING`; you push; the summary says `UNKNOWN` | Status stays `conflict` until a known value arrives | §3.1. The naive answer flips to `waitingForReview` and back |
| 12 | Approved, checks `PENDING` | `checksRunning`, not counted | §3.2 row 4 sits above `readyToMerge` |
| 13 | `decision == null`, one `APPROVED` latest review, checks `SUCCESS` | `readyToMerge`, counted | §3.1's `null` clause |
| 14 | Team `@acme/backend` requested; you reviewed after the request; the team request is still pending | Role `involved`, not counted, no notification | §2.2's second clause |
| 15 | `acme/api` renamed to `acme/core` | Same cursors, same tags, no notification, rows show `acme/core` | D-09: identity is the node ID |
| 16 | The app is killed after step 8's write and before delivery | The events are not delivered on the next launch; the rows are marked | §5.6: at most once |
| 17 | Draft pull request with `checksFailing` | Status `checksFailing` with the draft modifier; not counted | §3.2 and §4: draft is a modifier and never counts |
| 18 | `acme/api` excluded, then included again 3 days later with 2 old comments on a watched pull request | 0 notifications for the old comments | §2.3: cursors survive exclusion for 30 days |

Reminders, with `interval` 60 min unless stated, and `t₀` the time `ana` requested your review on
`acme/api#482`:

| # | Given | Expected | Why |
|---|---|---|---|
| 19 | Polls every minute from `t₀` to `t₀ + 3 h 30 min`; you never review | `reviewRequested` at `t₀`; reminders at `t₀ + 1 h`, `+ 2 h`, `+ 3 h` | §5.7: each reminder anchors on the previous one |
| 20 | Mac asleep from `t₀ + 10 min` to `t₀ + 5 h` | 1 reminder at wake, the next at wake `+ 1 h` | §5.7: never a catch-up burst. The naive answer is 4 reminders at wake, or 1 grouped "4 reminders" |
| 21 | You approve at `t₀ + 40 min` | No reminder | The review ends the role, so the pull request is not pending |
| 22 | You reviewed at `t₀ + 40 min`; `ana` re-requests at `t₀ + 2 h` | `reviewRequested` at `t₀ + 2 h`; the reminder at `t₀ + 3 h`, not at `t₀ + 2 h` | The record is replaced with the new `requestedAt`, anchored on the re-request's notification. The naive answer reminds at once, because the first request is more than an hour old |
| 23 | Quiet hours `22:00`–`08:00`; `t₀` = 21:30; Mac awake all night | 0 reminders until 08:00; 1 at the first poll after 08:00; the next at 09:00 | §5.7: the window crosses midnight; a reminder due inside it waits for the end, and only one comes |
| 24 | Fresh install at `t₀ + 3 h` | 0 notifications; the first reminder at install `+ 1 h` | D-19 extended to reminders by the record's seeding |
| 25 | `acme/api#482` muted with scope `reminders`; at `t₀ + 2 h`, `ana` comments in a thread you started | 1 `threadReply`; no reminders | §5.7: scope `reminders` stops reminders only |
| 26 | `acme/api#482` muted with scope `all`; `ana` re-requests | 0 notifications; still listed, still counted | §5.4 rule 3; a re-request does not undo a mute |
| 27 | Pending review requests on 3 pull requests in `acme/api` and 1 in `acme/web`, all due in the same poll | 2 notifications: `3 reviews still waiting for you` for `acme/api`, `Your review is still waiting` for `acme/web` | Coalesced by `(repository, kind)` like events, §7.1 |
| 28 | Interval changed from 60 to 15 min at `t₀ + 50 min` with no reminder yet | 1 reminder at the next poll, then every 15 min | §5.7: the due time is recomputed, and late means one, not three |
| 29 | Quiet hours `22:00`–`08:00` in `America/Sao_Paulo`; the Mac travels to `Europe/Lisbon` | The window is 22:00–08:00 Lisbon time | §5.7: the time zone is the Mac's, passed in, not stored |
| 30 | Screen locked from `t₀ + 50 min` to `t₀ + 2 h 30 min` | Reminders at `t₀ + 1 h` and `t₀ + 2 h`, into Notification Center; none extra at unlock | D-26: presence is not read, and returning sends nothing extra |

Ignore and Focus:

| # | Given | Expected | Why |
|---|---|---|---|
| 31 | `acme/api#482` ignored; `ana` re-requests your review | 0 notifications, 0 reminders; count unchanged; the row is in **Ignored** | §5.8: a re-request does not end an ignore. The naive answer re-surfaces it |
| 32 | `acme/api#482` ignored for 2 days with 3 new comments; then `Stop Ignoring` | 0 notifications; the row returns to *Review requested* and counts again | §5.8: the cursor advanced while ignored |
| 33 | A Focus with Docket's filter (hold on) from 14:00 to 15:00; meanwhile 2 requests in `acme/api`, `bruno` approves your `acme/web#88`, and `acme/api#482` crosses its reminder interval | At 15:00, 2 notifications: `While you were in Focus` for `acme/api` (`2 reviews requested`) and for `acme/web` (`@bruno approved #88`); no reminder at 15:00; the reminder of #482 one interval after its last record | §7.5: reminders are not queued, and the digest groups kinds per repository |
| 34 | Hold on; Docket killed at 14:30 and relaunched at 14:40 | Still holding; at 15:00 the digest includes events from before and after the relaunch | `held` and the hold's start are in `state.json` |
| 35 | Hold started at 09:00 and macOS never calls the filter again | The hold ends at 21:00 and the digest is delivered | §7.5's 12-hour safety |
| 36 | Hold on; `acme/api#482` gets 2 held comments, then you ignore it before the Focus ends | The digest leaves out #482's comments | §7.5: held events of a pull request that is muted, ignored or gone are dropped |

The P1 kinds:

| # | Given | Expected | Why |
|---|---|---|---|
| 37 | Your `acme/api#470` turns `FAILURE` on head `a1`; you push `a2`, which also fails | 2 `checksFailed`, one per head | §5.3: once per head commit. The naive answer is 1, because the status never left `checksFailing` |
| 38 | Your `acme/api#470` is already `FAILURE` when Docket first sees it; the next poll is unchanged | 0 notifications | The head is recorded on entry |
| 39 | `bruno` merges your `acme/api#470`; separately you merge your `acme/api#471` | 1 `closedByOther`, `@bruno merged your pull request` | §5.4 rule 1 applied to the closer |
| 40 | On `carla`'s `acme/web#88`, `carla` writes `@you can you check the migration?` in the conversation | 1 `mention` | A conversation comment on someone else's pull request fires only as a mention |
| 41 | On your `acme/api#470`, `dave` comments `ping @you` | 1 `mention`, no `commentAdded` | The mention replaces the comment for the same item |
| 42 | `dave` writes `@acme/backend please look` or `@youngster` | 0 mentions | A team, or a longer login, is not you |

## 9. What can go wrong

| Failure | What Docket does |
|---|---|
| **Search index lag.** A new review request takes up to about a minute to appear in `requested` | It is notified one poll late. Pull requests already watched are read by ID and are unaffected. NFR-04 allows for one lagged poll; it is not a documented GitHub bound, and the logs record discovery time against the event's `createdAt` |
| `gh` missing, signed out, or token without `repo` / `read:org` | No poll; the popover shows the matching screen (FR-12, `05-design.md`) |
| `401` | Re-read the token once (FR-14), then the signed-out screen |
| SAML enforcement on one organization | GraphQL returns `FORBIDDEN` errors for those nodes, and listing requests carry `X-GitHub-SSO: partial-results; organizations=<ids>`. That organization's pull requests are left out, a banner names it and gives the fix (`09-provider-setup.md`), and every other organization keeps working (FR-13) |
| A node returns `NOT_FOUND` | Access was lost or the pull request was deleted: it leaves the watch set (§2.4) |
| Partial GraphQL errors on some nodes | Those nodes keep their previous snapshot for this poll; the rest proceeds |
| More than 30 new reviews, or 20 new comments in one thread, between polls | The oldest are outside the `last:` window and never notify. Unlikely at a 60 s interval; accepted rather than paginated |
| More than 150 results in one search | "+N not shown"; the overflow is not watched (§2.1) |
| The Mac's clock is wrong | Ages use the server-time offset (§3.4); event ordering uses server timestamps only |
| `state.json` unreadable | Moved aside as `state.corrupt-<timestamp>.json`, and the next poll is a fresh baseline: no notifications, nothing lost from `config.json` (D-10) |
| Notification permission denied | The list and count work; settings shows the permission state and a button to System Settings |
| A Focus filter's `perform` is never called (reported on macOS 26.5) | No hold ever starts: Focus behaves as without the filter (D-22). Settings says how to check, `05-design.md` §9 |
| A hold starts and the end is never called | The 12-hour safety of §7.5, and `Deliver Now` in the popover |
