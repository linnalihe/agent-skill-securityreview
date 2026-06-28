#!/usr/bin/env bash
#
# OWASP Top 10:2025 - first-pass pattern scanner.
#
# This is a NET, not a VERDICT. It surfaces candidate locations fast so the agent can spend its
# reasoning budget reading actual context instead of scanning blind. Every hit still needs to be
# read in context before being reported as a finding - see false-positive notes in each
# reference/A0X_*.md file.
#
# Usage:
#   scan_patterns.sh [--emit=summary] [path]                  # scan everything under path (default: .)
#   scan_patterns.sh [--emit=summary] [path] file1 file2 ...  # scan only the listed files (PR/diff mode)
#
# --emit=summary prints category-level hit counts only (no file lines), useful for triage.
# Default emits every match with file:line.
#
set -uo pipefail

# bash 3.x (stock macOS) does not support declare -A (associative arrays added in bash 4.0).
# Require bash 4+ and fail early with a clear message rather than dying mid-scan with a
# cryptic "declare: -A: invalid option" error.
if (( BASH_VERSINFO[0] < 4 )); then
  echo "ERROR: scan_patterns.sh requires bash 4+ (you have ${BASH_VERSION})." >&2
  echo "  macOS ships bash 3.2 for GPL reasons. Install a current bash:" >&2
  echo "    brew install bash" >&2
  echo "  Then invoke with the full path: /opt/homebrew/bin/bash $0 ..." >&2
  exit 1
fi

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

# --- Argument parsing ---
EMIT="full"
if [[ "${1:-}" == "--emit=summary" ]]; then
  EMIT="summary"
  shift
fi

TARGET="${1:-.}"
shift || true
FILES=("$@")

# --- Scanner backend: ripgrep preferred, grep fallback ---
USE_RG=0
if command -v rg >/dev/null 2>&1; then
  USE_RG=1
else
  echo "NOTE: ripgrep (rg) not found. Falling back to grep. Install ripgrep for faster, more accurate scanning." >&2
fi

# Exclusion globs/flags for directory-wide scans only.
# In PR/diff mode (explicit FILES passed), exclusions are NOT applied: the files were already
# scoped by the caller. Applying --glob '!env/' to an explicit path like backend/env/config.py
# silently drops it from results. Grep's --exclude-dir similarly only affects recursive traversal.
COMMON_EXCLUDES_RG=(--glob '!node_modules' --glob '!vendor' --glob '!dist' --glob '!build'
                    --glob '!.git' --glob '!*.min.js' --glob '!*.lock' --glob '!coverage'
                    --glob '!__pycache__' --glob '!*.pyc' --glob '!.venv' --glob '!env/')

COMMON_EXCLUDES_GREP=(--exclude-dir=node_modules --exclude-dir=vendor --exclude-dir=dist
                      --exclude-dir=build --exclude-dir=.git --exclude-dir=coverage
                      --exclude-dir=__pycache__ --exclude-dir=.venv --exclude-dir=env
                      --exclude='*.min.js' --exclude='*.lock' --exclude='*.pyc')

if [ "${#FILES[@]}" -gt 0 ]; then
  # PR/diff mode: scan only the explicitly listed files, no glob exclusions.
  SCAN_ARGS=("${FILES[@]}")
  ACTIVE_EXCLUDES_RG=()
  ACTIVE_EXCLUDES_GREP=()
else
  # Directory mode: scan the target tree with exclusions.
  SCAN_ARGS=("$TARGET")
  ACTIVE_EXCLUDES_RG=("${COMMON_EXCLUDES_RG[@]}")
  ACTIVE_EXCLUDES_GREP=("${COMMON_EXCLUDES_GREP[@]}")
fi

# --- Per-category hit counters (bash 4+ associative array) ---
declare -A CATEGORY_COUNTS

# SCAN: run a single pattern search. In full mode prints hits; always accumulates count.
# Args: label pattern [pattern ...]
# Caller must set CURRENT_CATEGORY before calling.
SCAN() {
  local label="$1"
  shift
  local patterns=("$@")
  local rg_args=()
  local grep_args=()
  for p in "${patterns[@]}"; do
    rg_args+=(-e "$p")
    grep_args+=(-e "$p")
  done

  local output
  if [ "$USE_RG" -eq 1 ]; then
    output=$(rg --no-heading --line-number --color=never -i \
      "${ACTIVE_EXCLUDES_RG[@]+"${ACTIVE_EXCLUDES_RG[@]}"}" \
      "${rg_args[@]}" "${SCAN_ARGS[@]}" 2>/dev/null || true)
  else
    output=$(grep -rnEi \
      "${ACTIVE_EXCLUDES_GREP[@]+"${ACTIVE_EXCLUDES_GREP[@]}"}" \
      "${grep_args[@]}" "${SCAN_ARGS[@]}" 2>/dev/null || true)
  fi

  local count
  count=$(echo "$output" | grep -c . || true)

  CATEGORY_COUNTS["${CURRENT_CATEGORY:-other}"]=$(( ${CATEGORY_COUNTS["${CURRENT_CATEGORY:-other}"]:-0} + count ))

  if [ "$EMIT" = "full" ]; then
    echo "-- $label --"
    if [ -n "$output" ]; then
      echo "$output"
    fi
  fi
}

section() {
  CURRENT_CATEGORY="$1"
  CATEGORY_COUNTS["$1"]=0
  if [ "$EMIT" = "full" ]; then
    echo ""
    echo "================ $1 ================"
  fi
}

# ---- A01 Broken Access Control ----
section "A01 Broken Access Control"
SCAN "direct object reference into a DB call without visible ownership check" \
  '(findById|findOne|find|get)\([^)]*req\.(params|query|body)'
SCAN "permissive CORS" \
  'Access-Control-Allow-Origin.{0,5}\*' 'cors\(\s*\)'
SCAN "open redirect candidates" \
  '(res\.redirect|redirect_to|window\.location)\s*\(.*(req\.|params\[|request\.)'
SCAN "directory listing / sensitive files" \
  'autoindex\s+on' 'Options \+Indexes'

# ---- A02 Security Misconfiguration ----
section "A02 Security Misconfiguration"
SCAN "debug mode left on" \
  'DEBUG\s*=\s*True' 'debug:\s*true' 'app\.debug\s*=\s*true'
SCAN "XXE-permissive XML parsing" \
  'DocumentBuilderFactory' 'XMLInputFactory' 'etree\.parse' 'lxml'
SCAN "missing-looking security headers config" \
  'Strict-Transport-Security' 'Content-Security-Policy' 'helmet\('

# ---- A03 Software Supply Chain Failures ----
section "A03 Software Supply Chain Failures"
SCAN "install scripts (check these are legitimate)" \
  '"postinstall"' '"preinstall"'
SCAN "mutable CI action tags / broad permissions" \
  'uses:.*@(v[0-9]+|main|master|latest)' 'permissions:\s*write-all'

# ---- A04 Cryptographic Failures ----
section "A04 Cryptographic Failures"
SCAN "broken/weak hash or cipher" \
  '\bmd5\b' '\bsha1\b' 'DES\b' '/ECB/'
SCAN "non-cryptographic randomness for security-sensitive values" \
  'Math\.random\(\)' '\brandom\.random\(' '\brandom\.randint\('
SCAN "disabled TLS/cert verification" \
  'verify\s*=\s*False' 'rejectUnauthorized:\s*false' 'NODE_TLS_REJECT_UNAUTHORIZED'
SCAN "hardcoded secret-shaped assignment" \
  "(secret|password|api[_-]?key|token)\\s*[:=]\\s*[\"'][A-Za-z0-9+/=_-]{8,}[\"']"

# ---- A05 Injection ----
section "A05 Injection"
SCAN "string-built SQL" \
  '(SELECT|INSERT|UPDATE|DELETE)\b.{0,80}(\+|f"|f'"'"'|%s|\$\{)'
SCAN "shell execution from dynamic input" \
  'shell\s*=\s*True' 'execSync\(' 'os\.system\(' 'Runtime\.getRuntime\(\)\.exec'
SCAN "dangerous HTML/eval sinks" \
  'dangerouslySetInnerHTML' '\bv-html\b' '\|\s*safe\b' '\beval\('

# ---- A06 Insecure Design (greppable subset only) ----
section "A06 Insecure Design"
SCAN "client-trusted price/role/state fields" \
  'req\.body\.(price|amount|role|isAdmin|discount)'
SCAN "file upload type check by extension only" \
  '\.(originalname|filename)\.(split|endsWith)'

# ---- A07 Authentication Failures ----
section "A07 Authentication Failures"
SCAN "hardcoded credentials" \
  "(username|user)\\s*==\\s*[\"']admin[\"']" "password\\s*==\\s*[\"'][^\"']+[\"']"
SCAN "enumerable auth error messages (manual review of nearby context needed)" \
  'No account' 'user not found' 'Incorrect password'

# ---- A08 Software/Data Integrity Failures ----
section "A08 Software/Data Integrity Failures"
SCAN "unsafe deserialization" \
  'pickle\.loads?\(' 'yaml\.load\(' 'ObjectInputStream' 'unserialize\('
SCAN "mutable/unpinned image or artifact references" \
  'FROM\s+[a-zA-Z0-9./_-]+:latest'

# ---- A09 Security Logging & Alerting Failures ----
section "A09 Security Logging & Alerting Failures"
SCAN "sensitive data passed into a log call" \
  '(log|logger)\.[a-z]+\(.*\b(password|token|secret|ssn|credit_?card)\b'
SCAN "empty/silent catch around auth or access-control code" \
  'catch\s*\([^)]*\)\s*\{\s*\}'

# ---- A10 Mishandling of Exceptional Conditions ----
section "A10 Mishandling of Exceptional Conditions"
SCAN "empty or pass-only exception handling" \
  'catch\s*\([^)]*\)\s*\{\s*\}' 'except.*:\s*$' 'except\s*:\s*pass'
SCAN "stack trace / traceback returned to client" \
  'err\.stack' 'traceback\.format_exc' 'printStackTrace'

# ---- Summary (always printed; also the only output in --emit=summary mode) ----
echo ""
echo "================ Summary ================"
TOTAL=0
for cat in "A01 Broken Access Control" "A02 Security Misconfiguration" \
           "A03 Software Supply Chain Failures" "A04 Cryptographic Failures" \
           "A05 Injection" "A06 Insecure Design" "A07 Authentication Failures" \
           "A08 Software/Data Integrity Failures" "A09 Security Logging & Alerting Failures" \
           "A10 Mishandling of Exceptional Conditions"; do
  count=${CATEGORY_COUNTS["$cat"]:-0}
  TOTAL=$((TOTAL + count))
  printf "  %-45s %d hits\n" "$cat" "$count"
done
echo ""
echo "  Total candidate hits: $TOTAL"
echo ""
echo "================ Done ================"
echo "Every hit above is a CANDIDATE only. Read each in surrounding context before reporting it"
echo "as a finding - see the false-positive notes in the matching reference/A0X_*.md file."
echo "A06 and most of A10 need direct reasoning over the code's logic, not just grep -"
echo "deliberately re-read security-sensitive code paths that produced zero hits above."
