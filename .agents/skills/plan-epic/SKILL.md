---
name: plan-epic
description: Planning-only orchestrator skill for epic issues that decomposes work into agent-labeled sub-issues, marks the final deploy issue, and verifies labels
---

# Plan Epic Orchestrator (`plan-epic`)

Planning-only orchestrator skill for high-level initiative tickets tagged with `epic` + `agent`.

---

## Workflow Overview

```
1. Intake & Scope Assessment (Gemini 3.8 Flash High)
     ↓
2. Architecture & Ticket Slicing (wayfinder + to-spec + to-tickets)
     ↓
3. Create Sub-Issues in GitHub/Linear:
     ├─ Every created sub-issue MUST receive the 'agent' label
     └─ Exactly ONE sub-issue (the final one in sequence) receives the 'deploy' label
     ↓
4. Mandatory Post-Creation Verification Gate:
     └─ Query and confirm 100% of created sub-issues have the 'agent' label attached before exiting
```

---

## Strict Planning-Only Invariant

- **NO Implementation Code**: Never modify application code, write feature implementations, create implementation branches, or open implementation pull requests during this skill.
- **Pure Decomposition**: The deliverable is a clear breakdown of vertical tracer-bullet sub-issues tracked in GitHub / Linear.

---

## Phase 1: Intake & Scope Assessment

- **Trigger**: Issue carries labels `epic` + `agent`.
- **Model**: `antigravity::gemini-3.8-flash-high` (`effort: high`).
- Parse the epic's objectives, acceptance criteria, and background context.
- Use [`wayfinder`](../wayfinder/SKILL.md) and [`grill-with-docs`](../grill-with-docs/SKILL.md) to locate relevant modules and align with existing architecture.
- If genuine scope ambiguities exist:
  - **NEVER comment on the issue or PR**.
  - Stop execution immediately and write questions in the **thread final message** for César via Grok Bot.

---

## Phase 2: Ticket Decomposition (`to-spec` + `to-tickets`)

- Break the epic down into sequential, vertical tracer-bullet sub-issues using [`to-tickets`](../to-tickets/SKILL.md).
- Each sub-issue must be independently testable, deliverable in a single PR, and reference the parent epic:
  - Title: `feat(<epic>): <tracer-bullet summary>` or `fix(<epic>): ...`
  - Body: Include context, requirements, acceptance criteria, and `Part of #<EPIC_NUMBER>`.
- Order the sub-issues chronologically: `Sub-issue 1`, `Sub-issue 2`, ..., `Sub-issue N`.

---

## Phase 3: Sub-Issue Creation & Label Rules

When creating sub-issues in GitHub (via `gh issue create`) or Linear:

1. **Mandatory `agent` Label**:
   - Every single sub-issue **MUST** be created with the **`agent`** label (plus `feature` or `bug`).
   - The `agent` label allows the factory dispatcher to ingest each sub-issue autonomously.
2. **Deploy Label Rule (Exactly One Sub-Issue)**:
   - Identify the **final sub-issue** in the dependency chain (the one that completes the epic).
   - Apply the **`deploy`** label to **exactly this one final sub-issue**.
   - Sub-issues `1` through `N-1` MUST NOT have the `deploy` label.
   - Note in the final sub-issue body:
     ```markdown
     Part of #<EPIC_NUMBER>
     Note: This is the final sub-issue of epic #<EPIC_NUMBER>. Merging this PR will trigger deployment and close the epic:
     Closes #<THIS_ISSUE_NUMBER>
     Closes #<EPIC_NUMBER>
     ```

---

## Phase 4: Mandatory Label Verification Gate

Before completing the skill:
1. Fetch all created sub-issues associated with the epic:
   ```bash
   gh issue list --search "Part of #<EPIC_NUMBER>" --json number,title,labels
   ```
2. Verify:
   - **Check 1**: Every sub-issue has the `agent` label attached.
   - **Check 2**: Exactly one sub-issue has the `deploy` label attached.
3. If any sub-issue is missing the `agent` label, immediately repair it:
   ```bash
   gh issue edit <SUB_ISSUE_NUMBER> --add-label "agent"
   ```
4. Output the verified list of sub-issues with their URLs and labels in the thread final message.
