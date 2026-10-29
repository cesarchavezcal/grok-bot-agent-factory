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
     ├─ Record each created issue number directly
     ├─ Every created sub-issue MUST receive the 'agent' label
     └─ Exactly ONE sub-issue (the final one in sequence) receives the 'deploy' label
     ↓
4. Mandatory Post-Creation Verification Gate:
     ├─ Inspect each created issue via `gh issue view`
     ├─ Verify 100% of created sub-issues have 'agent' (auto-repair if missing)
     └─ Verify exactly 1 sub-issue has 'deploy' (hard fail & repair if count != 1)
```

---

## Strict Planning-Only Invariant

- **NO Implementation Code**: Never modify application code, write feature implementations, create implementation branches, or open implementation pull requests during this skill.
- **Pure Decomposition**: The deliverable is a clear breakdown of vertical tracer-bullet sub-issues tracked in GitHub / Linear.
- **Precedence**: If an issue carries `epic` + `agent`, this skill takes precedence over `bug` and `feature`.

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
- **PR Closing Instructions for Sub-Issues**:
  - Intermediate sub-issues (`1` to `N-1`): PR body MUST use `Closes #<SUB_ISSUE_NUMBER>`.
  - Final deploy sub-issue (`N`): PR body MUST use BOTH:
    ```markdown
    Closes #<SUB_ISSUE_NUMBER>
    Closes #<EPIC_NUMBER>
    ```

---

## Phase 3: Sub-Issue Creation & Label Rules

When creating sub-issues in GitHub (via `gh issue create`):

1. **Capture Issue Numbers Directly**:
   - Do NOT rely on delayed GitHub search queries.
   - Capture the issue URL or number returned by each `gh issue create` call:
     ```bash
     CREATED_NUMBERS=()
     # For intermediate sub-issues (1 to N-1):
     ISSUE_URL=$(gh issue create --title "..." --body "..." --label "agent,feature")
     CREATED_NUMBERS+=($(basename "$ISSUE_URL"))
     ```
2. **Deploy Label Rule (Exactly One Sub-Issue)**:
   - Identify the **final sub-issue** in the dependency chain (the one that completes the epic).
   - Apply the **`deploy`** label at creation to **exactly this one final sub-issue**:
     ```bash
     FINAL_URL=$(gh issue create --title "..." --body "..." --label "agent,feature,deploy")
     CREATED_NUMBERS+=($(basename "$FINAL_URL"))
     ```
   - Sub-issues `1` through `N-1` MUST NOT have the `deploy` label.

---

## Phase 4: Mandatory Label Verification Gate

Before completing the skill:
1. For every created issue number `$NUM` in `${CREATED_NUMBERS[@]}`:
   ```bash
   LABELS_JSON=$(gh issue view "$NUM" --json labels --jq '[.labels[].name]')
   ```
2. **Check 1: `agent` Label**:
   - Verify that `"agent"` is present in `$LABELS_JSON`.
   - If missing, immediately repair:
     ```bash
     gh issue edit "$NUM" --add-label "agent"
     ```
3. **Check 2: `deploy` Label Count**:
   - Count how many sub-issues in `${CREATED_NUMBERS[@]}` carry the `"deploy"` label.
   - If `deploy_count === 1`: verification passes.
   - If `deploy_count !== 1`:
     - If `deploy_count === 0`: add `deploy` to the final sub-issue (`gh issue edit "${CREATED_NUMBERS[-1]}" --add-label "deploy"`).
     - If `deploy_count > 1`: remove `deploy` from all except the final sub-issue.
4. Output the verified list of sub-issues with their issue numbers, titles, and labels in the thread final message.
