# Setup & Repository Protection Guide

> **Important (GitHub Free Policy):** The template repository `cesarchavezcal/grok-bot-agent-factory` stays **PRIVATE**, but **all working repositories created from this template MUST be created as PUBLIC** (`--public`). GitHub Free only supports Branch Protection (`ci` required check) and Auto-Merge on public repositories.

---

## 0. Create a New Working Repository from the Template (`PUBLIC`)

When an agent or **Grok Bot** creates a new working project from this template:

```bash
gh repo create <name> --public --template cesarchavezcal/grok-bot-agent-factory --clone
cd <name>
./scripts/init.sh
```

Or if initializing from an existing local directory without a remote yet:

```bash
./scripts/init.sh --create-repo <name>
```

`./scripts/init.sh` is **100% idempotent** and safe to re-run at any time. If a repository happens to be private on a GitHub Free plan (where the GitHub API returns HTTP `403 / Upgrade to GitHub Pro`), `./scripts/init.sh` emits an explicit warning with the exact command to switch visibility to public without failing silently.

---

## 1. Labels (`agent` Intake Gate)

Only issues carrying the **`agent`** label are processed by the factory. All unlabeled issues (or issues without `agent`) are ignored.

### GitHub
Run the idempotent label script:

```bash
./scripts/setup-labels.sh
```

This creates/updates:
- `agent` (`#0E8A16`) — Trigger for Grok Bot / Agent Factory intake.
- `waiting-for-human` (`#FBCA04`) — Set when the agent posts a numbered block of 2–3 grilling questions and stops.
- `in-progress` (`#1D76DB`), `rework` (`#D93F0B`), `ready-to-merge` (`#5319E7`), `feature` (`#A2EEEF`), `bug` (`#D73A4A`).

### Linear
In Linear (**Workspace Settings → Labels**), create a label named **`agent`** (exact lowercase). Only Linear issues tagged with `agent` are dispatched.

---

## 2. Grok Bot Webhook Secrets (`GROK_WEBHOOK_URL` & `GROK_WEBHOOK_AUTH`)

`.github/workflows/notify-grok.yml` triggers on `issues` (`types: [labeled]`) and runs only when the added label is **`agent`** (`github.event.label.name == 'agent'`). It forwards the GitHub event payload (`$GITHUB_EVENT_PATH`) via `POST` to your Grok Bot endpoint.

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

## 3. Allow Auto-Merge, Squash Merge & Delete Branch on Merge

The `Autopilot-full` playbook merges PRs via **squash merge** once both the **`ci`** status check and independent verification (`verify-app` + Grok 4.7 interrogation) pass.

### CLI (`gh api PATCH`)
```bash
REPO="$(gh repo view --json nameWithOwner --jq '.nameWithOwner')"
gh api --method PATCH "repos/$REPO" \
  -F allow_auto_merge=true \
  -F allow_squash_merge=true \
  -F allow_merge_commit=false \
  -F allow_rebase_merge=false \
  -F delete_branch_on_merge=true
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
   - If the target repository does not yet have `.factory/template-sync.json` (for example, an older derived repo or an existing project adopting the factory), `sync-template.sh` fetches `.factory/template-sync.json` from the template ref via `gh` auth, uses it to drive the sync, and includes `.factory/template-sync.json` in the synced files.
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
5. **Idempotent**: If no managed files changed, it prints an up-to-date message and exits `0` without creating a branch or opening a PR.
6. **Version Tracking (`.factory/template-version`)**: When managed files change, it records the synced 40-character template commit SHA in `.factory/template-version`, prints a diff summary, pushes `chore/template-sync-<short-sha>`, and opens (or updates) a Pull Request against `main`.
