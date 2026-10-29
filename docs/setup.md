# Setup & GitHub/Linear Configuration Guide

This guide covers initial setup, GitHub merge policies, branch protection, secrets, labels, and template sync for working repositories created from `cesarchavezcal/grok-bot-agent-factory`.

> **Reminder (GitHub Free):** Working repositories created from this template **must be PUBLIC** (`--public`) so that GitHub Free allows required status checks (`ci`) and `allow_auto_merge`.

---

## 1. Labels (`agent`, `epic`, `deploy`, `bug`)

The factory relies on GitHub and Linear labels to route incoming tickets to the appropriate orchestrator skill.

### GitHub
Run the idempotent label script (also executed automatically by `./scripts/init.sh`):

```bash
./scripts/setup-labels.sh
```

This creates/updates:
- `agent` (`#0E8A16`) — Trigger: issue is picked up by the autonomous agent factory (Grok Bot).
- `epic` (`#B60205`) — Planning only: split into agent sub-issues.
- `deploy` (`#006B75`) — Deploy trigger: applied to the final sub-issue of an epic after green merge.
- `waiting-for-human` (`#FBCA04`) — Blocked on questions awaiting human response via Grok Bot.
- `in-progress` (`#1D76DB`), `rework` (`#D93F0B`), `ready-to-merge` (`#5319E7`), `feature` (`#A2EEEF`), `bug` (`#D73A4A`).

### Skill Routing Matrix
- **`epic` + `agent`** -> **`plan-epic`**: Planning-only thread that decomposes an epic into vertical sub-issues (`Part of #N`). Every created sub-issue MUST get the `agent` label; exactly one final sub-issue receives the `deploy` label. Label existence is verified before completion.
- **`bug` + `agent`** -> **`fix-bug`**: Reproduction-first defect workflow. Reproduces first (if unable to reproduce, stops and asks César in thread final message) -> writes failing test -> fixes root cause (`ce-debug`, `tdd`, `principle-fix-root-causes`) -> verifies all tests + runs app once -> Grok audit -> PR `Closes #N` -> merge on green CI.
- **`agent` alone (or with `feature`)** -> **`implement-ticket`**: Full lifecycle: plan (`grill-with-docs` + `wayfinder`) -> build (`poteto-mode`) -> Grok audit -> rework rule -> PR `Closes #N` -> merge on green CI. Deploys only if the issue has the `deploy` label.
- **Deploy Rule**: Intermediate sub-issues never deploy. Deploy occurs only on the final sub-issue of an epic (carrying the `deploy` label), after its green merge.
- **Issue Closing Rule**: Every PR body uses `Closes #N` (never `Refs #N`). For epics, the final deploy sub-issue PR also includes `Closes #EPIC`. Agents never close issues by hand.
- **Communication Rule**: Never comment on issues or PRs. When questions or reproduction blockers arise, stop and write them in the thread final message for dispatcher relay.

### Linear
In Linear (**Workspace Settings → Labels**), create a label named **`agent`** (exact lowercase). Only Linear issues tagged with `agent` are dispatched.

---

## 2. Grok Bot Webhook Secrets (`GROK_WEBHOOK_URL` & `GROK_WEBHOOK_AUTH`)

`.github/workflows/notify-grok.yml` triggers on `issues` (`opened`, `labeled`) and verifies the presence of the `agent` label:
- When an issue is **created with labels** (e.g., via the `.github/ISSUE_TEMPLATE/bug.yml` issue form), it dispatches immediately on `opened`. The subsequent initial `labeled` event is ignored via `created_at != updated_at` comparison to prevent double-firing.
- When `agent` is **added later to an existing issue**, it dispatches on `labeled`.
- The webhook payload includes the full event enriched with an explicit top-level `labels` array.

### Required Repository Secrets
- `GROK_WEBHOOK_URL` — Full HTTPS webhook endpoint URL for Grok Bot.
- `GROK_WEBHOOK_AUTH` — Value sent in the `Authorization` HTTP header (for example, `Bearer <token>`).

During `./scripts/init.sh`, the script checks `gh secret list` for both secrets:
- Any secret already present is skipped (idempotent).
- Any missing secret prompts interactively with hidden input via `gh secret set <NAME>` when a TTY is attached (never echoing or logging secret values).
- If run non-interactively (no TTY) or if you skip the prompt, `./scripts/init.sh` finishes cleanly and prints a reminder with the manual commands:

```bash
gh secret set GROK_WEBHOOK_URL
gh secret set GROK_WEBHOOK_AUTH
```

If either `GROK_WEBHOOK_URL` or `GROK_WEBHOOK_AUTH` is not configured when an issue is labeled with `agent`, `.github/workflows/notify-grok.yml` logs a `::notice::` annotation and exits `0` without failing workflow runs.

---

## 3. Allow Auto-Merge, Squash Merge & Preserve Branches

The `Autopilot-full` playbook merges PRs via **squash merge** once both the **`ci`** status check and independent verification (`verify-app` + Grok 4.7 interrogation) pass. Branches are preserved (`delete_branch_on_merge=false`). Every PR body uses `Closes #N` (never `Refs #N`) so the issue closes when the PR merges, and for epics the last (deploy) sub-issue PR also includes `Closes #EPIC`.

### CLI (`gh api PATCH`)
```bash
REPO="$(gh repo view --json nameWithOwner --jq '.nameWithOwner')"
gh api --method PATCH "repos/$REPO" \
  -F allow_auto_merge=true \
  -F allow_squash_merge=true \
  -F allow_merge_commit=false \
  -F allow_rebase_merge=false \
  -F delete_branch_on_merge=false
```

---

## 4. Branch Protection on `main` (Required Check: `ci`)

`.github/workflows/ci.yml` defines a job with the stable check name **`ci`**.

### CLI (`gh api PUT`)
```bash
REPO="$(gh repo view --json nameWithOwner --jq '.nameWithOwner')"
gh api --method PUT "repos/$REPO/branches/main/protection" --input - <<'EOF'
{
  "required_status_checks": {
    "strict": true,
    "contexts": ["ci"]
  },
  "enforce_admins": false,
  "required_pull_request_reviews": null,
  "restrictions": null,
  "required_linear_history": true,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "required_conversation_resolution": true
}
EOF
```

### If the Repo Was Created Private on GitHub Free
If the API returns HTTP `403` (`Upgrade to GitHub Pro or make this repository public to enable this feature`), make the working repository public and re-run `./scripts/init.sh`:

```bash
gh repo edit "$REPO" --visibility public --accept-visibility-change-consequences
./scripts/init.sh
```

---

## 5. App Verification Skill (`.agents/skills/verify-app`)

Before running autonomous merges on a new application:
1. Customize `.agents/skills/verify-app/SKILL.md` (or copy it to `.agents/skills/verify-<app>/SKILL.md` and update `"verifySkill"` in `.factory/config.json`).
2. Document your user-facing feature verification recipes in `.agents/skills/verify-app/features/`.

---

## 6. Syncing Upstream Template Updates (`./scripts/sync-template.sh`)

Derived working repositories can pull factory infrastructure updates from the private template (`cesarchavezcal/grok-bot-agent-factory`) at any time without touching application code:

```bash
# Sync from `main` (default) inside a derived working repo and open a PR if managed files changed
./scripts/sync-template.sh

# Sync from a specific branch, tag, or commit SHA
./scripts/sync-template.sh --ref <branch-or-sha>

# Run from a template checkout against another target repository (including first-time sync)
./scripts/sync-template.sh --target /path/to/working-repo

# Preview the diff summary without creating a branch or PR
./scripts/sync-template.sh --dry-run
```

### How It Works
1. **Authenticated Private Fetch**: Uses `gh repo clone` (`gh` CLI authentication) to fetch `cesarchavezcal/grok-bot-agent-factory` into a temporary directory.
2. **First-Time Bootstrap & `--target <path>`**:
   - If the target repository does not yet have `.factory/template-sync.json`, `sync-template.sh` fetches `.factory/template-sync.json` from the template ref via `gh` auth, uses it to drive the sync, and includes `.factory/template-sync.json` in the synced files.
   - Pass `--target <path>` to run `scripts/sync-template.sh` directly from a template checkout against any target repository; both the clean working-tree guard and the template self-guard evaluate the **target** repository rather than the script's location.
3. **Explicit Manifest (`.factory/template-sync.json`)**: Copies only the managed paths declared in `.factory/template-sync.json`:
   - `.factory/template-sync.json`
   - `.github/workflows/*`
   - `scripts/*` (including `scripts/sync-template.sh`, `scripts/init.sh`, and `scripts/setup-labels.sh`)
   - `.agents/skills/*`
   - `.cursor/rules`
   - `.cursor/agents`
   - `AGENTS.md`
   - `skills-lock.json`
   - `.factory/work-item.schema.json`
   - `.factory/WORK-ITEM.example.json`
4. **Never Touches App Code**: Application source files, `.factory/config.json` (which stores the working repo's `app` slug and `verifySkill`), `.factory/work-items`, and `.agents/skills/verify-app/features` are preserved.
