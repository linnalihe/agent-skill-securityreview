#!/usr/bin/env bash
#
# SessionStart hook for the security-review skill.
#
# Runs once at session start. Checks for rg, git, and gh and prints a single
# advisory line if any are missing. Never fails or blocks the session - missing
# tools degrade coverage, they do not abort the review.
#
set -uo pipefail

CONFIG_DIR="$HOME/.config/security-review"
mkdir -p "$CONFIG_DIR" 2>/dev/null || true

MISSING=()
command -v rg >/dev/null 2>&1 || MISSING+=("rg (ripgrep) - pattern scanning falls back to grep")
command -v git >/dev/null 2>&1 || MISSING+=("git - PR/diff mode (Mode A) unavailable")
command -v gh >/dev/null 2>&1 || MISSING+=("gh - PR fetch by number unavailable; paste diffs manually")

if [ "${#MISSING[@]}" -gt 0 ]; then
  echo "security-review: optional tools missing - ${MISSING[*]}"
  echo "  Run '/security-review preflight' for details and install instructions."
fi

exit 0
