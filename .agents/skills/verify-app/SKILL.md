---
name: verify-app
description: Stub verification skill. Copy to .agents/skills/verify-<app> when initializing a project. Drive the real user surface, capture runtime evidence, and clean up without deleting proof.
---

# Verify app (template)

Replace every placeholder before using this as runtime proof. Read `features/README.md` first.

**App:** `<app>`  
**Surface:** `<web | cli | api>`  
**Harness:** `<playwright | curl | pty>`

## Launch

Exact command that starts a disposable instance on an isolated port/data directory, and the ready signal (log line or health URL). Include teardown.

```bash
# TODO: disposable launch command (isolated port / data dir)
```

## Doctor

Read-only check: process up, expected URL or binary, data dir owned by this run. Refuse to drive a shared or unknown instance.

```bash
# TODO: doctor command
```

## Drive

Stable handles only (ARIA roles/labels, data attributes, CLI flags, HTTP routes). Pair each user action with a command and an observable result. Feature recipes live in `features/`.

## Evidence

Write `artifacts/<work-item-id>/`. Capture the action and the resulting state:
- **UI**: ARIA snapshot + screenshot.
- **CLI / API**: stdout, stderr, HTTP status, and exit code (`0`).
- **Mutations**: a second read-only check proving persisted state.

## Cleanup

Kill only the PID or process this run started. Remove temporary fixture data. **Keep `artifacts/<work-item-id>/`.**
