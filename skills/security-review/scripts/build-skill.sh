#!/usr/bin/env bash
#
# Build the distributable .skill bundle for the security-review skill.
#
# Produces dist/security-review.skill — a zip archive with the canonical
# skills/security-review/ layout that claude.ai and compatible harnesses
# can install via upload.
#
# Usage (run from repo root):
#   bash skills/security-review/scripts/build-skill.sh
#   bash skills/security-review/scripts/build-skill.sh --version=1.2.0   # override version tag
#
# Output: dist/security-review-<version>.skill
#         dist/security-review.skill        (symlink/copy pointing to versioned file)
#
# Requires: python3 (stdlib zipfile) or zip. python3 is tried first since it is
# available everywhere (Linux, macOS, CI) without extra install steps.
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SKILL_DIR="$REPO_ROOT/skills/security-review"
DIST_DIR="$REPO_ROOT/dist"
PLUGIN_JSON="$REPO_ROOT/.claude-plugin/plugin.json"

# --- Resolve version ---
VERSION_OVERRIDE=""
for arg in "$@"; do
  case "$arg" in
    --version=*) VERSION_OVERRIDE="${arg#--version=}" ;;
  esac
done

if [ -n "$VERSION_OVERRIDE" ]; then
  VERSION="$VERSION_OVERRIDE"
elif command -v jq >/dev/null 2>&1 && [ -f "$PLUGIN_JSON" ]; then
  VERSION=$(jq -r '.version' "$PLUGIN_JSON")
else
  VERSION=$(grep '^version:' "$SKILL_DIR/SKILL.md" | head -1 | sed 's/version:[[:space:]]*//' | tr -d '"')
fi

if [ -z "$VERSION" ] || [ "$VERSION" = "null" ]; then
  echo "ERROR: could not determine version from plugin.json or SKILL.md" >&2
  exit 1
fi

BUNDLE_NAME="security-review-${VERSION}.skill"
BUNDLE_PATH="$DIST_DIR/$BUNDLE_NAME"
SYMLINK_PATH="$DIST_DIR/security-review.skill"

echo "Building security-review v${VERSION}..."
echo "  Source:  $SKILL_DIR"
echo "  Output:  $BUNDLE_PATH"

# --- Read .skillignore exclusion patterns ---
SKILLIGNORE="$SKILL_DIR/.skillignore"
EXCLUDE_PATTERNS=()
if [ -f "$SKILLIGNORE" ]; then
  while IFS= read -r line; do
    [[ "$line" =~ ^[[:space:]]*$ ]] && continue
    [[ "$line" =~ ^# ]] && continue
    EXCLUDE_PATTERNS+=("$line")
  done < "$SKILLIGNORE"
fi

# Always exclude dev/test artifacts from the bundle regardless of .skillignore
EXCLUDE_PATTERNS+=("tests/" "fixtures/" ".DS_Store" ".git/")

# --- Build the bundle using python3 (preferred) or zip ---
mkdir -p "$DIST_DIR"
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

# Stage: copy skill into skills/security-review/ inside the work dir.
# Harnesses expect this layout when unzipping a .skill bundle.
STAGE="$WORK_DIR/skills/security-review"
mkdir -p "$STAGE"
cp -r "$SKILL_DIR/." "$STAGE/"

# Remove excluded patterns from staging area
for pattern in "${EXCLUDE_PATTERNS[@]}"; do
  find "$STAGE" -name "$pattern" -prune -exec rm -rf {} + 2>/dev/null || true
  # Also handle directory patterns (trailing slash stripped)
  clean="${pattern%/}"
  find "$STAGE" -name "$clean" -prune -exec rm -rf {} + 2>/dev/null || true
done

if command -v python3 >/dev/null 2>&1; then
  # Use python3 stdlib zipfile — available everywhere, no extra install needed.
  python3 - "$WORK_DIR" "$BUNDLE_PATH" <<'PYEOF'
import sys, os, zipfile, pathlib

work_dir = pathlib.Path(sys.argv[1])
out_path = pathlib.Path(sys.argv[2])

with zipfile.ZipFile(out_path, 'w', compression=zipfile.ZIP_DEFLATED) as zf:
    for path in sorted(work_dir.rglob('*')):
        if path.is_file():
            arcname = path.relative_to(work_dir)
            zf.write(path, arcname)

print(f"  {out_path.stat().st_size // 1024}KB · {len(zf.namelist())} files")
PYEOF

elif command -v zip >/dev/null 2>&1; then
  (cd "$WORK_DIR" && zip -r "$BUNDLE_PATH" skills/ -x "*.DS_Store" -x "*/.git/*" -q)
  echo "  $(du -sh "$BUNDLE_PATH" | cut -f1) · $(cd "$WORK_DIR" && find skills/ -type f | wc -l | tr -d ' ') files"

else
  echo "ERROR: neither python3 nor zip found. Install one to build the bundle." >&2
  exit 1
fi

# Update the unversioned pointer (symlink on Unix, copy on systems without ln -sf)
if ln -sf "$BUNDLE_NAME" "$SYMLINK_PATH" 2>/dev/null; then
  : # symlink created
else
  cp "$BUNDLE_PATH" "$SYMLINK_PATH"
fi

echo ""
echo "✓ dist/$BUNDLE_NAME"
echo "  dist/security-review.skill → $BUNDLE_NAME"
echo ""
echo "Install paths:"
echo "  claude.ai web:  Upload dist/security-review.skill via claude.ai > Customize > Skills > + > Upload a skill"
echo "  claude.ai CLI:  /plugin install dist/security-review.skill"
