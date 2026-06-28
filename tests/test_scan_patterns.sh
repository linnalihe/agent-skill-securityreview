#!/usr/bin/env bash
#
# Scanner regression tests. Runs scan_patterns.sh against known-bad fixtures
# and asserts expected hits per category. Exits non-zero on any failure.
#
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_SCRIPTS="$SCRIPT_DIR/../skills/security-review/scripts"
FIXTURES="$SCRIPT_DIR/fixtures"

PASS=0
FAIL=0

# Check that a category section has at least one non-empty hit line.
# We grep for the category header AND a code snippet known to be in the fixture.
check() {
  local label="$1"
  local file="$2"
  local expected_category="$3"
  local expected_snippet="$4"   # a string that appears in the actual matched code line

  local output
  output=$(bash "$SKILL_SCRIPTS/scan_patterns.sh" . "$file" 2>/dev/null)

  if echo "$output" | grep -q "$expected_category" && echo "$output" | grep -qF "$expected_snippet"; then
    echo "PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $label"
    echo "  Expected category '$expected_category' and snippet '$expected_snippet' in output"
    echo "  Category line: $(echo "$output" | grep "$expected_category" | head -2 || echo '(none)')"
    echo "  Snippet match: $(echo "$output" | grep -F "$expected_snippet" | head -2 || echo '(none)')"
    FAIL=$((FAIL + 1))
  fi
}

check_summary_count() {
  local label="$1"
  local file="$2"
  local category_prefix="$3"

  local output
  output=$(bash "$SKILL_SCRIPTS/scan_patterns.sh" --emit=summary . "$file" 2>/dev/null)

  local count
  count=$(echo "$output" | grep "$category_prefix" | grep -o '[0-9]* hits' | grep -o '[0-9]*' || echo "0")

  if [ "${count:-0}" -gt 0 ]; then
    echo "PASS: $label (${count} hits)"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $label (expected >0 hits for '$category_prefix', got ${count:-0})"
    FAIL=$((FAIL + 1))
  fi
}

check_badge() {
  local label="$1"
  local file="$2"

  local first_line
  first_line=$(bash "$SKILL_SCRIPTS/scan_patterns.sh" . "$file" 2>/dev/null | head -1)

  if echo "$first_line" | grep -q "🔒 security-review v"; then
    echo "PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $label — badge not on first line (got: '$first_line')"
    FAIL=$((FAIL + 1))
  fi
}

echo "Running scanner regression tests..."
echo ""

# Badge emission (LAW 0)
check_badge "badge emitted as first line" "$FIXTURES/sqli_sample.js"

# A01 Broken Access Control — open redirect: match on the redirect call itself
check "A01: open redirect detected" \
  "$FIXTURES/open_redirect.js" \
  "A01 Broken Access Control" \
  "res.redirect"

# A04 Cryptographic Failures — hardcoded secret pattern matches the assignment
check "A04: hardcoded secret detected" \
  "$FIXTURES/hardcoded_secret.py" \
  "A04 Cryptographic Failures" \
  "FAKE_KEY_FOR_TESTING_ONLY"

# A04 — MD5 usage
check "A04: MD5 usage detected" \
  "$FIXTURES/hardcoded_secret.py" \
  "A04 Cryptographic Failures" \
  "md5"

# A05 Injection — SQL concatenation
check "A05: SQL injection detected" \
  "$FIXTURES/sqli_sample.js" \
  "A05 Injection" \
  "SELECT"

# A08 Software/Data Integrity Failures — pickle.loads
check "A08: pickle.loads detected" \
  "$FIXTURES/insecure_deserialize.py" \
  "A08 Software/Data Integrity Failures" \
  "pickle.loads"

# A08 — yaml.load
check "A08: yaml.load detected" \
  "$FIXTURES/insecure_deserialize.py" \
  "A08 Software/Data Integrity Failures" \
  "yaml.load"

# A10 Mishandling of Exceptional Conditions — empty catch
check "A10: empty catch block detected" \
  "$FIXTURES/silent_catch.js" \
  "A10 Mishandling of Exceptional Conditions" \
  "catch"

# Summary mode
check_summary_count "A05 summary mode shows hits" \
  "$FIXTURES/sqli_sample.js" \
  "A05 Injection"

check_summary_count "A08 summary mode shows hits" \
  "$FIXTURES/insecure_deserialize.py" \
  "A08 Software/Data Integrity Failures"

echo ""
echo "Results: $PASS passed, $FAIL failed"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
