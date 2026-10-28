# Verification Map (Template)

Index of user-facing features verified by `verify-app` (or `verify-<app>`). Maintain one file per vertical feature slice.

## Baseline Preconditions

- Launch the app in an isolated environment (dedicated port and temporary data store per worktree).
- Run the doctor check first and refuse to drive a shared or unknown instance.

## Features

- Add one markdown file per feature here (`create-*.md`, `auth.md`, `search.md`, etc.) containing:
  1. **Sub-features & invariants**
  2. **How to reach it (user POV)**
  3. **Driving it with the harness (exact commands/selectors)**
  4. **Expected evidence & gotchas**
