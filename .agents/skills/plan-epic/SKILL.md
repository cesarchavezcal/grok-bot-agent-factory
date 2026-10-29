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
     ├─ Record each created issue number directly into an array
     ├─ Every created sub-issue MUST receive the 'agent' label
     └─ Exactly ONE sub-issue (the final one in sequence) receives the 'deploy' label
     ↓
4. Mandatory Post-Creation Verification Gate:
     ├─ Inspect each created issue via `gh issue view`
     ├─ Repair any missing 'agent' or invalid 'deploy' counts
     ├─ Re-inspect and verify: 100% have 'agent', exactly 1 has 'deploy'
     └─ If verification fails after repair: hard exit non-zero (exit 1)
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

When creating sub-issues in GitHub (via `gh issue create`) or Linear:

1. **Capture Issue Numbers Directly**:
   - Capture the issue number directly from each issue creation call:
     ```bash
     CREATED_NUMBERS=()
     # For intermediate sub-issues (1 to N-1):
     ISSUE_URL=$(gh issue create --title "..." --body "..." --label "agent,feature")
     CREATED_NUMBERS+=("$(basename "$ISSUE_URL")")
     ```
   - For Linear issues, create sub-issues via the Linear integration/dispatcher, apply the `agent` label to each, apply `deploy` to the final one, and record their identifiers.
2. **Deploy Label Rule (Exactly One Sub-Issue)**:
   - Identify the **final sub-issue** in the dependency chain (the one that completes the epic).
   - Apply the **`deploy`** label at creation to **exactly this one final sub-issue**:
     ```bash
     FINAL_URL=$(gh issue create --title "..." --body "..." --label "agent,feature,deploy")
     CREATED_NUMBERS+=("$(basename "$FINAL_URL")")
     ```
   - Sub-issues `1` through `N-1` MUST NOT have the `deploy` label.

---

## Phase 4: Mandatory Label Verification Gate

Before completing the skill:
1. **Initial Inspection**:
   ```bash
   DEPLOY_COUNT=0
   for NUM in "${CREATED_NUMBERS[@]}"; do
     LABELS_JSON=$(gh issue view "$NUM" --json labels --jq '[.labels[].name]')
     if ! echo "$LABELS_JSON" | grep -q '"agent"'; then
       echo "Repairing missing agent label on #$NUM..."
       gh issue edit "$NUM" --add-label "agent"
     fi
     if echo "$LABELS_JSON" | grep -q '"deploy"'; then
       DEPLOY_COUNT=$(( DEPLOY_COUNT + 1 ))
     fi
   done
   ```
2. **Deploy Label Repair**:
   - If `DEPLOY_COUNT === 0`: Add `deploy` to the final sub-issue (using bash 3.2-compatible index):
     ```bash
     FINAL_INDEX=$(( ${#CREATED_NUMBERS[@]} - 1 ))
     FINAL_NUM="${CREATED_NUMBERS[$FINAL_INDEX]}"
     echo "Repairing missing deploy label on final issue #$FINAL_NUM..."
     gh issue edit "$FINAL_NUM" --add-label "deploy"
     ```
   - If `DEPLOY_COUNT > 1`: Strip `deploy` from all intermediate sub-issues:
     ```bash
     FINAL_INDEX=$(( ${#CREATED_NUMBERS[@]} - 1 ))
     for ((i=0; i<FINAL_INDEX; i++)); do
       NUM="${CREATED_NUMBERS[i]}"
       gh issue edit "$NUM" --remove-label "deploy"
     done
     ```
3. **Strict Post-Repair Validation Gate**:
   - Re-inspect every issue in `${CREATED_NUMBERS[@]}` to ensure 100% compliance:
     ```bash
     VERIFIED_DEPLOY=0
     for NUM in "${CREATED_NUMBERS[@]}"; do
       VERIFIED_LABELS=$(gh issue view "$NUM" --json labels --jq '[.labels[].name]')
       if ! echo "$VERIFIED_LABELS" | grep -q '"agent"'; then
         echo "FATAL: Sub-issue #$NUM is still missing 'agent' label!" >&2
         exit 1
       fi
       if echo "$VERIFIED_LABELS" | grep -q '"deploy"'; then
         VERIFIED_DEPLOY=$(( VERIFIED_DEPLOY + 1 ))
       fi
     done

     if [ "$VERIFIED_DEPLOY" -ne 1 ]; then
       echo "FATAL: Expected exactly 1 deploy label, found $VERIFIED_DEPLOY!" >&2
       exit 1
     fi
     ```
4. Output the verified list of sub-issues with their issue numbers, titles, and labels in the thread final message.
