#!/usr/bin/env bash
# `template init` — Idempotent bootstrap script for Grok Bot Agent Factory projects.
# Safe to run multiple times without duplicate effects when creating or updating a repo from the template.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "============================================================"
echo "🚀 Grok Bot Agent Factory — template init"
echo "============================================================"

# ------------------------------------------------------------------------------
# 1. Verify required tools & authentication
# ------------------------------------------------------------------------------
echo ""
echo "🔍 [1/5] Checking required tools..."

missing_tools=0
for cmd in git gh node npx; do
  if command -v "$cmd" >/dev/null 2>&1; then
    echo "  ✓ $cmd found ($(command -v "$cmd"))"
  else
    echo "  ❌ $cmd is NOT installed"
    missing_tools=1
  fi
done

if [ "$missing_tools" -ne 0 ]; then
  echo "❌ Please install the missing tools above and re-run ./scripts/init.sh"
  exit 1
fi

if gh auth status >/dev/null 2>&1; then
  echo "  ✓ gh CLI is authenticated"
else
  echo "  ❌ gh CLI is NOT authenticated. Run 'gh auth login' and re-run ./scripts/init.sh"
  exit 1
fi

# ------------------------------------------------------------------------------
# 2. Install / restore official skills from skills-lock.json
# ------------------------------------------------------------------------------
echo ""
echo "📦 [2/5] Installing/updating official skills from skills-lock.json..."

NPM_CACHE_DIR="${NPM_CONFIG_CACHE:-/tmp/grok-bot-agent-factory-npm-cache}"

if [ -f "skills-lock.json" ]; then
  if npm_config_cache="$NPM_CACHE_DIR" npx -y skills experimental_install; then
    echo "  ✓ Official skills restored from skills-lock.json"
  else
    echo "  ⚠️ experimental_install fallback: installing pinned official skills directly..."
    npm_config_cache="$NPM_CACHE_DIR" npx -y skills add mattpocock/skills --skill grill-with-docs grilling domain-modeling wayfinder to-spec to-tickets -y
    npm_config_cache="$NPM_CACHE_DIR" npx -y skills add https://github.com/cursor/plugins/tree/main/pstack --skill poteto-mode -y
  fi
else
  echo "  ⚠️ skills-lock.json not found; installing official skills from source..."
  npm_config_cache="$NPM_CACHE_DIR" npx -y skills add mattpocock/skills --skill grill-with-docs grilling domain-modeling wayfinder to-spec to-tickets -y
  npm_config_cache="$NPM_CACHE_DIR" npx -y skills add https://github.com/cursor/plugins/tree/main/pstack --skill poteto-mode -y
fi

# Verify local verify-app template exists in .agents/skills/verify-app
if [ -f ".agents/skills/verify-app/SKILL.md" ]; then
  echo "  ✓ .agents/skills/verify-app template present"
else
  echo "  ⚠️ Warning: .agents/skills/verify-app/SKILL.md is missing"
fi

# ------------------------------------------------------------------------------
# 3. Sync GitHub labels (including `agent`)
# ------------------------------------------------------------------------------
echo ""
echo "🏷️  [3/5] Configuring GitHub labels..."

REPO_SLUG=""
if git remote get-url origin >/dev/null 2>&1; then
  REPO_SLUG="$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null || true)"
fi

if [ -n "$REPO_SLUG" ]; then
  echo "  ✓ Detected GitHub repository: $REPO_SLUG"
  bash "$ROOT_DIR/scripts/setup-labels.sh" "$REPO_SLUG"
else
  echo "  ⚠️ No GitHub remote detected yet. Skipping remote label creation (re-run ./scripts/init.sh after adding origin)."
fi

# ------------------------------------------------------------------------------
# 4. Configure GitHub merge settings & branch protection on `main`
# ------------------------------------------------------------------------------
echo ""
echo "🛡️  [4/5] Configuring repository merge policy & branch protection on 'main'..."

if [ -n "$REPO_SLUG" ]; then
  # Enable squash merge, auto-merge, and automatic head branch deletion
  if gh repo edit "$REPO_SLUG" \
    --enable-squash-merge \
    --enable-auto-merge \
    --delete-branch-on-merge \
    --enable-merge-commit=false \
    --enable-rebase-merge=false >/dev/null 2>&1; then
    echo "  ✓ Enabled squash-only merge, allow auto-merge, and delete-branch-on-merge on $REPO_SLUG"
  else
    echo "  ⚠️ Could not update repo merge settings (check admin permissions on $REPO_SLUG)"
  fi

  # Configure branch protection on `main` with required status check `ci`
  if gh api --method PUT "repos/$REPO_SLUG/branches/main/protection" \
    --input - <<'EOF' >/dev/null 2>&1
{
  "required_status_checks": {
    "strict": true,
    "contexts": ["ci"]
  },
  "enforce_admins": false,
  "required_pull_request_reviews": null,
  "restrictions": null,
  "required_linear_history": true,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "required_conversation_resolution": true
}
EOF
  then
    echo "  ✓ Branch protection active on 'main' (required check: 'ci', strict up-to-date, conversation resolution, linear history)"
  else
    echo "  ⚠️ Could not set branch protection on '$REPO_SLUG:main' (ensure 'main' branch is pushed and your plan/permissions support branch protection)."
  fi
else
  echo "  ⚠️ Skipping GitHub branch protection until remote 'origin' is configured."
fi

# ------------------------------------------------------------------------------
# 5. T3 Code registration & .factory/config.json summary
# ------------------------------------------------------------------------------
echo ""
echo "🧭 [5/5] Project registration & factory config check..."

APP_NAME="$(basename "$ROOT_DIR")"
if [ -f ".factory/config.json" ]; then
  APP_NAME="$APP_NAME" node -e '
    const fs = require("fs");
    const file = ".factory/config.json";
    const cfg = JSON.parse(fs.readFileSync(file, "utf8"));
    const appSlug = process.env.APP_NAME;
    if (cfg.app === "app" && appSlug && appSlug !== "grok-bot-agent-factory") {
      cfg.app = appSlug;
      fs.writeFileSync(file, JSON.stringify(cfg, null, 2) + "\n", "utf8");
      console.log("  ✓ Updated .factory/config.json app slug to: " + appSlug);
    } else {
      console.log("  ✓ .factory/config.json validated (app: " + cfg.app + ", verifySkill: " + cfg.verifySkill + ")");
    }
  '
fi

echo ""
echo "ℹ️  T3 Code registration (optional when running inside T3 Code):"
echo "   If orchestrating from T3 Code MCP, register this workspace with:"
echo "   t3_project_create({ name: \"$APP_NAME\", path: \"$ROOT_DIR\" })"
echo ""
echo "✅ template init complete! Ready to process 'agent'-labeled issues."
