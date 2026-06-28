#!/usr/bin/env bash
#
# SKILL.md frontmatter validation.
# Checks required fields exist and that version is consistent with plugin.json.
# Exits non-zero on any failure.
#
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_MD="$SCRIPT_DIR/../skills/security-review/SKILL.md"
PLUGIN_JSON="$SCRIPT_DIR/../.claude-plugin/plugin.json"

PASS=0
FAIL=0

check_field() {
  local label="$1"
  local pattern="$2"

  if grep -q "$pattern" "$SKILL_MD"; then
    echo "PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $label — '$pattern' not found in SKILL.md frontmatter"
    FAIL=$((FAIL + 1))
  fi
}

echo "Validating SKILL.md frontmatter..."
echo ""

check_field "name field present"           "^name:"
check_field "version field present"        "^version:"
check_field "description field present"    "^description:"
check_field "allowed-tools field present"  "^allowed-tools:"
check_field "user-invocable field present" "^user-invocable:"
check_field "author field present"         "^author:"
check_field "homepage field present"       "^homepage:"

# Version consistency: SKILL.md version must match plugin.json version
if command -v jq >/dev/null 2>&1; then
  PLUGIN_VERSION=$(jq -r '.version' "$PLUGIN_JSON" 2>/dev/null || echo "MISSING")
  SKILL_VERSION=$(grep '^version:' "$SKILL_MD" | head -1 | sed 's/version:[[:space:]]*//' | tr -d '"' || echo "MISSING")

  if [ "$PLUGIN_VERSION" = "$SKILL_VERSION" ]; then
    echo "PASS: version consistent (SKILL.md=$SKILL_VERSION, plugin.json=$PLUGIN_VERSION)"
    PASS=$((PASS + 1))
  else
    echo "FAIL: version mismatch — SKILL.md has '$SKILL_VERSION', plugin.json has '$PLUGIN_VERSION'"
    FAIL=$((FAIL + 1))
  fi
else
  echo "SKIP: version consistency check requires jq"
fi

# Check output laws are present
echo ""
echo "Checking output laws..."

for law in "LAW 0" "LAW 1" "LAW 2" "LAW 3" "LAW 4" "LAW 5" "LAW 6"; do
  if grep -q "$law" "$SKILL_MD"; then
    echo "PASS: $law present in SKILL.md"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $law missing from SKILL.md"
    FAIL=$((FAIL + 1))
  fi
done

echo ""
echo "Results: $PASS passed, $FAIL failed"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
