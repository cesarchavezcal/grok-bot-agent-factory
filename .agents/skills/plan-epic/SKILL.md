---
name: plan-epic
description: Planning-only orchestrator skill for epic issues that decomposes work into agent-labeled sub-issues, marks the final deploy issue, and verifies labels
---

# Plan Epic Orchestrator (`plan-epic`)

Planning-only orchestrator skill for high-level initiative tickets tagged with `epic` + `agent`.

---

## Workflow Overview

```
1. Intake & Scope Assessment (Configured epic_planner model from models.yml)
     ↓
2. Architecture & Ticket Slicing (wayfinder + to-spec + to-tickets)
     ↓
3. Create Sub-Issues in GitHub/Linear:
     ├─ Record each created issue number directly into an array
     ├─ Every created sub-issue MUST receive the 'agent' label
     └─ Exactly ONE sub-issue (the final one in sequence) receives the 'deploy' label
     ↓
4. Mandatory Post-Creation Verification Gate:
     ├─ Repair any missing 'agent' labels across all sub-issues
     ├─ Strip 'deploy' from all intermediate sub-issues if present
     ├─ Ensure 'deploy' is applied to the final sub-issue
     ├─ Re-inspect and verify: 100% have 'agent', intermediates lack 'deploy', final has 'deploy'
     └─ If any condition fails: hard exit non-zero (exit 1)
```

---

## Strict Planning-Only Invariant

- **NO Implementation Code**: Never modify application code, write feature implementations, create implementation branches, or open implementation pull requests during this skill.
- **Pure Decomposition**: The deliverable is a clear breakdown of vertical tracer-bullet sub-issues tracked in GitHub / Linear.
- **Precedence**: If an issue carries `epic` + `agent`, this skill takes precedence over `bug` and `feature`.

---

## Phase 1: Intake & Scope Assessment

- **Trigger**: Issue carries labels `epic` + `agent`.
- **Model Resolution (`models.yml`)**:
  - Read configured `epic_planner` model from [`models.yml`](../../../models.yml).
  - **Model Not Available Rule**: If the configured model is unavailable in the environment, **stop and tell the user immediately**. Do NOT use a fallback model, and do NOT retry.
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
1. **Initial Inspection & Agent Label Repair**:
   ```bash
   for NUM in "${CREATED_NUMBERS[@]}"; do
     LABELS_JSON=$(gh issue view "$NUM" --json labels --jq '[.labels[].name]')
     if ! echo "$LABELS_JSON" | grep -q '"agent"'; then
       echo "Repairing missing agent label on #$NUM..."
       gh issue edit "$NUM" --add-label "agent"
     fi
   done
   ```

2. **Deploy Label Repair**:
   ```bash
   FINAL_INDEX=$(( ${#CREATED_NUMBERS[@]} - 1 ))
   FINAL_NUM="${CREATED_NUMBERS[$FINAL_INDEX]}"

   # A. Strip 'deploy' from all intermediate sub-issues (0 to FINAL_INDEX - 1) if present
   for ((i=0; i<FINAL_INDEX; i++)); do
     NUM="${CREATED_NUMBERS[i]}"
     INTER_LABELS=$(gh issue view "$NUM" --json labels --jq '[.labels[].name]')
     if echo "$INTER_LABELS" | grep -q '"deploy"'; then
       echo "Removing erroneous deploy label from intermediate issue #$NUM..."
       gh issue edit "$NUM" --remove-label "deploy"
     fi
   done

   # B. Ensure the final sub-issue has the 'deploy' label
   FINAL_LABELS=$(gh issue view "$FINAL_NUM" --json labels --jq '[.labels[].name]')
   if ! echo "$FINAL_LABELS" | grep -q '"deploy"'; then
     echo "Adding deploy label to final sub-issue #$FINAL_NUM..."
     gh issue edit "$FINAL_NUM" --add-label "deploy"
   fi
   ```

3. **Strict Post-Repair Validation Gate**:
   ```bash
   FINAL_INDEX=$(( ${#CREATED_NUMBERS[@]} - 1 ))
   FINAL_NUM="${CREATED_NUMBERS[$FINAL_INDEX]}"

   # 1. 100% of sub-issues carry 'agent'
   for NUM in "${CREATED_NUMBERS[@]}"; do
     V_LABELS=$(gh issue view "$NUM" --json labels --jq '[.labels[].name]')
     if ! echo "$V_LABELS" | grep -q '"agent"'; then
       echo "FATAL: Sub-issue #$NUM is missing 'agent' label!" >&2
       exit 1
     fi
   done

   # 2. Intermediate sub-issues MUST NOT carry 'deploy'
   for ((i=0; i<FINAL_INDEX; i++)); do
     NUM="${CREATED_NUMBERS[i]}"
     V_LABELS=$(gh issue view "$NUM" --json labels --jq '[.labels[].name]')
     if echo "$V_LABELS" | grep -q '"deploy"'; then
       echo "FATAL: Intermediate sub-issue #$NUM carries 'deploy' label!" >&2
       exit 1
     fi
   done

   # 3. Final sub-issue MUST carry 'deploy'
   FINAL_V_LABELS=$(gh issue view "$FINAL_NUM" --json labels --jq '[.labels[].name]')
   if ! echo "$FINAL_V_LABELS" | grep -q '"deploy"'; then
     echo "FATAL: Final sub-issue #$FINAL_NUM is missing 'deploy' label!" >&2
     exit 1
   fi
   ```

4. Output the verified list of sub-issues with their issue numbers, titles, and labels in the thread final message.
