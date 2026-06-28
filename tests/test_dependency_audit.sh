#!/usr/bin/env bash
#
# Dependency audit regression tests. All tests run offline — they verify structural
# behaviour (badge, tool-missing lines, manifest detection, pinning check) without
# requiring npm audit, pip-audit, or any network call.
#
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUDIT_SCRIPT="$SCRIPT_DIR/../skills/security-review/scripts/dependency_audit.sh"
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

PASS=0
FAIL=0

check() {
  local label="$1"
  local output="$2"
  local pattern="$3"

  if echo "$output" | grep -qF "$pattern"; then
    echo "PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $label"
    echo "  Expected to find: '$pattern'"
    echo "  First 5 lines of output:"
    echo "$output" | head -5 | sed 's/^/    /'
    FAIL=$((FAIL + 1))
  fi
}

check_absent() {
  local label="$1"
  local output="$2"
  local pattern="$3"

  if echo "$output" | grep -qF "$pattern"; then
    echo "FAIL: $label — pattern should be absent: '$pattern'"
    FAIL=$((FAIL + 1))
  else
    echo "PASS: $label"
    PASS=$((PASS + 1))
  fi
}

echo "Running dependency audit tests..."
echo ""

# --- Badge emission ---
EMPTY_DIR="$WORK_DIR/empty"
mkdir -p "$EMPTY_DIR"
BADGE_OUT=$(bash "$AUDIT_SCRIPT" "$EMPTY_DIR" 2>/dev/null)
check "badge emitted as first line" "$(echo "$BADGE_OUT" | head -1)" "🔒 security-review v"

# --- No manifests path ---
NO_MANIFEST_OUT=$(bash "$AUDIT_SCRIPT" "$EMPTY_DIR" 2>/dev/null)
check "no manifests message when directory is empty" "$NO_MANIFEST_OUT" "No dependency manifests found"

# --- Done footer always present ---
check "done footer always present" "$NO_MANIFEST_OUT" "Done"

# --- Node.js: npm TOOL MISSING when npm not on PATH ---
NODE_DIR="$WORK_DIR/node_project"
mkdir -p "$NODE_DIR"
cat > "$NODE_DIR/package.json" <<'JSON'
{ "name": "test-pkg", "version": "1.0.0", "dependencies": { "express": "^4.18.0" } }
JSON
NODE_OUT=$(PATH=$(echo "$PATH" | tr ':' '\n' | grep -v npm | paste -sd ':') bash "$AUDIT_SCRIPT" "$NODE_DIR" 2>/dev/null || true)
if ! command -v npm >/dev/null 2>&1; then
  check "npm TOOL MISSING emitted" "$NODE_OUT" "A03 TOOL MISSING: npm not on PATH"
else
  # npm is available — verify Node.js section at least opens
  check "Node.js ecosystem detected" "$NODE_OUT" "Node.js detected"
fi

# --- Node.js: no lockfile finding ---
# package.json with no lockfile should produce a FINDING (A03) about reproducibility.
NOLOCKFILE_DIR="$WORK_DIR/no_lockfile"
mkdir -p "$NOLOCKFILE_DIR"
cat > "$NOLOCKFILE_DIR/package.json" <<'JSON'
{ "name": "unlocked", "version": "1.0.0", "dependencies": { "lodash": "4.17.21" } }
JSON
NOLOCKFILE_OUT=$(bash "$AUDIT_SCRIPT" "$NOLOCKFILE_DIR" 2>/dev/null || true)
check "missing lockfile finding emitted" "$NOLOCKFILE_OUT" "no lockfile committed"

# --- Python: pip-audit TOOL MISSING when pip-audit not on PATH ---
PY_DIR="$WORK_DIR/python_project"
mkdir -p "$PY_DIR"
echo "requests==2.31.0" > "$PY_DIR/requirements.txt"
if ! command -v pip-audit >/dev/null 2>&1; then
  PY_OUT=$(bash "$AUDIT_SCRIPT" "$PY_DIR" 2>/dev/null || true)
  check "pip-audit TOOL MISSING emitted" "$PY_OUT" "A03 TOOL MISSING: pip-audit not on PATH"
else
  echo "SKIP: pip-audit present — TOOL MISSING test skipped"
fi

# --- Python: pinning check — pinned requirements.txt must NOT trigger FINDING ---
PINNED_DIR="$WORK_DIR/pinned_requirements"
mkdir -p "$PINNED_DIR"
cat > "$PINNED_DIR/requirements.txt" <<'REQS'
# This project's dependencies
requests==2.31.0
flask==3.0.3
# test extra
pytest==7.4.0
REQS
PINNED_OUT=$(bash "$AUDIT_SCRIPT" "$PINNED_DIR" 2>/dev/null || true)
check_absent "pinned requirements.txt does NOT produce false FINDING" "$PINNED_OUT" "unpinned versions"

# --- Python: pinning check — unpinned requirement MUST trigger FINDING ---
UNPINNED_DIR="$WORK_DIR/unpinned_requirements"
mkdir -p "$UNPINNED_DIR"
cat > "$UNPINNED_DIR/requirements.txt" <<'REQS'
# comment line (should not trigger)
requests>=2.0
flask
REQS
UNPINNED_OUT=$(bash "$AUDIT_SCRIPT" "$UNPINNED_DIR" 2>/dev/null || true)
check "unpinned requirements.txt produces FINDING" "$UNPINNED_OUT" "FINDING (A03): requirements.txt has unpinned versions"

# --- Python: blank-line-only requirements.txt must NOT trigger false FINDING ---
BLANK_DIR="$WORK_DIR/blank_requirements"
mkdir -p "$BLANK_DIR"
printf "\n\n\n" > "$BLANK_DIR/requirements.txt"
BLANK_OUT=$(bash "$AUDIT_SCRIPT" "$BLANK_DIR" 2>/dev/null || true)
check_absent "blank requirements.txt does NOT produce false FINDING" "$BLANK_OUT" "unpinned versions"

# --- Python: option-directive-only requirements.txt must NOT trigger false FINDING ---
OPTS_DIR="$WORK_DIR/option_requirements"
mkdir -p "$OPTS_DIR"
cat > "$OPTS_DIR/requirements.txt" <<'REQS'
-r base.txt
-c constraints.txt
--extra-index-url https://pypi.example.com/simple
REQS
OPTS_OUT=$(bash "$AUDIT_SCRIPT" "$OPTS_DIR" 2>/dev/null || true)
check_absent "option-directive requirements.txt does NOT produce false FINDING" "$OPTS_OUT" "unpinned versions"

# --- Go: govulncheck TOOL MISSING ---
GO_DIR="$WORK_DIR/go_project"
mkdir -p "$GO_DIR"
cat > "$GO_DIR/go.mod" <<'GOMOD'
module example.com/myapp
go 1.22
GOMOD
if ! command -v govulncheck >/dev/null 2>&1; then
  GO_OUT=$(bash "$AUDIT_SCRIPT" "$GO_DIR" 2>/dev/null || true)
  check "govulncheck TOOL MISSING emitted" "$GO_OUT" "A03 TOOL MISSING: govulncheck not on PATH"
else
  echo "SKIP: govulncheck present — TOOL MISSING test skipped"
fi

# --- Rust: cargo-audit TOOL MISSING ---
RUST_DIR="$WORK_DIR/rust_project"
mkdir -p "$RUST_DIR"
touch "$RUST_DIR/Cargo.lock"
if ! command -v cargo-audit >/dev/null 2>&1; then
  RUST_OUT=$(bash "$AUDIT_SCRIPT" "$RUST_DIR" 2>/dev/null || true)
  check "cargo-audit TOOL MISSING emitted" "$RUST_OUT" "A03 TOOL MISSING: cargo-audit not on PATH"
else
  echo "SKIP: cargo-audit present — TOOL MISSING test skipped"
fi

# --- Ruby: bundler-audit TOOL MISSING ---
RUBY_DIR="$WORK_DIR/ruby_project"
mkdir -p "$RUBY_DIR"
touch "$RUBY_DIR/Gemfile.lock"
if ! command -v bundler-audit >/dev/null 2>&1; then
  RUBY_OUT=$(bash "$AUDIT_SCRIPT" "$RUBY_DIR" 2>/dev/null || true)
  check "bundler-audit TOOL MISSING emitted" "$RUBY_OUT" "A03 TOOL MISSING: bundler-audit not on PATH"
else
  echo "SKIP: bundler-audit present — TOOL MISSING test skipped"
fi

# --- Multi-ecosystem: multiple manifests all detected ---
MULTI_DIR="$WORK_DIR/multi_ecosystem"
mkdir -p "$MULTI_DIR"
echo '{ "name": "app", "version": "1.0.0" }' > "$MULTI_DIR/package.json"
echo "requests==2.31.0"                       > "$MULTI_DIR/requirements.txt"
printf "module example.com/app\ngo 1.22\n"   > "$MULTI_DIR/go.mod"
MULTI_OUT=$(bash "$AUDIT_SCRIPT" "$MULTI_DIR" 2>/dev/null || true)
check "multi-ecosystem: Node.js section detected" "$MULTI_OUT" "Node.js detected"
check "multi-ecosystem: Python section detected"  "$MULTI_OUT" "Python detected"
check "multi-ecosystem: Go section detected"      "$MULTI_OUT" "Go detected"

echo ""
echo "Results: $PASS passed, $FAIL failed"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
