#!/usr/bin/env bash
# `template init` — Idempotent bootstrap script for Grok Bot Agent Factory projects.
# Safe to run multiple times without duplicate effects when creating or updating a repo from the template.
#
# Usage:
#   ./scripts/init.sh
#   ./scripts/init.sh --create-repo <owner/name-or-name>   # Creates a PUBLIC GitHub repo from current checkout if origin is missing

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

CREATE_REPO_NAME=""
if [ "${1:-}" = "--create-repo" ] && [ -n "${2:-}" ]; then
  CREATE_REPO_NAME="$2"
fi

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

# Optionally create the working repository as PUBLIC if requested and origin does not exist yet
if [ -n "$CREATE_REPO_NAME" ] && ! git remote get-url origin >/dev/null 2>&1; then
  echo ""
  echo "🌐 Creating PUBLIC working repository '$CREATE_REPO_NAME' on GitHub..."
  gh repo create "$CREATE_REPO_NAME" --public --source . --remote origin --push
fi

# ------------------------------------------------------------------------------
# 2. Install / restore official skills from skills-lock.json
# ------------------------------------------------------------------------------
echo ""
echo "📦 [2/5] Installing/updating official skills from skills-lock.json..."

NPM_CACHE_DIR="${NPM_CONFIG_CACHE:-/tmp/grok-bot-agent-factory-npm-cache}"

install_official_skills_fallback() {
  npm_config_cache="$NPM_CACHE_DIR" npx -y skills add mattpocock/skills --skill domain-modeling grilling tdd to-spec to-tickets wayfinder -y
  npm_config_cache="$NPM_CACHE_DIR" npx -y skills add https://github.com/mattpocock/skills/tree/e74f0061bb67222181640effa98c675bdb2fdaa7 --skill grill-with-docs -y
  npm_config_cache="$NPM_CACHE_DIR" npx -y skills add https://github.com/cursor/plugins/tree/main/pstack --skill poteto-mode -y
}

if [ -f "skills-lock.json" ]; then
  if npm_config_cache="$NPM_CACHE_DIR" npx -y skills experimental_install; then
    echo "  ✓ Official skills restored from skills-lock.json"
  else
    echo "  ⚠️ experimental_install fallback: installing pinned official skills directly..."
    install_official_skills_fallback
  fi
else
  echo "  ⚠️ skills-lock.json not found; installing official skills from source..."
  install_official_skills_fallback
fi

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
  echo "  ⚠️ No GitHub remote detected yet."
  echo "     To create a new PUBLIC working repo from the template, run:"
  echo "       gh repo create <name> --public --template cesarchavezcal/grok-bot-agent-factory --clone"
  echo "     Or from an existing local checkout:"
  echo "       ./scripts/init.sh --create-repo <name>"
fi

# ------------------------------------------------------------------------------
# 4. Configure GitHub merge settings & branch protection on `main`
# ------------------------------------------------------------------------------
echo ""
echo "🛡️  [4/5] Configuring repository merge policy & branch protection on 'main'..."

if [ -n "$REPO_SLUG" ]; then
  REPO_VISIBILITY="$(gh repo view "$REPO_SLUG" --json visibility --jq '.visibility' 2>/dev/null || echo "UNKNOWN")"
  echo "  ℹ️  Repository visibility: $REPO_VISIBILITY"

  # 4a. Enable allow_auto_merge, squash merge, and delete_branch_on_merge via gh api PATCH
  PATCH_ERR=""
  if PATCH_ERR="$(gh api --method PATCH "repos/$REPO_SLUG" \
    -F allow_auto_merge=true \
    -F allow_squash_merge=true \
    -F allow_merge_commit=false \
    -F allow_rebase_merge=false \
    -F delete_branch_on_merge=true 2>&1 >/dev/null)"; then
    echo "  ✓ Enabled allow_auto_merge, squash-only merge, and delete_branch_on_merge on $REPO_SLUG"
  else
    if echo "$PATCH_ERR" | grep -qiE "403|422|upgrade|private|auto-merge"; then
      echo "  ⚠️  EXPLICIT WARNING (Auto-Merge / Merge Settings):"
      echo "     GitHub rejected allow_auto_merge on '$REPO_SLUG' (visibility: $REPO_VISIBILITY)."
      echo "     GitHub Free does NOT allow auto-merge on PRIVATE repositories."
      echo "     Working repositories created from this template MUST be PUBLIC:"
      echo "       gh repo create <name> --public --template cesarchavezcal/grok-bot-agent-factory --clone"
      echo "     Or make an existing working repo public with:"
      echo "       gh repo edit $REPO_SLUG --visibility public --accept-visibility-change-consequences"
      # Still apply squash-only and delete_branch_on_merge even if allow_auto_merge requires public/Pro
      gh api --method PATCH "repos/$REPO_SLUG" \
        -F allow_squash_merge=true \
        -F allow_merge_commit=false \
        -F allow_rebase_merge=false \
        -F delete_branch_on_merge=true >/dev/null 2>&1 || true
    else
      echo "  ⚠️  Could not update merge settings on '$REPO_SLUG': $PATCH_ERR"
    fi
  fi

  # 4b. Configure branch protection on `main` with required status check `ci` via gh api PUT
  PROT_ERR=""
  if PROT_ERR="$(gh api --method PUT "repos/$REPO_SLUG/branches/main/protection" \
    --input - <<'EOF' 2>&1 >/dev/null
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
  )"; then
    echo "  ✓ Branch protection active on 'main' (required check: 'ci', strict up-to-date, conversation resolution, linear history)"
  else
    if echo "$PROT_ERR" | grep -qiE "403|Upgrade to GitHub Pro|make this repository public"; then
      echo "  ⚠️  EXPLICIT WARNING (Branch Protection on '$REPO_SLUG:main'):"
      echo "     GitHub API returned HTTP 403: Branch protection is unavailable on PRIVATE repositories under GitHub Free."
      echo "     (Note: the template 'cesarchavezcal/grok-bot-agent-factory' stays PRIVATE, so this warning is expected on the template itself.)"
      echo "     For any WORKING repository created from this template, create it as PUBLIC:"
      echo "       gh repo create <name> --public --template cesarchavezcal/grok-bot-agent-factory --clone"
      echo "     Or switch an existing working repo to PUBLIC and re-run ./scripts/init.sh:"
      echo "       gh repo edit $REPO_SLUG --visibility public --accept-visibility-change-consequences && ./scripts/init.sh"
    else
      echo "  ⚠️  Could not set branch protection on '$REPO_SLUG:main': $PROT_ERR"
    fi
  fi
else
  echo "  ⚠️ Skipping GitHub merge policy & branch protection until remote 'origin' is configured."
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
