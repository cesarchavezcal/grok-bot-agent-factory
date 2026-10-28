# Setup & Repository Protection Guide

When a new repository is created from this template (either manually or by **Grok Bot**), run the idempotent bootstrap command:

```bash
./scripts/init.sh
```

Below is what `./scripts/init.sh` configures and how to verify or run each step manually.

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

## 2. Allow Auto-Merge & Squash Merge

The `Autopilot-full` playbook merges PRs via **squash merge** once both the **`ci`** status check and independent verification (`verify-app` + Grok 4.7 interrogation) pass.

### CLI (`gh`)
```bash
gh repo edit \
  --enable-squash-merge \
  --enable-auto-merge \
  --delete-branch-on-merge \
  --enable-merge-commit=false \
  --enable-rebase-merge=false
```

### GitHub Web UI
1. Go to **Settings → General → Pull Requests**.
2. Enable **Allow squash merging** (disable merge commits and rebase merging if you want strict squash-only history).
3. Enable **Allow auto-merge**.
4. Enable **Automatically delete head branches**.

---

## 3. Branch Protection on `main` (Required Check: `ci`)

`.github/workflows/ci.yml` defines a job with the stable check name **`ci`**.

### CLI (`gh api`)
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

### GitHub Web UI
1. Go to **Settings → Branches → Add branch protection rule** (or Rulesets) for `main`.
2. Enable **Require a pull request before merging** and **Require conversation resolution before merging**.
3. Enable **Require status checks to pass before merging**:
   - Check **Require branches to be up to date before merging**.
   - Add status check: **`ci`**.
4. Enable **Require linear history**.

---

## 4. App Verification Skill (`.agents/skills/verify-app`)

Before running autonomous merges on a new application:
1. Customize `.agents/skills/verify-app/SKILL.md` (or copy it to `.agents/skills/verify-<app>/SKILL.md` and update `"verifySkill"` in `.factory/config.json`).
2. Document your user-facing feature verification recipes in `.agents/skills/verify-app/features/`.
