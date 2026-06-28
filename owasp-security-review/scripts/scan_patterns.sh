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
#   scan_patterns.sh [path]                 # scan everything under path (default: .)
#   scan_patterns.sh [path] file1 file2 ...  # scan only the listed files (PR/diff mode)
#
set -uo pipefail

TARGET="${1:-.}"
shift || true
FILES=("$@")

if ! command -v rg >/dev/null 2>&1; then
  echo "ripgrep (rg) not found on PATH. Install it, or fall back to:" >&2
  echo "  grep -rnE '<pattern>' $TARGET" >&2
  exit 1
fi

# If specific files were passed (diff mode), scan only those. Otherwise scan the whole target.
if [ "${#FILES[@]}" -gt 0 ]; then
  SCAN_ARGS=("${FILES[@]}")
else
  SCAN_ARGS=("$TARGET")
fi

# Common excludes so we don't waste time/noise on vendored or generated code.
COMMON_EXCLUDES=(--glob '!node_modules' --glob '!vendor' --glob '!dist' --glob '!build'
                  --glob '!.git' --glob '!*.min.js' --glob '!*.lock' --glob '!coverage')

RG() { rg --no-heading --line-number --color=never -i "${COMMON_EXCLUDES[@]}" "$@"; }

section() { echo; echo "================ $1 ================"; }

section "A01 Broken Access Control"
echo "-- direct object reference into a DB call without visible ownership check --"
RG -e '(findById|findOne|find|get)\([^)]*req\.(params|query|body)' "${SCAN_ARGS[@]}"
echo "-- permissive CORS --"
RG -e 'Access-Control-Allow-Origin.{0,5}\*' -e 'cors\(\s*\)' "${SCAN_ARGS[@]}"
echo "-- open redirect candidates --"
RG -e '(res\.redirect|redirect_to|window\.location)\s*\(.*(req\.|params\[|request\.)' "${SCAN_ARGS[@]}"
echo "-- directory listing / sensitive files --"
RG -e 'autoindex\s+on' -e 'Options \+Indexes' "${SCAN_ARGS[@]}"

section "A02 Security Misconfiguration"
echo "-- debug mode left on --"
RG -e 'DEBUG\s*=\s*True' -e 'debug:\s*true' -e 'app\.debug\s*=\s*true' "${SCAN_ARGS[@]}"
echo "-- XXE-permissive XML parsing --"
RG -e 'DocumentBuilderFactory' -e 'XMLInputFactory' -e 'etree\.parse' -e 'lxml' "${SCAN_ARGS[@]}"
echo "-- missing-looking security headers config --"
RG -e 'Strict-Transport-Security' -e 'Content-Security-Policy' -e 'helmet\(' "${SCAN_ARGS[@]}"

section "A03 Software Supply Chain Failures"
echo "-- install scripts (check these are legitimate) --"
RG -e '"postinstall"' -e '"preinstall"' "${SCAN_ARGS[@]}"
echo "-- mutable CI action tags / broad permissions --"
RG -e 'uses:.*@(v[0-9]+|main|master|latest)' -e 'permissions:\s*write-all' "${SCAN_ARGS[@]}"

section "A04 Cryptographic Failures"
echo "-- broken/weak hash or cipher --"
RG -e '\bmd5\b' -e '\bsha1\b' -e 'DES\b' -e '/ECB/' "${SCAN_ARGS[@]}"
echo "-- non-cryptographic randomness for security-sensitive values --"
RG -e 'Math\.random\(\)' -e '\brandom\.random\(' -e '\brandom\.randint\(' "${SCAN_ARGS[@]}"
echo "-- disabled TLS/cert verification --"
RG -e 'verify\s*=\s*False' -e 'rejectUnauthorized:\s*false' -e 'NODE_TLS_REJECT_UNAUTHORIZED' "${SCAN_ARGS[@]}"
echo "-- hardcoded secret-shaped assignment --"
RG -e "(secret|password|api[_-]?key|token)\\s*[:=]\\s*[\"'][A-Za-z0-9+/=_-]{8,}[\"']" "${SCAN_ARGS[@]}"

section "A05 Injection"
echo "-- string-built SQL --"
RG -e '(SELECT|INSERT|UPDATE|DELETE)\b.{0,80}(\+|f"|f\x27|%s|\$\{)' "${SCAN_ARGS[@]}"
echo "-- shell execution from dynamic input --"
RG -e 'shell\s*=\s*True' -e 'execSync\(' -e 'os\.system\(' -e 'Runtime\.getRuntime\(\)\.exec' "${SCAN_ARGS[@]}"
echo "-- dangerous HTML/eval sinks --"
RG -e 'dangerouslySetInnerHTML' -e '\bv-html\b' -e '\|\s*safe\b' -e '\beval\(' "${SCAN_ARGS[@]}"

section "A06 Insecure Design (greppable subset only - most needs manual reasoning)"
echo "-- client-trusted price/role/state fields --"
RG -e 'req\.body\.(price|amount|role|isAdmin|discount)' "${SCAN_ARGS[@]}"
echo "-- file upload type check by extension only --"
RG -e '\.(originalname|filename)\.(split|endsWith)' "${SCAN_ARGS[@]}"

section "A07 Authentication Failures"
echo "-- hardcoded credentials --"
RG -e "(username|user)\\s*==\\s*[\"']admin[\"']" -e "password\\s*==\\s*[\"'][^\"']+[\"']" "${SCAN_ARGS[@]}"
echo "-- enumerable auth error messages (manual review of nearby context needed) --"
RG -e 'No account' -e 'user not found' -e 'Incorrect password' "${SCAN_ARGS[@]}"

section "A08 Software/Data Integrity Failures"
echo "-- unsafe deserialization (for yaml.load, manually confirm it's not yaml.safe_load) --"
RG -e 'pickle\.loads?\(' -e 'yaml\.load\(' -e 'ObjectInputStream' -e 'unserialize\(' "${SCAN_ARGS[@]}"
echo "-- mutable/unpinned image or artifact references --"
RG -e 'FROM\s+[a-zA-Z0-9./_-]+:latest' "${SCAN_ARGS[@]}"

section "A09 Security Logging & Alerting Failures"
echo "-- sensitive data passed into a log call --"
RG -e '(log|logger)\.[a-z]+\(.*\b(password|token|secret|ssn|credit_?card)\b' "${SCAN_ARGS[@]}"
echo "-- empty/silent catch around auth or access-control code (cross-check with A10) --"
RG -e 'catch\s*\([^)]*\)\s*\{\s*\}' "${SCAN_ARGS[@]}"

section "A10 Mishandling of Exceptional Conditions"
echo "-- empty or pass-only exception handling --"
RG -e 'catch\s*\([^)]*\)\s*\{\s*\}' -e 'except.*:\s*$' -e 'except\s*:\s*pass' "${SCAN_ARGS[@]}"
echo "-- stack trace / traceback returned to client --"
RG -e 'err\.stack' -e 'traceback\.format_exc' -e 'printStackTrace' "${SCAN_ARGS[@]}"

echo
echo "================ Done ================"
echo "Every hit above is a CANDIDATE only. Read each in surrounding context before reporting it"
echo "as a finding - see the false-positive notes in the matching reference/A0X_*.md file."
echo "Remember: A06 and most of A10 need direct reasoning over the code's logic, not just grep -"
echo "deliberately re-read security-sensitive code paths that produced zero hits above."
