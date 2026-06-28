#!/usr/bin/env bash
#
# security-review preflight check.
#
# Checks which tools are available and reports status. Always exits 0 - missing
# tools degrade coverage, they do not abort the review. The model reads this
# output and notes any degradation to the user upfront.
#
# Usage: preflight.sh
#
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_JSON="$SCRIPT_DIR/../../../.claude-plugin/plugin.json"

VERSION="?"
if command -v jq >/dev/null 2>&1 && [ -f "$PLUGIN_JSON" ]; then
  VERSION=$(jq -r '.version // "?"' "$PLUGIN_JSON" 2>/dev/null || echo "?")
fi

TODAY=$(date +%Y-%m-%d)
echo "🔒 security-review v${VERSION} · reviewed ${TODAY}"
echo ""
echo "Preflight check"
echo "---------------"

check() {
  local tool="$1"
  local note="$2"
  if command -v "$tool" >/dev/null 2>&1; then
    local ver
    ver=$("$tool" --version 2>/dev/null | head -1 || echo "")
    printf "  %-16s ✓  %s\n" "$tool" "$ver"
  else
    printf "  %-16s ✗  NOT FOUND — %s\n" "$tool" "$note"
  fi
}

check "rg"            "pattern scanner will fall back to grep (slower, less accurate)"
check "git"           "diff access unavailable; PR and branch review (Mode A) requires git"
check "gh"            "PR fetch by number (--pr=N) unavailable; paste the diff manually instead — install: brew install gh && gh auth login"
check "jq"            "version detection degraded; not required for scanning"
check "npm"           "Node.js A03 supply chain audit unavailable"
check "pip-audit"     "Python A03 supply chain audit unavailable — install: pip install pip-audit"
check "govulncheck"   "Go A03 supply chain audit unavailable — install: go install golang.org/x/vuln/cmd/govulncheck@latest"
check "bundler-audit" "Ruby A03 supply chain audit unavailable — install: gem install bundler-audit"
check "cargo-audit"   "Rust A03 supply chain audit unavailable — install: cargo install cargo-audit"
check "bun"           "Bun A03 supply chain audit unavailable"
check "uv"            "uv A03 supply chain audit unavailable"

echo ""
echo "Pattern scanner: $(command -v rg >/dev/null 2>&1 && echo 'ripgrep (full)' || echo 'grep fallback (degraded — install ripgrep for full coverage)')"
echo ""
echo "Missing tools reduce coverage but do not abort the review."
echo "The skill will note what could not be checked in the output."
