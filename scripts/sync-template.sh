#!/usr/bin/env bash
# `sync-template.sh` — Pulls managed factory files from the private template
# repository (`cesarchavezcal/grok-bot-agent-factory`) into a derived working
# repository, records the synced template commit SHA in `.factory/template-version`,
# and opens a pull request if any managed files changed.
#
# Idempotent: prints a diff summary and creates NO branch or PR when nothing changed.
# Never modifies application code or `.factory/config.json` app settings.
#
# Usage:
#   ./scripts/sync-template.sh [options]
#
# Options:
#   --ref <git-ref>          Template branch, tag, or commit SHA to sync from (default: main)
#   --repo <owner/name>      Template repository (default: from .factory/template-sync.json)
#   --branch <branch-name>   Branch name to create (default: chore/template-sync-<short-sha>)
#   --base <base-branch>     Base branch in working repo (default: main)
#   --source-dir <path>      Optional local template checkout (for testing; skips gh repo clone)
#   --dry-run                Print diff summary and revert without creating a branch or PR
#   --allow-template-self    Allow running inside the template repo itself (used with --dry-run)
#   -h, --help               Show this help message

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

MANIFEST_FILE=".factory/template-sync.json"

usage() {
  sed -n '2,22p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

TEMPLATE_REPO=""
TARGET_REF=""
SYNC_BRANCH=""
BASE_BRANCH=""
SOURCE_DIR=""
DRY_RUN=0
ALLOW_SELF=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --ref)
      TARGET_REF="${2:-}"
      shift 2
      ;;
    --repo)
      TEMPLATE_REPO="${2:-}"
      shift 2
      ;;
    --branch)
      SYNC_BRANCH="${2:-}"
      shift 2
      ;;
    --base)
      BASE_BRANCH="${2:-}"
      shift 2
      ;;
    --source-dir)
      SOURCE_DIR="${2:-}"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --allow-template-self)
      ALLOW_SELF=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "❌ Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

echo "============================================================"
echo "🔄 Grok Bot Agent Factory — template sync"
echo "============================================================"

# ------------------------------------------------------------------------------
# 1. Verify required tools & clean working tree
# ------------------------------------------------------------------------------
for cmd in git gh node; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "❌ Required tool '$cmd' is not installed." >&2
    exit 1
  fi
done

if [ -z "$SOURCE_DIR" ]; then
  if ! gh auth status >/dev/null 2>&1; then
    echo "❌ gh CLI is not authenticated. Run 'gh auth login' to access the private template." >&2
    exit 1
  fi
fi

if [ ! -f "$MANIFEST_FILE" ]; then
  echo "❌ Manifest file '$MANIFEST_FILE' not found in $(pwd)." >&2
  exit 1
fi

# Read defaults from local .factory/template-sync.json and .factory/config.json
eval "$(node -e '
  const fs = require("fs");
  const manifest = JSON.parse(fs.readFileSync(".factory/template-sync.json", "utf8"));
  let baseBranch = "main";
  if (fs.existsSync(".factory/config.json")) {
    try {
      const cfg = JSON.parse(fs.readFileSync(".factory/config.json", "utf8"));
      if (cfg.baseBranch) baseBranch = cfg.baseBranch;
    } catch (_) {}
  }
  console.log("DEFAULT_TEMPLATE_REPO=" + JSON.stringify(manifest.templateRepo || "cesarchavezcal/grok-bot-agent-factory"));
  console.log("DEFAULT_REF=" + JSON.stringify(manifest.defaultRef || "main"));
  console.log("VERSION_FILE=" + JSON.stringify(manifest.versionFile || ".factory/template-version"));
  console.log("DEFAULT_BASE_BRANCH=" + JSON.stringify(baseBranch));
')"

TEMPLATE_REPO="${TEMPLATE_REPO:-$DEFAULT_TEMPLATE_REPO}"
TARGET_REF="${TARGET_REF:-$DEFAULT_REF}"
BASE_BRANCH="${BASE_BRANCH:-$DEFAULT_BASE_BRANCH}"

if [ -n "$(git status --porcelain)" ]; then
  echo "❌ Working tree has uncommitted changes. Please commit or stash them before running sync-template.sh." >&2
  git status --short >&2
  exit 1
fi

CURRENT_REPO=""
if git remote get-url origin >/dev/null 2>&1; then
  ORIGIN_URL="$(git remote get-url origin)"
  if [[ "$ORIGIN_URL" =~ github\.com[:/]([^/]+/[^/.]+)(\.git)?$ ]]; then
    CURRENT_REPO="${BASH_REMATCH[1]}"
  else
    CURRENT_REPO="$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null || true)"
  fi
fi

if [ "$CURRENT_REPO" = "$TEMPLATE_REPO" ] && [ "$ALLOW_SELF" -eq 0 ] && [ "$DRY_RUN" -eq 0 ]; then
  echo "❌ Current repository IS the template repository ($TEMPLATE_REPO)." >&2
  echo "   Run this script inside a derived working repository (or pass --dry-run / --allow-template-self)." >&2
  exit 1
fi

PREV_VERSION="none"
if [ -f "$VERSION_FILE" ]; then
  PREV_VERSION="$(tr -d '[:space:]' < "$VERSION_FILE")"
fi

# ------------------------------------------------------------------------------
# 2. Fetch private template repository via `gh` (or use --source-dir)
# ------------------------------------------------------------------------------
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/template-sync.XXXXXX")"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

TEMPLATE_DIR="$TMP_DIR/template"

if [ -n "$SOURCE_DIR" ]; then
  if [ ! -d "$SOURCE_DIR" ]; then
    echo "❌ --source-dir '$SOURCE_DIR' does not exist." >&2
    exit 1
  fi
  echo "📂 Using local template source: $SOURCE_DIR"
  mkdir -p "$TEMPLATE_DIR"
  tar -C "$SOURCE_DIR" -cf - . | tar -C "$TEMPLATE_DIR" -xf -
  if [ -d "$TEMPLATE_DIR/.git" ] && [ -n "$TARGET_REF" ]; then
    git -C "$TEMPLATE_DIR" checkout --quiet "$TARGET_REF" 2>/dev/null || true
  fi
else
  echo "📥 Fetching private template '$TEMPLATE_REPO' (ref: '$TARGET_REF') via gh auth..."
  gh repo clone "$TEMPLATE_REPO" "$TEMPLATE_DIR" -- --quiet
  git -C "$TEMPLATE_DIR" checkout --quiet "$TARGET_REF"
fi

TEMPLATE_SHA="$(git -C "$TEMPLATE_DIR" rev-parse HEAD)"
SHORT_SHA="$(git -C "$TEMPLATE_DIR" rev-parse --short=7 HEAD)"

echo "  ✓ Template resolved: $TEMPLATE_REPO @ $TARGET_REF ($SHORT_SHA / $TEMPLATE_SHA)"
echo "  ℹ️  Previous synced version: $PREV_VERSION"

# ------------------------------------------------------------------------------
# 3. Copy managed paths from template (preserving app code & local config)
# ------------------------------------------------------------------------------
ACTIVE_MANIFEST="$MANIFEST_FILE"
if [ -f "$TEMPLATE_DIR/$MANIFEST_FILE" ]; then
  ACTIVE_MANIFEST="$TEMPLATE_DIR/$MANIFEST_FILE"
fi

echo ""
echo "📋 Syncing managed paths from manifest ($MANIFEST_FILE)..."

TEMPLATE_DIR="$TEMPLATE_DIR" WORK_DIR="$ROOT_DIR" ACTIVE_MANIFEST="$ACTIVE_MANIFEST" node -e '
  const fs = require("fs");
  const path = require("path");

  const templateDir = process.env.TEMPLATE_DIR;
  const workDir = process.env.WORK_DIR;
  const manifestPath = process.env.ACTIVE_MANIFEST;
  const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));

  const managedPaths = manifest.managedPaths || [];
  const preserveLocalPaths = new Set(manifest.preserveLocalPaths || []);

  // Save preserved local paths in memory if they exist so we never clobber them
  const preservedBackups = new Map();
  for (const rel of preserveLocalPaths) {
    const full = path.join(workDir, rel);
    if (fs.existsSync(full)) {
      preservedBackups.set(rel, {
        isDir: fs.statSync(full).isDirectory(),
        tempBackup: null
      });
    }
  }

  function copyRecursive(src, dest, relFromRoot) {
    if (preserveLocalPaths.has(relFromRoot) && fs.existsSync(dest)) {
      return;
    }
    const stat = fs.lstatSync(src);
    if (stat.isDirectory()) {
      fs.mkdirSync(dest, { recursive: true });
      for (const entry of fs.readdirSync(src)) {
        if (entry === ".git") continue;
        const childRel = relFromRoot ? path.posix.join(relFromRoot, entry) : entry;
        copyRecursive(path.join(src, entry), path.join(dest, entry), childRel);
      }
    } else if (stat.isSymbolicLink()) {
      const linkTarget = fs.readlinkSync(src);
      fs.mkdirSync(path.dirname(dest), { recursive: true });
      if (fs.existsSync(dest)) fs.unlinkSync(dest);
      fs.symlinkSync(linkTarget, dest);
    } else {
      fs.mkdirSync(path.dirname(dest), { recursive: true });
      fs.copyFileSync(src, dest);
      fs.chmodSync(dest, stat.mode);
    }
  }

  for (const pattern of managedPaths) {
    console.log("  • " + pattern);
    if (pattern.endsWith("/*")) {
      const parentRel = pattern.slice(0, -2);
      const srcParent = path.join(templateDir, parentRel);
      if (!fs.existsSync(srcParent)) continue;
      for (const entry of fs.readdirSync(srcParent)) {
        if (entry === ".git") continue;
        const childRel = path.posix.join(parentRel, entry);
        copyRecursive(
          path.join(srcParent, entry),
          path.join(workDir, parentRel, entry),
          childRel
        );
      }
    } else {
      const srcPath = path.join(templateDir, pattern);
      if (!fs.existsSync(srcPath)) continue;
      copyRecursive(srcPath, path.join(workDir, pattern), pattern);
    }
  }
'

# ------------------------------------------------------------------------------
# 4. Check idempotency & print diff summary (excluding version file first)
# ------------------------------------------------------------------------------
MANAGED_CHANGES="$(git status --porcelain)"

if [ -z "$MANAGED_CHANGES" ]; then
  echo ""
  echo "✅ All managed files are already up to date with $TEMPLATE_REPO @ $SHORT_SHA."
  echo "   No branch or PR created."
  exit 0
fi

# Record the synced template commit SHA in .factory/template-version
mkdir -p "$(dirname "$VERSION_FILE")"
printf "%s\n" "$TEMPLATE_SHA" > "$VERSION_FILE"

echo ""
echo "📊 Diff Summary ($PREV_VERSION -> $SHORT_SHA):"
echo "------------------------------------------------------------"
git status --short
echo "------------------------------------------------------------"
git diff --stat
echo "------------------------------------------------------------"

if [ "$DRY_RUN" -eq 1 ]; then
  echo ""
  echo "🧪 Dry run complete (--dry-run). Reverting working tree changes without creating a branch or PR."
  git checkout -- .
  git clean -fd
  exit 0
fi

# ------------------------------------------------------------------------------
# 5. Create sync branch, commit, push, and open PR
# ------------------------------------------------------------------------------
SYNC_BRANCH="${SYNC_BRANCH:-chore/template-sync-$SHORT_SHA}"

echo ""
echo "🌿 Preparing branch '$SYNC_BRANCH'..."
git checkout -B "$SYNC_BRANCH"

git add -A
git commit -m "chore(template): sync factory template @ $SHORT_SHA"

echo "🚀 Pushing '$SYNC_BRANCH' to origin..."
git push -u origin "$SYNC_BRANCH" --force-with-lease

PR_TITLE="chore(template): sync factory template @ $SHORT_SHA"
PR_BODY="$(cat <<EOF
## Summary
Automated template sync from \`$TEMPLATE_REPO\` (\`$TARGET_REF\` @ \`$TEMPLATE_SHA\`).

- **Previous template version**: \`$PREV_VERSION\`
- **New template version**: \`$TEMPLATE_SHA\` (\`$SHORT_SHA\`)
- **Manifest**: [\`.factory/template-sync.json\`](.factory/template-sync.json)
- **Version file**: [\`.factory/template-version\`](.factory/template-version)

## Managed Paths Synced
$(node -e '
  const fs = require("fs");
  const m = JSON.parse(fs.readFileSync(".factory/template-sync.json", "utf8"));
  for (const p of m.managedPaths || []) console.log("- `" + p + "`");
')
EOF
)"

EXISTING_PR_URL="$(gh pr list --head "$SYNC_BRANCH" --base "$BASE_BRANCH" --state open --json url --jq '.[0].url // empty' 2>/dev/null || true)"

if [ -n "$EXISTING_PR_URL" ]; then
  echo "  ✓ Updated existing Pull Request: $EXISTING_PR_URL"
  gh pr edit "$EXISTING_PR_URL" --title "$PR_TITLE" --body "$PR_BODY" >/dev/null
  PR_URL="$EXISTING_PR_URL"
else
  PR_URL="$(gh pr create --base "$BASE_BRANCH" --head "$SYNC_BRANCH" --title "$PR_TITLE" --body "$PR_BODY")"
  echo "  ✓ Opened Pull Request: $PR_URL"
fi

echo ""
echo "✅ Template sync complete: $PR_URL"
