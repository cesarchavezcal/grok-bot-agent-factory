# Grok Bot Agent Factory (Template)

Reusable, zero-API-key, Claude-free software factory template orchestrated with **T3 Code**, official **`mattpocock/skills`**, and official **`pstack` (`poteto-mode`)**, designed to work with an external issue dispatcher (**Grok Bot**).

---

## Quick Start (`template init`)

When creating a new project from this template (manually or via **Grok Bot**), run the idempotent initialization script:

```bash
./scripts/init.sh
```

`./scripts/init.sh` is safe to re-run at any time without duplicate side effects. It:
1. Verifies required CLI tools (`git`, `gh` authenticated, `node`, `npx`).
2. Installs/restores all official skills pinned in [`skills-lock.json`](skills-lock.json) into `.agents/skills/`.
3. Creates/updates GitHub repository labels (including `agent`) via [`./scripts/setup-labels.sh`](scripts/setup-labels.sh).
4. Configures GitHub merge policy (**Allow auto-merge**, **Squash merge only**, **Delete branch on merge**) and **Branch protection on `main`** with the required status check **`ci`**.
5. Updates the project slug in [`.factory/config.json`](.factory/config.json) and prints the optional T3 Code project registration command.

See [`docs/setup.md`](docs/setup.md) for manual GitHub/Linear setup details and [`AGENTS.md`](AGENTS.md) for the complete agent operating contract.

---

## Workflow Overview

1. **Intake (`agent` label only)**:
   - Only GitHub Issues or Linear Issues labeled with **`agent`** are ingested. Everything else is ignored.
2. **Planning (`mattpocock/skills`)**:
   - Uses official skills installed from `mattpocock/skills` and locked in [`skills-lock.json`](skills-lock.json):
     - [`wayfinder`](.agents/skills/wayfinder/SKILL.md)
     - [`grill-with-docs`](.agents/skills/grill-with-docs/SKILL.md) ([`grilling`](.agents/skills/grilling/SKILL.md) + [`domain-modeling`](.agents/skills/domain-modeling/SKILL.md))
     - [`to-spec`](.agents/skills/to-spec/SKILL.md)
     - [`to-tickets`](.agents/skills/to-tickets/SKILL.md)
3. **Grilling (Deduce First, Ask 2–3 Questions & Stop)**:
   - The agent resolves everything deducible from the codebase and docs first.
   - Any remaining non-deducible ambiguity is asked in a **single numbered block of 2–3 independent questions**, and the agent **STOPS** waiting for the reply via **Grok Bot**.
4. **Build & Merge (`pstack` `poteto-mode` · `Autopilot-full`)**:
   - Uses official [`poteto-mode`](.agents/skills/poteto-mode/SKILL.md) (`cursor/plugins`, locked in [`skills-lock.json`](skills-lock.json)) under the [`Autopilot-full`](.agents/skills/poteto-mode/playbooks/autopilot-full.md) playbook.
   - Runs up to **3 concurrent worktrees** off `main`.
   - Merges via **squash merge** only when **`ci` is green** AND **independent verification** ([`verify-app`](.agents/skills/verify-app/SKILL.md) runtime proof + `grok-4.7` adversarial interrogation) passes.

---

## Model Orchestration (Zero API Keys, Zero Claude)

| Role | Provider & Model | Pool | Notes |
| :--- | :--- | :--- | :--- |
| **Context Scout** | `antigravity::gemini-3.8-flash-high` | `AGY_FAST` | Fast repo scout & context brief (`<2KB`) |
| **Spec & Plan** | `antigravity::gemini-4-argon-high` | `AGY_PRO` | `wayfinder`, `grill-with-docs`, `to-spec`, `to-tickets` |
| **Build (UI / CRUD)** | `antigravity::gemini-3.8-flash-high` | `AGY_FAST` | Standard UI, CRUD, frontend, docs slices |
| **Build (Backend)** | `grok::grok-4.7-build-fast` | `GROK_WORK` | DB, SQL, concurrency, security, state machines |
| **Runtime Verify** | `antigravity::gemini-3.8-flash-high` | `AGY_FAST` | Drives `.agents/skills/verify-app` (`exitCode: 0`) |
| **Adversarial Audit** | `grok::grok-4.7` (`reasoningEffort: high`) | `GROK_AUDIT` | Independent read-only diff & spec interrogation |
| **Rework Escalation** | `antigravity::gemini-4-argon-high` | `AGY_PRO` | Up to **2 attempts** (`maxRetries: 2`), distinct from Grok auditor |

---

## Repository Structure

```text
.
├── AGENTS.md                                    # Agent operating contract & pipeline rules
├── README.md                                    # Overview & quick start
├── skills-lock.json                             # Locked official skills (mattpocock/skills + pstack)
├── .agents/skills/                              # Official skills + single verify-app template
│   ├── wayfinder/
│   ├── grill-with-docs/
│   ├── grilling/
│   ├── domain-modeling/
│   ├── to-spec/
│   ├── to-tickets/
│   ├── poteto-mode/
│   └── verify-app/
├── .cursor/
│   ├── rules/factory.mdc                        # Always-applied factory rules
│   └── agents/                                  # Builder (Flash/Grok) & Interrogator (Grok) profiles
├── .factory/
│   ├── config.json                              # Generic factory & model routing configuration
│   ├── work-item.schema.json                    # Work-item JSON schema
│   ├── WORK-ITEM.example.json                   # Work-item example
│   └── work-items/.gitkeep                      # Runtime work-items directory
├── .github/
│   ├── ISSUE_TEMPLATE/                          # Human feature.md, bug.md, and config.yml
│   ├── PULL_REQUEST_TEMPLATE.md                 # Generic PR receipt template
│   └── workflows/ci.yml                         # Generic CI workflow (stable check name: `ci`)
├── docs/setup.md                                # Branch protection, auto-merge, and labels guide
└── scripts/
    ├── init.sh                                  # Idempotent `template init` bootstrap script
    └── setup-labels.sh                          # Idempotent GitHub labels script (+ Linear note)
```
