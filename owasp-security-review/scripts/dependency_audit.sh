#!/usr/bin/env bash
#
# A03 Software Supply Chain Failures - runs the right native audit tool per ecosystem,
# detected from manifest/lockfiles present in the target directory.
#
# Usage: dependency_audit.sh [path]
#
set -uo pipefail
TARGET="${1:-.}"

have() { command -v "$1" >/dev/null 2>&1; }

echo "Scanning $TARGET for dependency manifests..."
echo

# --- Node / npm / yarn / pnpm ---
if [ -f "$TARGET/package.json" ]; then
  echo "=== Node.js detected (package.json) ==="
  if [ ! -f "$TARGET/package-lock.json" ] && [ ! -f "$TARGET/yarn.lock" ] && [ ! -f "$TARGET/pnpm-lock.yaml" ]; then
    echo "FINDING (A03): no lockfile committed - builds are not reproducible and versions can drift."
  fi
  if have npm; then
    (cd "$TARGET" && npm audit --omit=dev 2>&1) || echo "(npm audit reported findings or failed - see output above)"
  else
    echo "npm not available in this environment - run 'npm audit' where Node is installed."
  fi
  echo
fi

# --- Python ---
if [ -f "$TARGET/requirements.txt" ] || [ -f "$TARGET/pyproject.toml" ] || [ -f "$TARGET/Pipfile" ]; then
  echo "=== Python detected ==="
  if have pip-audit; then
    if [ -f "$TARGET/requirements.txt" ]; then
      (cd "$TARGET" && pip-audit -r requirements.txt 2>&1)
    else
      (cd "$TARGET" && pip-audit 2>&1)
    fi
  else
    echo "pip-audit not installed. Install with: pip install pip-audit --break-system-packages"
  fi
  if [ -f "$TARGET/requirements.txt" ] && grep -qvE '==' "$TARGET/requirements.txt" 2>/dev/null; then
    echo "FINDING (A03): requirements.txt has unpinned versions - pin exact versions for reproducible, auditable builds."
  fi
  echo
fi

# --- Go ---
if [ -f "$TARGET/go.mod" ]; then
  echo "=== Go detected (go.mod) ==="
  if have govulncheck; then
    (cd "$TARGET" && govulncheck ./... 2>&1)
  else
    echo "govulncheck not installed. Install with: go install golang.org/x/vuln/cmd/govulncheck@latest"
  fi
  echo
fi

# --- Ruby ---
if [ -f "$TARGET/Gemfile.lock" ]; then
  echo "=== Ruby detected (Gemfile.lock) ==="
  if have bundler-audit; then
    (cd "$TARGET" && bundler-audit check --update 2>&1)
  else
    echo "bundler-audit not installed. Install with: gem install bundler-audit"
  fi
  echo
fi

# --- Java / Maven ---
if [ -f "$TARGET/pom.xml" ]; then
  echo "=== Java/Maven detected (pom.xml) ==="
  echo "Recommend: mvn org.owasp:dependency-check-maven:check"
  echo "(not run automatically here - requires network access to the NVD feed)"
  echo
fi

# --- Java / Gradle ---
if [ -f "$TARGET/build.gradle" ] || [ -f "$TARGET/build.gradle.kts" ]; then
  echo "=== Java/Gradle detected ==="
  echo "Recommend: the OWASP Dependency-Check Gradle plugin, or 'gradle dependencyCheckAnalyze'"
  echo
fi

# --- Rust ---
if [ -f "$TARGET/Cargo.lock" ]; then
  echo "=== Rust detected (Cargo.lock) ==="
  if have cargo-audit; then
    (cd "$TARGET" && cargo audit 2>&1)
  else
    echo "cargo-audit not installed. Install with: cargo install cargo-audit"
  fi
  echo
fi

echo "================ Done ================"
echo "If a tool above wasn't available, note that explicitly in the report rather than silently"
echo "skipping the category - A03 findings need a real audit tool's output, not a guess."
