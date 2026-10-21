# 09 — Provider setup

Everything outside the code that Docket depends on, set up in order for the first time: the GitHub
CLI and its scopes, organization approval and SAML, the repository, the two signing keys, the first
run, and every secret and configuration value with what breaks without it.

Docket has one provider, GitHub, reached through two doors: the `gh` binary on your Mac, which
holds the credential (D-02), and the `eliasjnior/docket` repository, which holds the release
secrets (D-04, D-14, D-15). There is no server, no cloud account and no environment variable in the
app (`03-architecture.md` §8). Sections 1–2 are what anyone running Docket needs; sections 3–5 are
what the person cutting releases needs, once.

GitHub UI labels below are the ones in use when this was written. Where a label is not certain, the
text says so instead of guessing; the command-line path next to it is the one to trust.

## 1. GitHub CLI

### 1.1 Install

```sh
brew install gh
gh --version
```

Homebrew puts `gh` at `/opt/homebrew/bin/gh` on Apple silicon and `/usr/local/bin/gh` on Intel —
the two paths Docket tries first (FR-11). Installed anywhere else (MacPorts, a Nix profile, a
manual download), Docket falls back to `command -v gh` in your login shell, and if that fails too
you set the path in **Settings → Account**, which writes `ghPath` in `config.json`
(`04-data.md` §2.1).

### 1.2 Sign in

```sh
gh auth login
```

Answer the prompts in this order:

| Prompt | Answer | Why |
|---|---|---|
| Where do you use GitHub? | `GitHub.com` | Docket reads only `github.com`; GitHub Enterprise Server is out of scope (PROJECT.md §4) |
| Preferred protocol for Git operations | `HTTPS` or `SSH` — either | Docket never runs `git`. The answer only decides how `gh` configures Git for your own clones |
| Authenticate Git with your GitHub credentials? (HTTPS only) | Your choice | Same reason |
| Upload your SSH public key? (SSH only) | Your choice | Same reason |
| How would you like to authenticate GitHub CLI? | `Login with a web browser` | It produces an OAuth token issued to the GitHub CLI app — the token D-02 relies on. `Paste an authentication token` stores a personal access token instead, which works for Docket but is not what this document assumes (§2.3) |

`gh` prints a one-time code, opens `https://github.com/login/device`, and you paste the code and
approve. On that approval page GitHub lists your organizations; one with SAML single sign-on shows
a button to authorize the token for it — use it now, it saves §2.2 later.

### 1.3 Scopes

Docket needs exactly two OAuth scopes:

| Scope | What Docket does with it | Without it |
|---|---|---|
| `repo` | Reads pull requests, reviews, comments and checks of private repositories; downloads releases of the private `eliasjnior/docket` for the updater (D-14) | Private repositories are invisible; updates fail with `404` (§9) |
| `read:org` | Reads organization membership and your team slugs, so review requests made to a team count as yours (`02-activity-detection.md` §2.2) | Team review requests are missed; the popover shows the missing-scope screen (FR-12) |

`gh auth login` asks for `repo`, `read:org` and `gist` by default, so a browser login already has
both. Docket never writes, so it would be satisfied with less; GitHub's OAuth scopes have no
read-only form of `repo`, and that is the cost of using a token Docket did not create.

Check:

```sh
gh auth status
```

The line to read is `Token scopes:` — it must contain `'repo'` and `'read:org'`. If either is
missing (a token created long ago, or one pasted in), add it without signing out:

```sh
gh auth refresh -h github.com -s read:org
# or, for both:
gh auth refresh -h github.com -s repo,read:org
```

`refresh` opens the same browser flow as §1.2 and keeps the scopes the token already had. Docket
reads scopes from every response's `X-OAuth-Scopes` header (`03-architecture.md` §6 step 3), so the
missing-scope screen clears on the next poll; press `⌘R` to make that now.

### 1.4 More than one account

`gh` holds several accounts per host. Run `gh auth login` again to add one, then:

```sh
gh auth status                      # lists every account; one is marked active
gh auth switch -h github.com -u <login>
```

Docket always reads the **active** account's token (`gh auth token --hostname github.com`). After a
switch:

- **Restart Docket.** `03-architecture.md` §6 step 4 picks a switch up on the next `401` or the next
  launch, but the previous account's token is still valid after a switch, so no `401` arrives and in
  practice only the relaunch applies it.
- **The first poll is a fresh baseline.** `state.json` records `viewerLogin`; a different login
  discards cursors and the delivered ledger and starts over without notifications (`04-data.md`
  §2.2, D-19). Selection and tags in `config.json` are kept — tags are keyed by node ID and simply
  do not match pull requests the new account cannot see.
- **Updates follow the account.** The updater uses the same token, so the active account must be
  able to read `eliasjnior/docket` (§9).

## 2. Organizations

Docket reads an organization's repositories with GitHub CLI's token, so it sees exactly what `gh`
sees. Two organization settings decide that: OAuth app access restrictions and SAML single sign-on.
Check with:

```sh
gh api orgs/<org> --jq .login        # works at all?
gh pr list --repo <org>/<some-private-repo> --limit 1
```

If both answer, the organization is fine and this section does not apply.

### 2.1 OAuth app access restrictions

An organization with OAuth app access restrictions (GitHub's default for organizations created
recently) lets an OAuth app read its private data only after an owner approves that app. GitHub CLI
is an OAuth app for this purpose. Most organizations that use `gh` at all have already approved it;
the symptom of one that has not is `gh` itself failing on that organization's private repositories,
with an error naming OAuth app access restrictions.

To ask for approval, as a member:

1. Go to **github.com → Settings → Applications → Authorized OAuth Apps**.
2. Open **GitHub CLI**.
3. Under the organization access section, find the organization and choose **Request** (the button
   label may read *Request access*; the section and the button are what to look for).
4. An organization owner receives the request and approves it in the organization's settings, under
   the third-party or OAuth application access policy. The exact menu name has changed over time and
   is not quoted here; GitHub's documentation page "Approving OAuth apps for your organization" is
   the reference to send the owner.

The organization's members are notified by e-mail when the request is decided. Nothing changes in
Docket: the next poll includes the organization.

**The uncomfortable part of D-02, again:** Docket works because the organization allows GitHub CLI.
An organization that restricts OAuth apps and refuses GitHub CLI blocks Docket exactly as it blocks
`gh`, and there is nothing in Docket to configure around it. The fallback named in D-02's revisit
condition is a classic personal access token held in the Keychain, behind the same `TokenProvider`
port. **It is not built in v1.** And it may not help: organizations can also restrict access by
classic personal access tokens, so check that policy before building it.

### 2.2 SAML single sign-on

An organization that enforces SAML SSO accepts a token only after it has been authorized for that
organization, and only while you have a valid SSO session with its identity provider. The `gh`
token is authorized separately from your browser session.

**Symptom in Docket:** a banner per organization (FR-13). GitHub answers listing requests with
`X-GitHub-SSO: partial-results; organizations=<ids>` and leaves those organizations out; a request
for one resource answers `X-GitHub-SSO: required; url=<url>` (`03-architecture.md` §6). Every other
organization keeps working.

**Fix, in order of preference:**

1. **The banner's button.** It opens the `url` from `X-GitHub-SSO: required` when GitHub returned
   one. GitHub sends you through the identity provider's sign-in and then asks you to authorize the
   token for the organization.
2. **Re-authorize through `gh`.** Sign in to the organization's SSO in the browser first —
   `https://github.com/orgs/<org>/sso` starts it — then run:

   ```sh
   gh auth refresh -h github.com -s repo,read:org
   ```

   The browser approval page lists the organization with an authorize button next to it, as in
   §1.2. GitHub authorizes an OAuth app's token for an SSO organization only when an SSO session is
   active at approval time, which is why the order matters.
3. **From settings.** **github.com → Settings → Applications → Authorized OAuth Apps → GitHub CLI**
   shows organization access; for an SSO organization it offers to grant or authorize. This page's
   exact wording for SSO organizations is not certain; options 1 and 2 are the reliable ones.

Press `⌘R` afterwards; the banner clears when the next poll returns the organization's results.

SSO sessions expire on the identity provider's schedule, not GitHub's. An authorized token keeps
working for API requests between sessions in the usual configuration, but an organization can
require a fresh session; a banner reappearing weeks later is that, and the fix is the same.

## 3. The repository

Needed once, by whoever owns the repository.

### 3.1 Create

```sh
gh repo create eliasjnior/docket --private \
  --description "macOS menu bar app for the pull requests waiting on you"
```

Private is D-04's decision, and it has two consequences handled below: the Swift checks do not run
on Actions (D-12) and `main` may not be protectable (D-13).

### 3.2 Settings

The same settings Lookout's `scripts/configure-repo.sh` applies, without its ruleset:

```sh
repo=eliasjnior/docket

gh api --method PATCH "repos/$repo" --silent \
  -F allow_squash_merge=true \
  -F allow_merge_commit=false \
  -F allow_rebase_merge=false \
  -F delete_branch_on_merge=true \
  -F allow_update_branch=true \
  -f squash_merge_commit_title=PR_TITLE \
  -f squash_merge_commit_message=PR_BODY \
  -F has_wiki=false \
  -F has_projects=false

gh api --method PUT "repos/$repo/actions/permissions/workflow" --silent \
  -f default_workflow_permissions=read \
  -F can_approve_pull_request_reviews=true
```

| Setting | Value | Why |
|---|---|---|
| Merge methods | Squash only, title from the pull request, body from its description | One commit per pull request on `main`, whose message is the Conventional Commit title release-please reads (`06-engineering-practices.md`) |
| Delete branch on merge | On | Merged branches do not accumulate |
| Default workflow permissions | Read | Each workflow declares what it needs; `Release` declares `contents`, `pull-requests` and `actions: write` |
| Allow GitHub Actions to create and approve pull requests | On | Without it release-please cannot open its release pull request and the `Release` workflow fails on its first run |

In the web UI the last two are **Settings → Actions → General → Workflow permissions**: *Read
repository contents and packages permissions* and the checkbox *Allow GitHub Actions to create and
approve pull requests*. Also on that page, **Actions permissions** must allow the actions the
workflows use (`googleapis/release-please-action`, `maxim-lobanov/setup-xcode` and GitHub's own);
the default *Allow all actions and reusable workflows* does.

### 3.3 Labels

```sh
gh label create needs-human --repo eliasjnior/docket --color B60205 \
  --description "Blocked on a decision or an action only the owner can take"
gh label create goal:m0 --repo eliasjnior/docket --color 0E8A16 \
  --description "Milestone M0"
# one goal:mN per milestone in 07-roadmap.md
```

`goal:m0`… tie issues and pull requests to the milestones of `07-roadmap.md`; `needs-human` marks
anything an agent cannot finish alone, such as every step in §2 and §4.

### 3.4 Protecting `main` — closing D-13

D-13 is open and this is the check that closes it. Rulesets and branch protection on a private
repository need GitHub Pro for a personal account; GitHub Free does not offer them.

```sh
gh api user --jq .plan.name     # "free" or "pro"
```

- **`free`:** nothing to configure on GitHub. Lefthook's `pre-push` refusing `refs/heads/main` is
  the whole protection, and it holds only on machines where the hooks are installed. Close D-13 as
  "local enforcement only" with **Revisit when** the plan changes or the repository goes public.
- **`pro`:** add the ruleset from Lookout's `scripts/configure-repo.sh` — no deletion, no force
  push, linear history, pull request required with squash as the only merge method, review threads
  resolved, zero required approvals (there is one person). Its required status checks are the
  Ubuntu job's checks only — the pull request title check and gitleaks, under the names
  `06-engineering-practices.md` gives them — never a macOS check, because none runs on pull
  requests (D-12). With required checks, the release pull request's check runs, started by
  `GITHUB_TOKEN`, wait for approval; the `Release` workflow copies Lookout's approval step for
  that, and when it warns, approve by hand:
  `gh api -X POST repos/eliasjnior/docket/actions/runs/<id>/approve`.

## 4. Code signing

D-15: releases and `make install` are signed with one self-signed certificate,
`Docket Self-Signed Code Signing`. macOS does not trust it and does not need to. What matters is
that the designated requirement — `identifier "com.eliasjnior.docket" and certificate leaf = H"…"` —
is identical across builds, because notification permission is bound to it and the updater accepts
only an app that satisfies the running app's requirement (D-14).

### 4.1 Create the certificate

Either way produces the same thing: a code-signing certificate with its private key.

**Keychain Access.** Open **Keychain Access → Certificate Assistant → Create a Certificate…**:

| Field | Value |
|---|---|
| Name | `Docket Self-Signed Code Signing` — exactly; `codesign-app.sh` signs by this name |
| Identity Type | Self Signed Root |
| Certificate Type | Code Signing |
| Let me override defaults | Optional; tick it only to set the validity period, which defaults to one year. Choose 10 years (3650 days): expiry is a rotation (§4.4) |

The certificate and its private key land in the login keychain, under **My Certificates**.

**openssl.** Reproducible, and the validity is explicit:

```sh
mkdir -p ~/docket-signing && cd ~/docket-signing
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout docket-signing.key -out docket-signing.crt \
  -subj "/CN=Docket Self-Signed Code Signing" \
  -addext "basicConstraints=critical,CA:false" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning"
```

`extendedKeyUsage=codeSigning` is the one extension that matters: without it `codesign` refuses the
identity.

### 4.2 Export the PKCS#12

From Keychain Access: in **My Certificates**, right-click the certificate → **Export…**, format
**Personal Information Exchange (.p12)**, and set a password. From openssl:

```sh
openssl pkcs12 -export -legacy \
  -inkey docket-signing.key -in docket-signing.crt \
  -name "Docket Self-Signed Code Signing" \
  -out docket-signing.p12
```

`-legacy` is for Homebrew's OpenSSL 3, whose default encryption `security import` may reject;
macOS's own `/usr/bin/openssl` is LibreSSL, which does not know the flag and does not need it. Use
a long random password (`openssl rand -base64 24`) and keep it with the `.p12` in your password
manager — the `.p12` and its password are the only copy of the identity outside the secrets.

### 4.3 Store it as secrets, import it locally

```sh
base64 -i docket-signing.p12 | gh secret set SIGNING_CERTIFICATE_P12 --repo eliasjnior/docket
gh secret set SIGNING_CERTIFICATE_PASSWORD --repo eliasjnior/docket   # prompts for the value
```

The `Release` workflow's macOS job decodes the first into a throwaway keychain, unlocks it with the
second, signs with `apps/macos/scripts/codesign-app.sh` and deletes the keychain
(`import-signing-identity.sh`, copied from Lookout). That job also proves the certificate does not
need to be trusted: the throwaway keychain holds no trust settings.

For `make install`, the identity must be in your login keychain. The Keychain Access route already
put it there; after the openssl route:

```sh
security import docket-signing.p12 -k ~/Library/Keychains/login.keychain-db -T /usr/bin/codesign
security find-identity -p codesigning     # lists "Docket Self-Signed Code Signing"
```

Then delete the loose `.key` and `.p12` files from disk.

### 4.4 Rotation

Rotate when the certificate expires or its private key may have leaked. Create a new one (§4.1),
replace both secrets and the local identity (§4.2–4.3), and delete the old identity from the login
keychain.

**What it costs.** The new certificate's leaf hash changes the designated requirement, so to macOS
the next build is a different app:

- Notification permission is asked again, once.
- Anything bound to the old requirement in the Keychain asks again, once. Docket stores nothing in
  the Keychain itself (`04-data.md` §6) and reads the token through `gh`, whose own Keychain item is
  bound to `gh`, so in practice this is notification permission only.
- **The updater refuses the rotated build.** It checks the new app against the *running* app's
  designated requirement (D-14), which names the old leaf. The first release after a rotation must
  be installed by hand — `gh release download` (§6.1) or `make install` — and updates resume from
  there (D-20). Lookout's release document does not mention this; it applies there too.

## 5. Update signing key

D-14: each release archive carries an Ed25519 signature that the app checks against
`DocketUpdatePublicKey` before installing. The private half exists only in the `UPDATE_SIGNING_KEY`
repository secret.

### 5.1 Generate

```sh
cd apps/macos
swift scripts/generate-update-key.swift   # line 1: private key, line 2: public key (both base64)
```

- Line 1: `gh secret set UPDATE_SIGNING_KEY --repo eliasjnior/docket`, paste it at the prompt. Do
  not save it anywhere else. A lost key is a rotation; a leaked one is half of what it takes to
  ship you a hostile update, and the code-signature check of §4 is the other half.
- Line 2: put it in `apps/macos/project.yml` as the `DocketUpdatePublicKey` Info.plist value, and
  commit it. It is public by definition.

### 5.2 Rotation

The installed app trusts only the key it was built with, so the new public key has to arrive in a
release signed with the old private key:

1. Generate a new pair (§5.1). Keep line 1 aside; do not update the secret yet.
2. Put the new line 2 in `project.yml`, merge, and release. This release is still signed with the
   old `UPDATE_SIGNING_KEY` and ships the new public key.
3. Wait until your Mac is running that release (**About** shows the version).
4. Replace `UPDATE_SIGNING_KEY` with the new line 1. Every later release is signed with it.

An installation that skips step 3's release and is offered a later one directly fails the signature
check, because the updater offers only the newest version; that installation is updated by hand
once. With one user that is an inconvenience, not a reason for a key list.

## 6. First run

### 6.1 Install

From a release:

```sh
gh release download --repo eliasjnior/docket --pattern 'Docket-*.zip' --dir /tmp/docket
ditto -x -k /tmp/docket/Docket-*.zip /Applications
open /Applications/Docket.app
```

From source: `make install` in `apps/macos`, which builds Release, signs with the identity of §4.3
and replaces `/Applications/Docket.app`.

### 6.2 Gatekeeper

Self-signing (D-15) means Gatekeeper blocks a browser-downloaded archive once. **Docket requires
macOS 15, where Control-click → Open no longer bypasses Gatekeeper.** On macOS 15 an archive
downloaded by a browser opens like this:

1. Double-click `Docket.app`; macOS says it cannot verify the app. Choose **Done** (not *Move to
   Trash*).
2. Open **System Settings → Privacy & Security**, scroll to the security section, and choose **Open
   Anyway** next to the message about Docket. Authenticate.
3. Open Docket again and confirm **Open Anyway**.

This happens once per installation. It does not happen at all when the archive never carried the
quarantine attribute: `gh release download` and `make install` do not set it, which is why §6.1
uses them. If a browser download is already in place, `xattr -dr com.apple.quarantine
/Applications/Docket.app` has the same effect as the three steps.

### 6.3 Prompts, in order

| Prompt | What to answer | If you decline |
|---|---|---|
| Notification permission (macOS) | **Allow** | The list and the count work; nothing notifies. Settings shows the state and a button to **System Settings → Notifications → Docket** (`02-activity-detection.md` §9) |
| Launch at login (Docket, FR-90) | Accept | Docket runs only when opened. Accepting registers it with `SMAppService`; macOS then lists it under login items in **System Settings → General** (the pane is named *Login Items & Extensions* on recent macOS), where it can be turned off |
| Missing `gh`, signed out, missing scope, SAML (FR-12, FR-13) | Run the command the screen names (§1, §2) | No poll until fixed |

### 6.4 What the first poll does

The first successful poll on a fresh install is the **baseline** (D-19): it fetches everything you
watch, sets the count, fills the three lists, records every review, comment and request as already
seen, and sends **no notifications** — not even for review requests that are waiting. Pending
requests are counted and listed; only what happens after the baseline notifies. Quitting and
relaunching later does notify what happened while Docket was closed, coalesced, because the baseline
is persisted in `state.json`.

## 7. Configuration and secrets

The app reads no environment variables (`03-architecture.md` §8). Every value it or its release
depends on is one of these:

| Name | What it is | Where it comes from | Who needs it | What breaks without it | Rotation |
|---|---|---|---|---|---|
| The `gh` token | OAuth token issued to GitHub CLI with `repo`, `read:org` | `gh auth login` (§1.2); held by `gh` in the macOS Keychain | App at runtime, read with `gh auth token` at launch and on `401`, kept in memory only (FR-10, `04-data.md` §6) | Everything: no poll, the signed-out or missing-scope screen; no updates while the repository is private | `gh auth refresh` or `gh auth login`; revoke at **Settings → Applications → Authorized OAuth Apps → GitHub CLI**. Docket picks a new token up on the next `401` or launch |
| `SIGNING_CERTIFICATE_P12` | Base64 PKCS#12 of `Docket Self-Signed Code Signing` | §4.1–4.3 | `Release` workflow | The macOS job fails at **Sign**; no release assets | §4.4 — costs one permission prompt and one manual install |
| `SIGNING_CERTIFICATE_PASSWORD` | Password of that PKCS#12 | Chosen in §4.2 | `Release` workflow | Same as above | With the certificate |
| Signing identity in the login keychain | The same certificate and key, imported locally | §4.3 | Local `make install` | `make install` fails at `codesign`; a Debug build is unaffected (§8) | With the certificate |
| `UPDATE_SIGNING_KEY` | Base64 Ed25519 private key | `generate-update-key.swift` line 1 (§5.1) | `Release` workflow, step **Sign update** | No `.sig` and no `release.json`; the app finds no installable update | §5.2 — two releases |
| `DocketUpdatePublicKey` | Base64 Ed25519 public key, in `project.yml` → `Info.plist` | `generate-update-key.swift` line 2 | App at runtime (updater) | Every update fails signature verification | With `UPDATE_SIGNING_KEY` |
| `GITHUB_TOKEN` | The workflow's built-in token | Provided by Actions | `Release` workflow: release-please, run approval, `gh release upload` | Nothing to set; fails only if §3.2's workflow permissions are wrong | Per run, by GitHub |
| Bundle identifier `com.eliasjnior.docket` | Identity of the app, part of the designated requirement | `project.yml` (D-03) | App, signing, updater | — | Never: changing it loses notification permission and settings (D-03) |
| `ghPath` | Explicit path to `gh` | **Settings → Account**, stored in `config.json` | App at runtime | Only matters when `gh` is outside the paths of §1.1 | — |
| `SIGN_IDENTITY`, `SIGN_KEYCHAIN` | Inputs of `codesign-app.sh`: identity name (defaults to `Docket Self-Signed Code Signing`) and keychain path | Set by the `Makefile` and the `Release` workflow | Signing scripts, not the app | — | — |

Nothing else is a secret. The repository holds no `.env`, and gitleaks runs on staged files and on
pull requests to keep it that way (`04-data.md` §6).

## 8. What is not needed to develop

- **No secret for the check suite.** `swift test` and `scripts/ci.sh` run against recorded,
  synthetic JSON fixtures served through a `URLProtocol` stub, and against a `CommandRunner` that
  scripts `gh`'s output (`03-architecture.md` §7). They need neither network, nor `gh`, nor a
  signed-in account.
- **No signing identity for Debug.** Debug builds are ad-hoc signed (`CODE_SIGN_IDENTITY=-`). They
  have no stable designated requirement, so the updater skips the code-signature check for them, as
  Lookout's does; the Ed25519 check always applies. The cost: notification permission may be asked
  again after a rebuild of a Debug app, because each ad-hoc build is a different requirement.
- **`docket-cli poll` needs only `gh` signed in.** It runs one poll against your real account and
  prints roles, statuses, events and `rateLimit.cost`:

  ```sh
  swift run --package-path apps/macos/Packages/DocketKit docket-cli whoami
  swift run --package-path apps/macos/Packages/DocketKit docket-cli poll
  ```

- **Neither key of §4–5 is needed** to build, test or run Docket locally. Only a release needs them,
  and only on the Actions runner; `make install` needs the identity of §4.3 and nothing else.

## 9. Gaps to know before blaming the configuration

| What you see | What it actually is |
|---|---|
| A review request appears a poll late | GitHub's search index lag on discovery (`02-activity-detection.md` §9). Not a scope or SSO problem; pull requests already watched are read by ID and do not lag |
| One organization's pull requests are missing, with no error anywhere else | SAML partial results: GitHub leaves the organization out and says so only in a header. Docket shows a banner (FR-13); `gh` in your terminal shows nothing at all, because `gh pr list` and `gh search` silently return what they can. Fix with §2.2 |
| `gh auth status` in your shell reports a different account or token than Docket uses | A `GH_TOKEN` or `GITHUB_TOKEN` in your shell environment. `gh` prefers it, but Docket runs `gh auth token` with an environment of only `HOME` and `PATH` (`03-architecture.md` §6 step 2), so it reads the account stored in the Keychain. Run `env -u GH_TOKEN -u GITHUB_TOKEN gh auth status` to see what Docket sees |
| Docket still shows the previous account after `gh auth switch` | §1.4: the old token stays valid, so no `401` arrives; Docket re-reads the token hourly and on wake (`03-architecture.md` §6), or quit and reopen it now |
| "No updates available", while a newer release exists | The updater uses the `gh` token to see releases of the private repository (D-14). The active account must be able to read `eliasjnior/docket`, and the token must have `repo`; check with `gh release list --repo eliasjnior/docket`. GitHub answers `404`, not `403`, when it cannot, so this looks like "no release" rather than an error |
| An update downloaded, then was refused | Either the update key was rotated out of order (§5.2) or the signing certificate was rotated (§4.4). Install that release by hand once |
| Gatekeeper after an update | It does not appear. The updater clears quarantine attributes on the new app before relaunching it (copied from Lookout's `UpdateInstaller`), and the designated requirement is unchanged, so macOS treats it as the app you already allowed. If it does appear, the build was signed with a different identity (§4.4) |
| Gatekeeper on first launch, and right-click → Open does nothing | macOS 15 removed that bypass; use §6.2 |
| Actions minutes running low | Each release runs one macOS job of about 6 minutes, counted ten times on a private repository: about 60 of the 2000 monthly minutes of GitHub Free (D-12, `03-architecture.md` §10). Thirty releases a month would exhaust it; pull requests cost only the Ubuntu job at 1× |
| `make install` fails at signing, while the release workflow succeeds | The identity is in the secrets but not in your login keychain (§4.3), or it is there under a different name than `Docket Self-Signed Code Signing` |
