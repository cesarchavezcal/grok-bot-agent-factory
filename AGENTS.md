# AGENTS.md — Grok Bot Agent Factory

This repository is an autonomous software factory powered by **T3 Code**, official **`mattpocock/skills`**, and official **`pstack` (`poteto-mode`)**, coordinated with an external dispatcher (**Grok Bot**).

---

## 0. Creating a New Project & `template init`

> **Visibility Rule (GitHub Free):** While the template `cesarchavezcal/grok-bot-agent-factory` remains **PRIVATE**, **every working repository created from this template MUST be PUBLIC** (`--public`) so that GitHub Free permits branch protection (`ci` required status check) and `allow_auto_merge`.

When an agent or **Grok Bot** creates a new working project from this template:

```bash
# 1. Create the new working repository as PUBLIC from the private template
gh repo create <name> --public --template cesarchavezcal/grok-bot-agent-factory --clone
cd <name>

# 2. Run idempotent bootstrap (or `./scripts/init.sh --create-repo <name>` from a local dir)
./scripts/init.sh
```

What [`./scripts/init.sh`](scripts/init.sh) does (idempotent, safe to re-run at any time):
1. **Tool & Auth Verification**: Verifies `git`, `gh` (authenticated), `node`, and `npx` with clear diagnostic messages.
2. **Official Skills Sync**: Installs/restores the full official skills pinned by commit SHA and hash in [`skills-lock.json`](skills-lock.json):
   - From `mattpocock/skills`: [`wayfinder`](.agents/skills/wayfinder/SKILL.md), [`grill-with-docs`](.agents/skills/grill-with-docs/SKILL.md) (full standalone skill with `ADR-FORMAT.md` & `CONTEXT-FORMAT.md`), [`grilling`](.agents/skills/grilling/SKILL.md), [`domain-modeling`](.agents/skills/domain-modeling/SKILL.md), [`to-spec`](.agents/skills/to-spec/SKILL.md), [`to-tickets`](.agents/skills/to-tickets/SKILL.md), and [`tdd`](.agents/skills/tdd/SKILL.md) (with `tests.md` & `mocking.md`).
   - From `cursor/plugins` (`pstack`): [`poteto-mode`](.agents/skills/poteto-mode/SKILL.md) (including `playbooks/autopilot-full.md`).
   - Checks local [`.agents/skills/verify-app/SKILL.md`](.agents/skills/verify-app/SKILL.md).
3. **GitHub Labels**: Runs [`./scripts/setup-labels.sh`](scripts/setup-labels.sh) to ensure the `agent` trigger label, `epic` planning label, and workflow state labels exist (and prints the Linear `agent` label note).
4. **Merge Policy & Branch Protection (`gh api`)**:
   - Calls `gh api PATCH repos/<owner>/<repo>` to enable `allow_auto_merge=true`, `allow_squash_merge=true`, `allow_merge_commit=false`, `allow_rebase_merge=false`, and `delete_branch_on_merge=true`.
   - Calls `gh api PUT repos/<owner>/<repo>/branches/main/protection` to protect `main` with the required status check **`ci`** (`strict: true`), linear history, and conversation resolution.
   - If the repository is private on a GitHub Free plan (API returns `403 / Upgrade to GitHub Pro`), it prints an **explicit warning** with the command to make the working repo public (`gh repo edit <repo> --visibility public --accept-visibility-change-consequences`) and does not fail silently.
5. **Factory Config & T3 Registration**: Updates the `app` slug in [`.factory/config.json`](.factory/config.json) and prints the optional T3 Code registration call (`t3_project_create`).

---

## 1. Intake Rule (`agent` & `epic` Label Gate)

- **Entry Condition**: Only issues from **GitHub Issues** or **Linear** carrying the **`agent`** label are eligible for execution.
- **Ignore Rule**: Any issue without the `agent` label MUST be ignored completely.
- **Normal vs. Epic Flow**:
  - **`agent` alone**: Normal issue — executes the standard plan, build, verify, and merge pipeline. Its PR body MUST include `Closes #N` (never `Refs #N`) so the issue closes automatically when the PR merges.
  - **`epic` + `agent`**: Planning-only thread that splits the epic into sub-issues labeled `agent` (`Part of #N`), where the last sub-issue is deploy. Each sub-issue PR includes `Closes #N` (never `Refs #N`), and the last (deploy) sub-issue PR also includes `Closes #EPIC` so merging the final PR closes both the deploy sub-issue and the parent epic. Do not write or merge implementation code directly on the epic thread.
  - **Issue Closing Rule**: Agents never close issues by hand; issues close only when a PR with `Closes #N` (and `Closes #EPIC` on the final deploy sub-issue PR) merges.
  - **Labeling Order**: Always add **`epic` before `agent`** so the `epic` label is already present on the issue when adding `agent` triggers `.github/workflows/notify-grok.yml`.
- **Work-Item State**: Each accepted issue is tracked in `.factory/work-items/<id>.json` following [`.factory/work-item.schema.json`](.factory/work-item.schema.json). Do not commit runtime work-item JSON files unless explicitly asked.

---

## 2. Pipeline Stages & Official Skills

| Stage | Primary Skill(s) | Active Model (`provider::model`) | Pool |
| :--- | :--- | :--- | :--- |
| **Phase 0: Context Scout** | Repo exploration & context brief (`<2KB`) | `antigravity::gemini-3.8-flash-high` | `AGY_FAST` |
| **Phase 1: Discovery & Grilling** | [`wayfinder`](.agents/skills/wayfinder/SKILL.md), [`grill-with-docs`](.agents/skills/grill-with-docs/SKILL.md), [`grilling`](.agents/skills/grilling/SKILL.md), [`domain-modeling`](.agents/skills/domain-modeling/SKILL.md) | `antigravity::gemini-4-argon-high` | `AGY_PRO` |
| **Phase 2: Spec & Tickets** | [`to-spec`](.agents/skills/to-spec/SKILL.md), [`to-tickets`](.agents/skills/to-tickets/SKILL.md) | `antigravity::gemini-4-argon-high` | `AGY_PRO` |
| **Phase 3a: Build (UI / CRUD)** | [`poteto-mode`](.agents/skills/poteto-mode/SKILL.md) ([`autopilot-full`](.agents/skills/poteto-mode/playbooks/autopilot-full.md)) + [`tdd`](.agents/skills/tdd/SKILL.md) | `antigravity::gemini-3.8-flash-high` | `AGY_FAST` |
| **Phase 3b: Build (Backend / Complex)** | [`poteto-mode`](.agents/skills/poteto-mode/SKILL.md) ([`autopilot-full`](.agents/skills/poteto-mode/playbooks/autopilot-full.md)) + [`tdd`](.agents/skills/tdd/SKILL.md) | `grok::grok-4.7-build-fast` (`reasoningEffort: medium`) | `GROK_WORK` |
| **Phase 4a: Runtime Verification** | [`verify-app`](.agents/skills/verify-app/SKILL.md) (`verify-<app>`) | `antigravity::gemini-3.8-flash-high` | `AGY_FAST` |
| **Phase 4b: Independent Audit** | Adversarial diff & spec interrogation | `grok::grok-4.7` (`reasoningEffort: high`) | `GROK_AUDIT` |
| **Rework Escalation (max 2)** | Scoped repair from 4a/4b findings | `antigravity::gemini-4-argon-high` (`maxRetries: 2`) | `AGY_PRO` |

### Strict Invariants
- **Zero Paid API Keys**: Never require or read `GEMINI_API_KEY`, `XAI_API_KEY`, `CURSOR_API_KEY`, `ANTHROPIC_API_KEY`, or `OPENAI_API_KEY`. All models run through authenticated sessions.
- **100% Claude-Free**: Never route tasks to Claude models (`disallowClaude: true`).
- **Model Separation on Audit & Rework**: Rework escalates to `antigravity::gemini-4-argon-high` (up to 2 attempts) so the rework builder is always a different model family from the `grok::grok-4.7` auditor.

---

## 3. Grilling Protocol (Stop & Wait for Grok Bot)

During **Planning / Grilling** (`grill-with-docs` / `wayfinder`):
1. **Self-Deduction First**: Explore the repository, types, tests, ADRs, and existing docs to answer every question that can be deduced from code. Never ask a human what the repository already answers.
2. **Batched Clarification Block (2–3 Questions)**: If genuine product, scope, or trade-off ambiguities remain that cannot be deduced from the repo:
   - Formulate a **single numbered list of 2 to 3 independent, high-leverage questions**.
   - Record the questions in `.factory/work-items/<id>.json` under `pendingQuestions`, set `stage: "grilling"`, `status: "blocked"`, and `waitingOn: "human"`.
   - Post the numbered block to the issue / dispatcher output and **STOP immediately**.
3. **Resume on Dispatcher Reply**: Do not guess or proceed until the human reply arrives via the external dispatcher (**Grok Bot**). Once answered, lock decisions into docs/spec via `to-spec` and slice vertical tracer-bullet tickets via `to-tickets`.

---

## 4. Build, Verification & Merge (`poteto-mode` · `Autopilot-full`)

Execution follows the official pstack [`poteto-mode`](.agents/skills/poteto-mode/SKILL.md) skill, [`tdd`](.agents/skills/tdd/SKILL.md) seam discipline, and the [`Autopilot-full`](.agents/skills/poteto-mode/playbooks/autopilot-full.md) playbook:

1. **Parallel Worktrees (Max Concurrency = 3)**:
   - Run at most **3 concurrent ticket owners** in isolated Git worktrees branched directly off `main` (never stacked).
   - Route standard UI/CRUD tickets to `antigravity::gemini-3.8-flash-high` ([`.cursor/agents/builder-flash.md`](.cursor/agents/builder-flash.md)) and complex backend/DB/concurrency/security/architecture tickets to `grok::grok-4.7-build-fast` ([`.cursor/agents/builder-grok.md`](.cursor/agents/builder-grok.md)).
2. **Independent Verification Before Merge**:
   - Green CI (`ci`) alone **never** authorizes a merge.
   - Before merging, every PR must pass:
     - **Green CI check (`ci`)** on the current head rebased onto `main`.
     - **Phase 4a Runtime Verification** (`antigravity::gemini-3.8-flash-high`) running `.agents/skills/verify-app` (or `verify-<app>`) against a disposable instance with artifacts saved under `artifacts/<work-item-id>/`.
     - **Phase 4b Independent Interrogation** (`grok::grok-4.7`, `reasoningEffort: high`, [`.cursor/agents/interrogator-grok.md`](.cursor/agents/interrogator-grok.md)) auditing the diff, spec, and verification evidence (`verdict: PASS`).
3. **Rework Escalation (Up to 2 Attempts)**:
   - If Phase 4a or Phase 4b fails, increment `retryCount` and escalate the rework pass to **`antigravity::gemini-4-argon-high`** (`maxRetries: 2`).
   - If the ticket still fails after 2 rework attempts, set `status: "blocked"`, `waitingOn: "blocked"`, and stop for human intervention.
4. **Squash Merge & Auto-Closing Issues**:
   - Every PR body MUST use `Closes #N` (never `Refs #N`) so the issue closes automatically when the PR merges; for epics, the last (deploy) sub-issue PR also includes `Closes #EPIC`. Agents never close issues by hand.
   - Once `ci` is green and both Phase 4a and Phase 4b pass on the `main`-rebased head, merge via **squash merge** (`gh pr merge --squash --delete-branch`).
