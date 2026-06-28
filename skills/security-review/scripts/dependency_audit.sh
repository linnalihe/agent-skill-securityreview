#!/usr/bin/env bash
#
# A03 Software Supply Chain Failures - runs the right native audit tool per ecosystem,
# detected from manifest/lockfiles present in the target directory.
#
# Usage: dependency_audit.sh [path]
#
# When a tool is missing this script emits a structured "A03 TOOL MISSING:" line the
# model can pass through to the report rather than silently skipping the ecosystem.
#
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_JSON="$SCRIPT_DIR/../../../.claude-plugin/plugin.json"

# --- Badge (first line of output per LAW 0) ---
VERSION="?"
if command -v jq >/dev/null 2>&1 && [ -f "$PLUGIN_JSON" ]; then
  VERSION=$(jq -r '.version // "?"' "$PLUGIN_JSON" 2>/dev/null || echo "?")
fi
TODAY=$(date +%Y-%m-%d)
echo "🔒 security-review v${VERSION} · reviewed ${TODAY}"
echo ""

TARGET="${1:-.}"

have() { command -v "$1" >/dev/null 2>&1; }

tool_missing() {
  local ecosystem="$1"
  local tool="$2"
  local install="$3"
  echo "A03 TOOL MISSING: $tool not on PATH — $ecosystem supply chain audit skipped."
  echo "  Install with: $install"
  echo "  Note this explicitly in the report rather than treating it as 'no findings'."
}

echo "Scanning $TARGET for dependency manifests..."
echo ""
FOUND_ANY=0

# --- Node / npm ---
if [ -f "$TARGET/package.json" ]; then
  FOUND_ANY=1
  echo "=== Node.js detected (package.json) ==="
  if [ ! -f "$TARGET/package-lock.json" ] && [ ! -f "$TARGET/yarn.lock" ] && \
     [ ! -f "$TARGET/pnpm-lock.yaml" ] && [ ! -f "$TARGET/bun.lockb" ]; then
    echo "FINDING (A03): no lockfile committed - builds are not reproducible and versions can drift."
  fi
  if have npm; then
    (cd "$TARGET" && npm audit --omit=dev 2>&1) || echo "(npm audit reported findings or failed - see output above)"
  else
    tool_missing "Node.js" "npm" "install Node.js from nodejs.org"
  fi
  echo ""
fi

# --- Bun ---
if [ -f "$TARGET/bun.lockb" ]; then
  FOUND_ANY=1
  echo "=== Bun detected (bun.lockb) ==="
  if have bun; then
    (cd "$TARGET" && bun audit 2>&1) || echo "(bun audit reported findings or failed - see output above)"
  else
    tool_missing "Bun" "bun" "curl -fsSL https://bun.sh/install | bash"
  fi
  echo ""
fi

# --- Python (requirements.txt / pyproject.toml / Pipfile) ---
if [ -f "$TARGET/requirements.txt" ] || [ -f "$TARGET/pyproject.toml" ] || [ -f "$TARGET/Pipfile" ]; then
  FOUND_ANY=1
  echo "=== Python detected ==="

  # uv preferred over pip-audit when uv.lock is present
  if [ -f "$TARGET/uv.lock" ] && have uv; then
    echo "Using uv (uv.lock detected)..."
    (cd "$TARGET" && uv pip audit 2>&1) || echo "(uv pip audit reported findings or failed - see above)"
  elif have pip-audit; then
    if [ -f "$TARGET/requirements.txt" ]; then
      (cd "$TARGET" && pip-audit -r requirements.txt 2>&1)
    else
      (cd "$TARGET" && pip-audit 2>&1)
    fi
  else
    tool_missing "Python" "pip-audit" "pip install pip-audit"
  fi

  if [ -f "$TARGET/requirements.txt" ] && grep -qvE '==' "$TARGET/requirements.txt" 2>/dev/null; then
    echo "FINDING (A03): requirements.txt has unpinned versions - pin exact versions for reproducible, auditable builds."
  fi
  echo ""
fi

# --- uv (uv.lock without pyproject.toml catch-all) ---
if [ -f "$TARGET/uv.lock" ] && [ ! -f "$TARGET/pyproject.toml" ] && [ ! -f "$TARGET/requirements.txt" ]; then
  FOUND_ANY=1
  echo "=== uv project detected (uv.lock) ==="
  if have uv; then
    (cd "$TARGET" && uv pip audit 2>&1) || echo "(uv pip audit reported findings or failed - see above)"
  else
    tool_missing "uv" "uv" "curl -LsSf https://astral.sh/uv/install.sh | sh"
  fi
  echo ""
fi

# --- Go ---
if [ -f "$TARGET/go.mod" ]; then
  FOUND_ANY=1
  echo "=== Go detected (go.mod) ==="
  if have govulncheck; then
    (cd "$TARGET" && govulncheck ./... 2>&1)
  else
    tool_missing "Go" "govulncheck" "go install golang.org/x/vuln/cmd/govulncheck@latest"
  fi
  echo ""
fi

# --- Ruby ---
if [ -f "$TARGET/Gemfile.lock" ]; then
  FOUND_ANY=1
  echo "=== Ruby detected (Gemfile.lock) ==="
  if have bundler-audit; then
    (cd "$TARGET" && bundler-audit check --update 2>&1)
  else
    tool_missing "Ruby" "bundler-audit" "gem install bundler-audit"
  fi
  echo ""
fi

# --- Java / Maven ---
if [ -f "$TARGET/pom.xml" ]; then
  FOUND_ANY=1
  echo "=== Java/Maven detected (pom.xml) ==="
  echo "Recommend: mvn org.owasp:dependency-check-maven:check"
  echo "(not run automatically here - requires network access to the NVD feed)"
  echo ""
fi

# --- Java / Gradle ---
if [ -f "$TARGET/build.gradle" ] || [ -f "$TARGET/build.gradle.kts" ]; then
  FOUND_ANY=1
  echo "=== Java/Gradle detected ==="
  echo "Recommend: the OWASP Dependency-Check Gradle plugin, or 'gradle dependencyCheckAnalyze'"
  echo ""
fi

# --- Rust ---
if [ -f "$TARGET/Cargo.lock" ]; then
  FOUND_ANY=1
  echo "=== Rust detected (Cargo.lock) ==="
  if have cargo-audit; then
    (cd "$TARGET" && cargo audit 2>&1)
  else
    tool_missing "Rust" "cargo-audit" "cargo install cargo-audit"
  fi
  echo ""
fi

if [ "$FOUND_ANY" -eq 0 ]; then
  echo "No dependency manifests found in $TARGET."
  echo "If manifests exist in subdirectories, pass the subdirectory path explicitly."
fi

echo "================ Done ================"
echo "Any 'A03 TOOL MISSING' lines above must appear in the report - do not treat missing"
echo "tools as 'no findings'. The audit is incomplete where a tool was unavailable."
