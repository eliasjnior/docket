# Popover redesign, triage and AI actions — design

Status: agreed with the maintainer in conversation on 2026-10-21, after three rounds of mockups.
This document is the input to the implementation plan. Where it changes behaviour already written in
`docs/01`–`05`, the PR that builds it updates those documents (CLAUDE.md: the plan is the source of
truth). Choices marked **(builder's call)** were made by the agent, not agreed with the maintainer,
and may be changed during planning if a better option appears.

## 1. Why

The maintainer uses Docket with a team that has **62 pull requests waiting for review** at once. The
current popover gives each row the same weight. Four things go wrong:

- automation pull requests (Dependabot, Renovate…) and abandoned ones bury the few that need a human;
- a running check is hard to tell apart from the other statuses;
- the repository group header is too faint to work as a group;
- there is no way to tell which pull requests you have already opened.

The maintainer also found the UI plain: weak colour, a faint active tab, a cramped header, a left
margin wider than the right one, and a redundant `Updating…` label.

Success: with 60+ pull requests listed, the maintainer can see within a couple of seconds what is new,
who is waiting on them (human, not bot), and what state each pull request is in, and can narrow the
list to a mix of organizations, labels and statuses.

**Anti-goals.** These would count as a failure even if every feature works:

- a popover that feels busier than before;
- three stacked rows of navigation that push the list below the fold;
- a notification storm when a team requests many reviews at once;
- any write to GitHub;
- the token reaching a child process.

## 2. Visual direction

The reference is the round-2.4 mockup (`direction-v6.html`). It is not committed. The described
result is what counts.

| Area | Decision |
|---|---|
| Header | App logo (the app icon, small), then `Docket`, with refresh and settings on the right. The `Updating…` and `Updated N min ago` text is removed: the refresh symbol spinning is the only progress signal. The stale-data warning of FR-44 moves to the banner area (**builder's call**) |
| Tabs | A segmented control filling the width: `Review requested`, `Mine`, `Involved`, plus `Ignored` while something is ignored. The control is taller than today's (about 34 pt). Each label is centred in its segment. Each segment's count sits in a circle pinned to the segment's trailing edge, vertically centred, with the number centred in the circle. The selected segment is filled with the accent colour, and its count circle is white with accent-coloured digits. Unselected circles are a neutral grey |
| Sub-tabs | Under the tabs, a row of pill-shaped toggles: `Humans`, `Bots`, `Stale` (§3). They appear only in *Review requested*. Each uses the same count circle as the tabs. Text is centred horizontally and vertically, with enough vertical padding that it does not touch the pill's border |
| Actions menu | A `•••` button at the trailing end of the sub-tab row. In tabs without sub-tabs it sits at the trailing end of the filter row. It opens a menu that today holds one item: `Mark All as Seen` (§4) |
| Filter row | Chips for the active filters (`Org: acme, globex ✕`) and a `+ Filter` chip. Text is centred, with room above and below; the spacing under the row must not look cramped |
| Repository group header | A full-width band in a slightly raised background: a small rounded square in a colour derived from the repository name, the owner in secondary text, `/`, the name in semibold, and the count on the right. The header is **pinned while scrolling** and replaced by the next group's header, like Contacts |
| Row | A 3 pt status rail on the leading edge, in the status colour. Line 1 is the title. Line 2, left to right: `#number`, a filled status pill, author, labels, then the age on the right. The leading and trailing margins are equal: the marked-dot gutter goes, because seen/unseen (§4) does that job. Unseen rows have an accent-tinted background and a semibold title. Seen rows have the normal background and the title in the secondary colour |
| Status pill | A filled capsule: the token at about 15% opacity with the text in the token colour. `Checks running` shows an animated spinner in `status.attention` (amber), so it no longer looks like `Waiting for review` (blue). `Checks failing` and `Conflict` are red, `Ready` is green, `Changes requested` is orange |
| Colour | More colour overall, always from the token set of `05-design.md` §10.2. White text on any filled colour must meet WCAG AA, so the accent is dark enough for that |

The repository group, the waited time and the other information of `05-design.md` §6.1 stay. Only
their rendering changes.

## 3. Review requested: Humans, Bots, Stale

*Review requested* gains three sub-tabs. Together they partition the tab: every row is in exactly one
of them.

- **Stale.** The pull request has had no human activity for `staleAfterDays`, configurable, default 7
  (**builder's call**). Human activity is a commit, a force push, or a comment or review by anyone who
  is not a bot. Stale wins over Humans and Bots.
- **Bots.** The author is a bot: GraphQL `__typename == "Bot"`, a login ending in `[bot]`, or a login
  in a user-editable list in Settings, for accounts like a `renovate` user that is not typed as a bot
  (**builder's call**, empty by default).
- **Humans.** Everything else. This is the default sub-tab.

The selected sub-tab is kept for the life of the process, like the tab. The tab's own count stays the
total of the three.

**What Bots and Stale do outside the popover** (maintainer's decision). Two settings control it:

| Setting | Default | When off |
|---|---|---|
| Count and notify bot pull requests | **on** | Pull requests in *Bots* leave the menu bar count of `02` §4 and get no `reviewRequested` notification and no reminder |
| Count and notify stale pull requests | **off** | Pull requests in *Stale* leave the menu bar count of `02` §4 and get no `reviewRequested` notification and no reminder |

The defaults are the maintainer's decision: bots count and stale pull requests do not.

- Other event kinds on those pull requests keep their own rules: a review submitted on your pull
  request still notifies.
- A stale pull request that gets human activity leaves *Stale*, so it counts and notifies again from
  that poll on.
- These rules are pure functions in `DocketActivity`. They change `Count`, `Reminders` and the compose
  step. Each change gets worked examples in `02` §8.

**One bot test** is shared by the sub-tabs, seen/unseen (§4) and the notification rules of `02` §5.4
(**builder's call**). An actor is a bot when:

- its `__typename` is `Bot`;
- its login ends in `[bot]`; or
- its login is in **Extra bot logins**.

An extra login is a bot everywhere, including §5.4's suppression of its events. The existing
`botAllowlist` (D-16, FR-57) keeps its meaning: an allowlisted bot may still notify. It is still a
bot for the sub-tabs and for seen/unseen.

**Human activity** is defined the same way for Stale and for seen/unseen (§4):

- a commit authored by a non-bot;
- a force push by a non-bot;
- a comment, review or thread reply by a non-bot;
- a review request or re-request made by a non-bot (**builder's call**: so a fresh request on an old
  pull request is not hidden in Stale).

A bot's rebase or push, such as Dependabot's or an autoformat bot's, is not human activity. The
summary query must therefore read the head commit's author and the last force push's actor. It reads
only the head OID today. The builder records the cost change in `02` §6.2.

## 4. Seen and unseen

Each pull request in the list is **seen** or **unseen**, from the viewer's point of view. The state is
local to this Mac.

- Opening a pull request from Docket marks it seen. That covers a row click, `Return`, `Open in
  Browser`, and a notification click that opens one pull request. Opening it outside Docket is not
  detected.
- `Mark All as Seen` in the actions menu marks every row of the visible list as seen. The visible list
  is the current tab, sub-tab and filters.
- A seen pull request becomes unseen again when, after it was seen, there is **human activity** as
  defined in §3, by someone other than the viewer.
- Bot activity never makes a pull request unseen. That covers CI comments, label bots, and a bot's
  commits or rebases.
- When the version that introduces seen state first runs, everything already listed starts as seen.
  This is the same idea as the event baseline of `02` §5.2, so an upgrade does not light up 62 rows
  (**builder's call**). A pull request that enters the list afterwards starts unseen.

Seen/unseen replaces the marked dot of FR-46 in the row. The count per tab keeps working from the same
data: a tab shows its unseen count if the builder keeps that signal (**builder's call**: replace the
tab's marked `●` with nothing, since the count circle is there; keep it only if a dot still helps).

Persistence: a per-pull-request record of the head OID and the time it was seen. This is an on-disk
format change, which `docs/04-data.md` describes and versions.

## 5. GitHub labels instead of local tags

Local tags go away completely: the tag editor, `Edit Tags…`, the tag filter, the `T` shortcut and
`tags.json`. Each row shows the pull request's **GitHub labels**, in their GitHub colour, rendered as
small outlined pills. The text colour is adjusted for contrast on the popover material. Labels are
read-only. Docket still never writes to GitHub (non-negotiable 5).

Existing `tags.json` files are left on disk and ignored. A future version may delete them. The
maintainer accepts losing the tags already created. This reverses FR-80 to FR-83 and D-xx entries
about tags. The PR that removes them updates `01-product.md` and the register.

## 6. Filters

Four filter dimensions: **organization**, **repository**, **label** and **status**. Each allows
several values.

- Within a dimension, values combine with OR: org acme *or* globex.
- Across dimensions, values combine with AND: (acme or globex) *and* label backend.
- The `+ Filter` chip opens a menu per dimension that lists the values present in the current tab,
  with counts, and toggles them.
- Each active dimension is one chip with an `✕` that clears it.
- `Escape` clears the most recently added dimension.
- The repository filter set by a grouped notification click (FR-59) becomes a one-value repository
  filter.
- Filters apply to every tab and are kept for the life of the process (**builder's call**).

## 7. Mine: Ready, Blocked, Draft

*Mine* is organized into three groups, in this order:

1. **Ready.** Not a draft, and not blocked.
2. **Blocked.** Not a draft, and one of: `conflict`, `checksFailing`, `changesRequested`. The row
   says why, for example `Conflict with main` or `Changes requested by @ana`.
3. **Draft.** Every draft, whatever its status. Collapsed by default in the list layout.

Inside each group the order is today's: status precedence of `02` §3.2, then newest first.

Two layouts, chosen in Settings → General. The default is **List**:

- **List:** the groups stacked as sections in the normal 380 pt popover, each with a header and a
  count.
- **Board:** three columns side by side, like a Jira board. Each card shows the title, the reference,
  and the blocking reason. While *Mine* is selected the popover widens to about 620 pt. It goes back to
  the normal width on the other tabs.

There is no drag and drop. A pull request's column follows from its state.

## 8. Review-request notifications: one per pull request

A detected review request produces **its own notification**: "@ana is waiting for your review", with
`acme/api #482` and the title. Review requests are no longer coalesced by repository.

- The other event kinds keep the coalescing of `02` §7.1.
- The cap of five per poll (FR-55) still holds. Review requests have the highest priority. If more than
  five arrive in one poll, the first four are delivered individually and the fifth summarizes the rest,
  as today.
- `threadIdentifier` stays per repository, so Notification Center still stacks them.

This changes `02` §7.1, the copy in `05` §8, and needs a worked example in `02` §8.

## 9. Context menu additions

Three items join the row's context menu. They sit in a new group after `Copy Reference`:

- `Open in Jira`
- `Review with AI`
- `Summarize with AI`

### 9.1 Open in Jira

Settings has a **Jira base URL**, such as `https://acme.atlassian.net`. The issue is found in this
order; the first match wins:

1. A link in the pull request **body** whose host matches the base URL's host, used as is.
2. An issue key (`[A-Z][A-Z0-9]+-\d+`) in the **title**.
3. An issue key in the **head branch name**.

A key opens `<base>/browse/<KEY>`. With no base URL set, or no match, the item is shown disabled.
This needs the pull request's `body` and `headRefName` in the summary or detail query. The builder
picks the cheaper place and records the cost change in `02` §6.2.

### 9.2 Review with AI and Summarize with AI

Both run a **user-editable command** in the **user's chosen terminal app**.

Settings has a new **AI** tab (**builder's call** on the tab name):

- **Terminal app:** a picker listing Terminal, iTerm and other installed terminals Docket recognises,
  plus `Choose…`. The maintainer uses iTerm. The default is the app registered for `.command` files.
- **Review command** and **Summarize command:** multi-line text fields, each with a default and a
  `Reset to Default` button. Placeholders: `{url}`, `{repo}`, `{number}`, `{title}`, `{branch}`. The
  default review command is a `claude` invocation asking it to review `{url}`. It reads the diff and
  comments with `gh` and reports problems. The summarize default asks for a short summary of what the
  pull request does and why. The builder writes the exact default prompts.
- **Local clones:** a list mapping a repository to a folder on disk.
  - When the pull request's repository has a mapping, the command runs in that folder.
  - Otherwise it runs in a fresh temporary folder.
  - The maintainer agreed to this.

What happens on click:

1. Docket writes a temporary `.command` script with permissions `0700`. The script `cd`s into the
   folder and runs the command with the placeholders substituted.
2. Docket asks the chosen app to open the script, through `NSWorkspace` with the app's URL.
3. The script deletes itself when it starts.

**Untrusted values never become shell syntax** (**builder's call** on the mechanism). Pull request
titles and branch names are written by other people. Pasting them into the command, even inside
quotes, would let a title like `$(rm -rf ~)` run on the maintainer's Mac, because double quotes still
expand `$(…)`.

So the script does not substitute values into the text:

1. It exports each value as an environment variable, assigned with single-quote escaping:
   `DOCKET_URL`, `DOCKET_REPO`, `DOCKET_NUMBER`, `DOCKET_TITLE` and `DOCKET_BRANCH`.
2. Before writing the script, each `{x}` in the template is rewritten to `"$DOCKET_X"`.

A value is then always one expanded word, never parsed as code, whether or not the user wrote quotes
around the placeholder. A template that puts a placeholder inside single quotes would not expand. In
that case Settings shows a warning under the field. A test runs hostile titles through the generated
script: `$(…)`, backticks, `'`, `"`, `;` and newlines.

The token is never in the script, its environment or its arguments. `claude` and `gh` use their own
login. Docket does not talk to any AI service: the user's command does, in the user's terminal. This
needs a new decision in the register (**D-28**): *Docket may launch a user-configured command in the
user's terminal on an explicit user action*. The decision records:

- why the alternative was rejected: Docket calling an AI API itself would break non-negotiable 7;
- what to revisit: if a shipped default ever needs a network service other than GitHub.

Whether a given terminal actually runs a `.command` opened this way must be checked by hand for
Terminal and iTerm. Others are best effort. If one does not, the builder may fall back to
AppleScript for that app, and note it.

## 10. Settings summary

New or changed settings. All live in `config.json`, which is versioned per `04-data.md`.

| Setting | Tab | Default |
|---|---|---|
| Stale after N days | Notifications or General (**builder's call**) | 7 |
| Extra bot logins | same | empty |
| Count and notify bot pull requests | Notifications | on |
| Count and notify stale pull requests | Notifications | off |
| Mine layout: List / Board | General | List |
| Jira base URL | General or AI | empty |
| Terminal app | AI | `.command` handler |
| Review command, Summarize command | AI | built-in defaults |
| Local clones | AI | empty |

The tag-related settings go.

## 11. Constraints that bind the builder

- Every non-negotiable in `CLAUDE.md`:
  - rules in `DocketActivity` stay pure, with time injected;
  - views see stores only;
  - copy lives in `Localizable.xcstrings`;
  - fixtures are synthetic.
- The bot test, the stale test, the seen/unseen rules, the Mine grouping, the Jira key extraction and
  the shell quoting are pure functions with tests in `DocketActivity` or `DocketCore`. The `.command`
  writer and the launcher live in an adapter behind a port.
- The gate's coverage floors (90% `DocketActivity`, 75% `DocketKit`) hold.
- Several PRs will change a public type in `DocketCore`/`DocketActivity` or an on-disk format. That
  triggers `needs-human` under the auto-merge rules. See §13.
- Each PR stays under ~400 changed lines. The work is a sequence of PRs, not one.
- Views are checked with `Docket --snapshot`. Snapshots for the new states are added: sub-tabs,
  filters with several values, unseen rows, the Mine list and board, and the AI settings.

## 12. Not in this design

- The market survey requested earlier (item 10 of the request) was not done. The maintainer judged
  the direction good enough to build. Further ideas from a survey would be a separate round.
- Drag and drop in the board, manual ordering, and writing anything back to GitHub or Jira.
- Detecting that a pull request was opened outside Docket.

## 13. Delivery

The maintainer's decision: **nothing in this work is merged until the maintainer has installed and
tested it locally.**

1. The work is still a sequence of small PRs, each through the pre-push gate. PRs that hit a
   `needs-human` condition get the label and a comment saying why, as usual.
2. The PRs are stacked. Each one is opened against the branch of the PR before it, or they are
   collected on one integration branch (the builder's call). Every PR is left open. None is merged.
3. When the sequence is complete, the builder runs `make -C apps/macos install` from the top of the
   stack and hands the maintainer the list of what to test.
4. After the maintainer's OK, the stack is merged into `main` in order. A release follows.
