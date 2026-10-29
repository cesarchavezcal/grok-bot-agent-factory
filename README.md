# Grok Bot Agent Factory (Template)

Reusable, zero-API-key, Claude-free software factory template orchestrated with **T3 Code**, official **`mattpocock/skills`**, and official **`pstack` (`poteto-mode`)**, designed to work with an external issue dispatcher (**Grok Bot**).

---

## Quick Start (`template init` — Public Working Repos)

> **Note on Visibility (GitHub Free):** This template repository (`cesarchavezcal/grok-bot-agent-factory`) is **PRIVATE**, but **all working repositories created from it MUST be PUBLIC** (`--public`) so GitHub Free enables branch protection (`ci` required status check) and `allow_auto_merge`.

When creating a new project from this template (manually or via **Grok Bot**):

```bash
# 1. Create a PUBLIC working repository from the template
gh repo create <name> --public --template cesarchavezcal/grok-bot-agent-factory --clone
cd <name>

# 2. Run the idempotent initialization script
./scripts/init.sh
```

*(Alternatively, inside an existing local checkout without a remote yet, run `./scripts/init.sh --create-repo <name>` to create the public GitHub repository and bootstrap it in one step.)*

[`./scripts/init.sh`](scripts/init.sh) is 100% idempotent and safe to re-run at any time without duplicate side effects. It:
1. Verifies required CLI tools (`git`, `gh` authenticated, `node`, `npx`).
2. Installs/restores all official skills pinned by commit SHA and hash in [`skills-lock.json`](skills-lock.json) into `.agents/skills/`.
3. Creates/updates GitHub repository labels (`agent`, `epic`, `deploy`, `bug`, etc.) via [`./scripts/setup-labels.sh`](scripts/setup-labels.sh).
4. Configures GitHub merge policy via `gh api PATCH` (`allow_auto_merge=true`, `allow_squash_merge=true`, `delete_branch_on_merge=false`) and **Branch protection on `main`** via `gh api PUT` with the required status check **`ci`**. If a repository is private on GitHub Free (`403 / upgrade`), it emits a clear, explicit warning instead of failing silently.
5. Checks `gh secret list` for `GROK_WEBHOOK_URL` and `GROK_WEBHOOK_AUTH`, interactively running `gh secret set` (hidden input) for any missing secret when a TTY is present, or printing a clear reminder without failing if skipped or run non-interactively.
6. Updates the project slug in [`.factory/config.json`](.factory/config.json) and prints the optional T3 Code project registration command.

See [`docs/setup.md`](docs/setup.md) for manual GitHub/Linear setup details and [`AGENTS.md`](AGENTS.md) for the complete agent operating contract.

### Syncing Upstream Template Updates (`sync-template.sh`)

Inside any working repository derived from this template (or from a template checkout targeting another repo via `--target`), pull the latest managed workflows, scripts, skills, and rules from the private `cesarchavezcal/grok-bot-agent-factory` template and open a PR:

```bash
./scripts/sync-template.sh                          # Sync from `main` (default)
./scripts/sync-template.sh --ref <ref>              # Sync from a specific branch, tag, or SHA
./scripts/sync-template.sh --target /path/to/repo   # Sync another repo from a template checkout
./scripts/sync-template.sh --dry-run                # Print diff summary without creating a branch/PR
```

- **First-Time Sync Ready**: If the target repo does not yet have `.factory/template-sync.json`, the script fetches the manifest from the template ref via `gh` auth, uses it to drive the sync, and includes `.factory/template-sync.json` in the synced files.
- **Remote Target (`--target <path>`)**: Can be run from a template checkout against another local repo; both the dirty-tree guard and the template self-guard apply to the target repo rather than the script location.
- **Explicit Manifest ([`.factory/template-sync.json`](.factory/template-sync.json))**: Syncs only managed factory paths (`.factory/template-sync.json`, `.github/workflows/*`, `.github/ISSUE_TEMPLATE/*`, `scripts/*`, `.agents/skills/*`, `.cursor/rules`, `.cursor/agents`, `AGENTS.md`, `skills-lock.json`, `.factory/work-item.schema.json`, `.factory/WORK-ITEM.example.json`) and never touches application code or `.factory/config.json`.
- **Idempotent**: Prints a diff summary and creates no branch or PR when nothing changed.
- **Version Tracking ([`.factory/template-version`](.factory/template-version))**: Records the synced 40-character template commit SHA.

---

## Workflow Overview

1. **Intake & Dispatch Routing (`agent`, `bug`, `epic` labels)**:
   - Only GitHub Issues or Linear Issues labeled with **`agent`** are ingested. Everything else is ignored.
   - [`.github/workflows/notify-grok.yml`](.github/workflows/notify-grok.yml) triggers on `issues` (`opened`, `labeled`) and passes the full event payload enriched with explicit top-level `labels` and `delivery_id` to `GROK_WEBHOOK_URL` (with `Authorization: $GROK_WEBHOOK_AUTH`).
   - **Double-Fire Prevention**: Concurrency with `cancel-in-progress: true` keyed by issue number cancels redundant in-flight runs when issues are created with template labels.
   - **Skill Routing Matrix & Precedence**:
     - **`epic` + `agent`** -> **[`plan-epic`](.agents/skills/plan-epic/SKILL.md)**: Planning-only flow that decomposes an epic into vertical tracer-bullet sub-issues. Every created sub-issue MUST have `agent`; exactly one final sub-issue receives `deploy`. Label existence is verified before ending. `epic` takes precedence over all other labels.
     - **`bug` + `agent`** -> **[`fix-bug`](.agents/skills/fix-bug/SKILL.md)**: Reproduction-first defect workflow. Reproduces first (if not reproducible, stops and asks in thread final message) -> failing test -> root cause fix (`ce-debug`, `tdd`, `principle-fix-root-causes`) -> verifies all tests + runs app once -> Grok audit -> PR `Closes #N` -> merge on green CI.
     - **`agent` alone (or with `feature`)** -> **[`implement-ticket`](.agents/skills/implement-ticket/SKILL.md)**: Standard feature pipeline orchestrating plan (`wayfinder` + `grill-with-docs`) -> build (`poteto-mode`) -> Grok audit -> rework -> PR `Closes #N` -> squash merge on green CI. Deploys only if the issue carries the `deploy` label.
2. **Communication Discipline**:
   - **Never comment on GitHub/Linear issues or PRs**.
   - If clarification or reproduction guidance is needed for César, the agent stops immediately and writes the questions in the **thread final message**. The external dispatcher (**Grok Bot**) relays it to César.
3. **Planning (`mattpocock/skills`)**:
   - Uses official skills pinned in [`skills-lock.json`](skills-lock.json): [`wayfinder`](.agents/skills/wayfinder/SKILL.md), [`grill-with-docs`](.agents/skills/grill-with-docs/SKILL.md), [`grilling`](.agents/skills/grilling/SKILL.md), [`domain-modeling`](.agents/skills/domain-modeling/SKILL.md), [`to-spec`](.agents/skills/to-spec/SKILL.md), [`to-tickets`](.agents/skills/to-tickets/SKILL.md), and [`tdd`](.agents/skills/tdd/SKILL.md).
4. **Build & Merge (`pstack` `poteto-mode` · `Autopilot-full`)**:
   - Follows official [`poteto-mode`](.agents/skills/poteto-mode/SKILL.md) under the [`Autopilot-full`](.agents/skills/poteto-mode/playbooks/autopilot-full.md) playbook + [`tdd`](.agents/skills/tdd/SKILL.md).
   - Every PR body uses `Closes #N` (never `Refs #N`). For epics, the final deploy sub-issue PR also includes `Closes #EPIC`.
   - Merges via **squash merge** (`gh pr merge <PR_NUMBER> --squash` without `--delete-branch`) only when **`ci` is green** AND **independent verification + Grok audit** pass. Branches are never deleted.

---

## Model Orchestration (Zero API Keys, Zero Claude, Zero Argon)

| Role | Provider & Model | Pool | Notes |
| :--- | :--- | :--- | :--- |
| **Context Scout** | `antigravity::gemini-3.8-flash-low` | `AGY_FAST` | Fast repo scout & context brief (`<2KB`), low effort |
| **Spec & Plan** | `antigravity::gemini-3.8-flash-high` | `AGY_FAST` | `wayfinder`, `grill-with-docs`, `to-spec`, `plan-epic`, high effort |
| **Build (UI / CRUD)** | `antigravity::gemini-3.8-flash-medium` | `AGY_FAST` | Standard UI, CRUD, frontend, docs slices, medium effort |
| **Build (Backend)** | `grok::grok-4.7-build-fast` | `GROK_WORK` | DB, SQL, concurrency, security, state machines (`reasoningEffort: medium`) |
| **Runtime Verify** | `antigravity::gemini-3.8-flash-medium` | `AGY_FAST` | Drives `.agents/skills/verify-app` (`exitCode: 0`), medium effort |
| **Adversarial Audit** | `grok::grok-4.7` (`reasoningEffort: high`) | `GROK_AUDIT` | Independent read-only diff & spec interrogation |
| **Rework Escalation** | `antigravity::gemini-3.8-flash-high` | `AGY_FAST` | Up to **2 attempts** (`maxRetries: 2`), distinct from Grok auditor, high effort |

### Gemini Flash Effort Rule
Gemini Flash effort is chosen strictly according to task complexity:
- **`low`** (`gemini-3.8-flash-low`): Scout & simple exploratory tasks (Phase 0 Context Scout).
- **`medium`** (`gemini-3.8-flash-medium`): Normal work including standard UI/CRUD builds (Phase 3a) and runtime verification (Phase 4a).
- **`high`** (`gemini-3.8-flash-high`): High-complexity problems including discovery & grilling (Phase 1), spec & ticket breakdown (Phase 2), and rework escalation passes.

---

## Repository Structure

```text
.
├── AGENTS.md                                    # Agent operating contract & pipeline rules
├── README.md                                    # Overview & quick start
├── skills-lock.json                             # Locked official skills (mattpocock/skills + pstack)
├── .agents/skills/                              # Official skills + orchestrators + verify-app template
│   ├── implement-ticket/                        # High-level feature orchestrator skill
│   ├── fix-bug/                                 # High-level bug fixing orchestrator skill
│   ├── plan-epic/                               # High-level epic planning orchestrator skill
│   ├── wayfinder/
│   ├── grill-with-docs/
│   ├── grilling/
│   ├── domain-modeling/
│   ├── to-spec/
│   ├── to-tickets/
│   ├── tdd/
│   ├── poteto-mode/
│   └── verify-app/
├── .cursor/
│   ├── rules/factory.mdc                        # Always-applied factory rules
│   └── agents/                                  # Builder (Flash/Grok) & Interrogator (Grok) profiles
├── .factory/
│   ├── config.json                              # Generic factory & model routing configuration
│   ├── template-sync.json                       # Explicit manifest of managed template sync paths
│   ├── template-version                         # Synced template commit SHA
│   ├── work-item.schema.json                    # Work-item JSON schema
│   ├── WORK-ITEM.example.json                   # Work-item example
│   └── work-items/.gitkeep                      # Runtime work-items directory
├── .github/
│   ├── ISSUE_TEMPLATE/                          # Issue forms (bug.yml, feature.md, config.yml)
│   ├── PULL_REQUEST_TEMPLATE.md                 # Generic PR receipt template
│   └── workflows/
│       ├── ci.yml                               # Generic CI workflow (stable check name: `ci`)
│       └── notify-grok.yml                      # Dispatches `agent`-labeled issues to Grok Bot webhook
├── docs/setup.md                                # Branch protection, auto-merge, secrets, labels & sync guide
└── scripts/
    ├── init.sh                                  # Idempotent `template init` bootstrap script
    ├── setup-labels.sh                          # Idempotent GitHub labels script (+ Linear note)
    └── sync-template.sh                         # Idempotent upstream template sync & PR script
```
