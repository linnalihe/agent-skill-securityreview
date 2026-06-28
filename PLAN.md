# Build Plan: security-review as a production Agent Skills package

This document is a phase-by-phase build plan for turning the current `owasp-security-review/` prototype into a production-grade Agent Skills package distributed and invoked exactly like [mvanhorn/last30days-skill](https://github.com/mvanhorn/last30days-skill).

The architecture model is last30days throughout: a SKILL.md prose contract the model reads and executes step by step, backed by bash/Python scripts the model is instructed to call. The SKILL.md is the product surface; the scripts are implementation detail. Every design decision below is derived from studying how last30days handles the same structural problem.

---

## Current state

The repo already has the core intellectual content:

- `owasp-security-review/SKILL.md` - mode detection, OWASP category routing, severity rubric, hard rules
- `owasp-security-review/scripts/scan_patterns.sh` - ripgrep-based pattern scanner across all 10 categories
- `owasp-security-review/scripts/dependency_audit.sh` - ecosystem-aware supply chain audit (npm/pip/go/ruby/rust)
- `owasp-security-review/reference/A0X_*.md` - one reference file per OWASP category
- `owasp-security-review/templates/` - PR review comment and full finding report formats

What is missing is everything that makes this installable, distributable, reliable, and safe across multiple harnesses.

---

## Target layout

After all phases are complete, the repo should look like this:

```
agent-skill-securityreview/
├── .claude-plugin/
│   ├── plugin.json          # Claude Code marketplace manifest
│   └── marketplace.json     # Marketplace listing metadata
├── .codex-plugin/
│   └── plugin.json          # Codex plugin manifest
├── .agents/
│   └── plugins/
│       └── marketplace.json # Agent Skills ecosystem listing
├── .github/
│   └── workflows/
│       ├── validate.yml     # CI: lint SKILL.md frontmatter, run tests
│       └── release.yml      # Builds and publishes .skill bundle on tag
├── .gitignore
├── .skillignore             # Files excluded from .skill bundle (tests, fixtures, etc.)
├── AGENTS.md                # Machine-readable contributor + architecture guide (Claude.md alias)
├── CLAUDE.md                # Points to AGENTS.md (@AGENTS.md)
├── CHANGELOG.md             # Structured version history
├── README.md                # Human-readable overview + install table
├── hooks/
│   ├── hooks.json           # SessionStart hook registration
│   └── scripts/
│       └── check-tools.sh   # Checks for rg, git, gh and reports missing tools
├── skills/
│   └── security-review/
│       ├── SKILL.md         # Canonical skill spec (model reads this on invocation)
│       ├── .skillignore
│       ├── reference/
│       │   └── A0X_*.md    # (moved from owasp-security-review/reference/)
│       ├── scripts/
│       │   ├── preflight.sh         # --preflight mode: tool availability check
│       │   ├── scan_patterns.sh     # (moved + hardened from owasp-security-review/)
│       │   └── dependency_audit.sh  # (moved + hardened from owasp-security-review/)
│       └── templates/
│           ├── finding_report.md
│           └── pr_review_comment.md
└── tests/
    ├── test_scan_patterns.sh        # Verify scanner fires on known-bad fixtures
    ├── test_dependency_audit.sh     # Verify ecosystem detection
    └── fixtures/
        ├── sqli_sample.js           # Known-bad file for scanner tests
        ├── hardcoded_secret.py
        └── insecure_deserialize.py
```

---

## Phase 1: Package scaffolding

**Goal:** make the skill installable via `npx skills add` and the Claude Code marketplace.

### 1.1 Plugin manifests

Create `.claude-plugin/plugin.json`:

```json
{
  "name": "security-review",
  "version": "1.0.0",
  "description": "OWASP Top 10:2025 security review for pull requests and codebases. Finds vulnerabilities, explains exploitability in plain language, and proposes concrete fixes.",
  "author": {
    "name": "linnalihe",
    "url": "https://github.com/linnalihe"
  },
  "homepage": "https://github.com/linnalihe/agent-skill-securityreview",
  "repository": "https://github.com/linnalihe/agent-skill-securityreview",
  "license": "MIT",
  "keywords": [
    "security", "owasp", "code-review", "vulnerability", "pr-review",
    "static-analysis", "devsecops", "cwe", "injection", "audit"
  ]
}
```

Create `.codex-plugin/plugin.json` and `.agents/plugins/marketplace.json` with the same content shape (Codex and Agent Skills ecosystem manifests follow identical structure to last30days).

### 1.2 Move skill files into canonical layout

Rename `owasp-security-review/` → `skills/security-review/` and update all paths referenced in SKILL.md. The `skills/<name>/` layout is what `npx skills add` and the Claude Code plugin cache expect. Current references to `scripts/scan_patterns.sh` and `reference/A0X_*.md` will need to become `$SKILL_DIR/scripts/...` substitutions in SKILL.md (see Phase 2).

### 1.3 Session-start hook

Create `hooks/hooks.json`:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PLUGIN_ROOT:-${extensionPath:-.}}/hooks/scripts/check-tools.sh\""
          }
        ]
      }
    ]
  }
}
```

Create `hooks/scripts/check-tools.sh` - a lightweight check that:
- Verifies `rg` (ripgrep) is on PATH; if not, prints an advisory (does not fail the hook - missing rg degrades to grep fallback, not a hard stop)
- Verifies `git` is available; notes if not (snippet-only mode will still work)
- Verifies `gh` CLI is available; notes if not (PR fetch from GitHub URLs will be unavailable without it)
- Creates `~/.config/security-review/` if it doesn't exist (for any future per-user config)

The hook is advisory only - it should never block the model from starting.

### 1.4 README.md

Minimal README covering: what it does, the three review modes (PR diff, full audit, snippet), the install table (Claude Code marketplace + `npx skills add`), and the tool prerequisites (rg for fast pattern scanning, git for diff access, gh for hosted PR fetch).

### 1.5 AGENTS.md + CLAUDE.md

`AGENTS.md` is the machine-readable contributor guide. Modelled on last30days' AGENTS.md - covers:
- Repo structure and what each directory is for
- The two-layer design: SKILL.md is the product surface, scripts are implementation
- Rule: every new script flag needs a corresponding SKILL.md step that teaches the model the flag exists (otherwise no harness will ever use it)
- Security hygiene: never commit real tokens, credentials, or vulnerable-but-real code in fixtures
- Test requirements and how to run them
- CHANGELOG.md maintenance rules

`CLAUDE.md` contains a single line: `@AGENTS.md`

---

## Phase 2: SKILL.md hardening

**Goal:** make SKILL.md a reliable, regression-resistant contract the model follows correctly every run, across every harness.

The core lesson from last30days is that SKILL.md is not documentation - it is a behavioral contract enforced through named failure modes, output laws moved to the top of the file, and structural anchors the model passes through verbatim. Every section of SKILL.md that gets ignored produces a documented class of wrong output. The fixes are structural, not just prose.

### 2.1 Frontmatter

Replace the current minimal frontmatter with the full Agent Skills schema:

```yaml
---
name: security-review
version: "1.0.0"
description: "Review any pull request or codebase for OWASP Top 10:2025 security vulnerabilities. Finds bugs, explains exploitability in plain language, and proposes concrete fixes with before/after diffs."
argument-hint: 'security-review | security-review --pr=123 | security-review path/to/file.py'
allowed-tools: Bash, Read, WebFetch
user-invocable: true
license: MIT
homepage: https://github.com/linnalihe/agent-skill-securityreview
repository: https://github.com/linnalihe/agent-skill-securityreview
author: linnalihe
---
```

`argument-hint` tells the model's autocomplete what invocation patterns exist. `allowed-tools` restricts what the model can call inside this skill to the minimum needed (Bash for scripts, Read for file inspection, WebFetch for CVE lookups). `user-invocable: true` makes it appear in `/skill list`.

### 2.2 Stale-clone self-check (STEP 0)

Mirror last30days' STEP 0 stale-clone check. Claude Code auto-restores its `~/.claude/plugins/marketplaces/` directory from `origin/main` on session start - this directory can lag the versioned plugin cache by one or more releases. Add a check at the very top of SKILL.md (before any content the model acts on) that:

1. Finds the versioned plugin cache for this skill
2. Compares it against the directory the model loaded SKILL.md from
3. If loaded from the stale marketplaces path AND a newer cache copy exists, re-reads the cached SKILL.md before proceeding

This defends against the scenario where a new `--pr` flag or a bug fix ships in v1.1.0, but the model runs from the v1.0.0 marketplaces clone and never sees it.

### 2.3 Output contract section (before any steps)

Move the output contract to the top of SKILL.md, immediately after the stale-clone check. This mirrors last30days' hard-learned lesson: rules buried at line 1000+ get missed when the model reads the file in chunks.

**Mandatory output badge (LAW 0):**

Every response from this skill must begin with:

```
🔒 security-review v{VERSION} · reviewed {YYYY-MM-DD}
```

The version comes from `jq -r '.version' "$SKILL_DIR/../../.claude-plugin/plugin.json"`. The scripts emit this badge as their first stdout line so the correct behavior is always to pass through the script output verbatim.

**Why the badge is mandatory:** it anchors the output format. Without it, the model drifts into generic "code review" mode and loses the structured finding format with severity tiers, OWASP codes, CWE numbers, and the explicit merge recommendation. The badge is observable by the user and signals that the full SKILL.md contract was followed.

**Output laws (all query types):**

- **LAW 1 - MERGE RECOMMENDATION IS MANDATORY AND MUST BE FIRST.** Every PR review (Mode A) begins with `**Recommendation: Request changes / Approve with comments / Approve**` on its own line immediately after the badge. Never bury the recommendation. Never omit it. The reader looks at line 1 to know whether to block the merge.
- **LAW 2 - NO INVENTED VULNERABILITIES.** Every finding must be grounded in a specific file and line number from the actual code reviewed. Never report a class of vulnerability as "likely present" without a concrete location. If a check cannot be completed (file not accessible, context outside the diff), say so explicitly in the "Couldn't verify" section rather than speculating.
- **LAW 3 - NO WORKING EXPLOITS.** Illustrative payloads to demonstrate the bug class are allowed (`' OR '1'='1`, `<script>alert(1)</script>`). Full exploitation scripts, weaponized shellcode, and chained payloads that would cause real damage are not. If a finding would require a working exploit to explain, describe the attack path in plain language instead.
- **LAW 4 - NEVER FIX BY HIDING.** Do not silence an exception to stop a crash. Do not disable a CSP header to make a test pass. Do not add a `// nosec` comment to suppress a scanner alert without actually fixing the underlying issue. If the correct fix requires a design decision, flag it for human review rather than applying the wrong mechanical fix.
- **LAW 5 - PASS THROUGH SCRIPT OUTPUT.** When `scan_patterns.sh` or `dependency_audit.sh` is invoked, pass through its stdout into the working context verbatim before reasoning about findings. Never summarize or paraphrase scanner output into the review without reading the actual hits - a "no findings" summary for a category where the scanner had hits is a LAW 2 violation.
- **LAW 6 - WHAT WAS CHECKED BUT NOT FLAGGED IS MANDATORY.** Every review (Mode A and B) must include a "What I checked but didn't flag" section. A review with zero clean-bill items reads as incomplete and makes it impossible to distinguish "no findings" from "didn't look." If a security-sensitive area was inspected and found clean, say so.

### 2.4 SKILL_DIR substitution

Replace all hardcoded paths in SKILL.md (`scripts/scan_patterns.sh`, `reference/A01_broken_access_control.md`, etc.) with `$SKILL_DIR`-prefixed paths. `SKILL_DIR` is always set to the directory of the SKILL.md the model just Read. This is the single change that makes the skill work correctly regardless of how it was installed (Claude Code plugin cache, `npx skills` global install, symlinked checkout, OpenClaw, etc.).

The pattern:

```bash
SKILL_DIR="<absolute path of the directory containing the SKILL.md you just Read>"
bash "$SKILL_DIR/scripts/scan_patterns.sh" "$TARGET" "${CHANGED_FILES[@]}"
```

### 2.5 Mandatory preflight step

Before any review work, the SKILL.md must instruct the model to run:

```bash
bash "$SKILL_DIR/scripts/preflight.sh"
```

The preflight script checks: rg on PATH (required for `scan_patterns.sh`), git on PATH (required for diff access), gh on PATH (required for hosted PR fetch). It prints a human-readable status table. If rg is missing, the model is instructed to fall back to `grep -rnE` and note in the output that pattern scanning was done via grep fallback (slower, less accurate). It never hard-stops the review - it degrades gracefully and tells the user exactly what degraded and why.

### 2.6 Mode detection as a formal step with failure cases

The current SKILL.md has a good mode table but no handling for ambiguous or broken inputs. Add:

- **No target provided and no diff in context:** ask the user a single clarifying question ("What do you want me to review? A PR number, a path, or a code snippet?"). Never guess. Never start scanning the current directory blindly.
- **PR number provided but no gh CLI:** tell the user that `gh` is needed to fetch the diff (`brew install gh && gh auth login`) and offer to review a manually pasted diff instead.
- **Mode C (snippet) without surrounding context:** proactively note at the top of the finding what can't be verified (auth middleware, rate limiting, upstream parameterization) so the reader knows the scope.

### 2.7 Named failure modes

Document the failure modes that will inevitably occur so future model versions can avoid repeating them. Based on the structure of the current SKILL.md and common patterns in security review tooling, anticipate:

**Named failure mode (invented findings):** model reads a pattern hit from `scan_patterns.sh` and reports it as a confirmed vulnerability without reading the surrounding context. The pattern `eval(` fires on `eval("1+1")` in a test file with no user input. The scanner comment says "every hit is a CANDIDATE - read in context before reporting." LAW 2 restates this as a hard output constraint.

**Named failure mode (missing merge recommendation):** model produces a thorough finding list but omits the top-line `Recommendation:` line. The reader has to read the entire review to determine if the PR should be blocked. LAW 1 requires it on the first content line.

**Named failure mode (design-level auto-fix):** model applies a mechanical fix to an A06 Insecure Design or A10 Exceptional Conditions finding. These categories require business-context decisions (what is a legitimate booking volume? what is the correct rollback behavior when payment succeeds but fulfillment fails?). The SKILL.md hard rules section already covers this; LAW 4 reinforces it at the output-contract level.

**Named failure mode (skipped category for no scanner hits):** model runs `scan_patterns.sh`, gets zero hits for A06 and A10, and reports "no findings in these categories" without reasoning over the code paths. A06 and A10 are explicitly called out in the current SKILL.md as "reasoning only" categories that grep will never catch. LAW 5 and the per-step instruction require explicitly re-reading security-sensitive code paths even when the scanner is silent.

---

## Phase 3: Script hardening

**Goal:** make the scripts reliable, badge-emitting, and safe to invoke from any harness.

### 3.1 Badge emission

Both `scan_patterns.sh` and `dependency_audit.sh` should emit the badge line as their first stdout line:

```bash
VERSION=$(jq -r '.version' "$(dirname "$0")/../../.claude-plugin/plugin.json" 2>/dev/null || echo "?")
echo "🔒 security-review v${VERSION} · reviewed $(date +%Y-%m-%d)"
```

When the model passes through script output verbatim (per LAW 5), the badge appears automatically. This mirrors how last30days' engine emits the badge so the model's correct behavior - passing through script output - produces the required first-line anchor without needing model compliance on badge formatting.

### 3.2 preflight.sh

New script. Checks and prints a status table:

```
Tool        Status    Note
--------    ------    ----
rg          ✓         v14.1.0
git         ✓         v2.44.0
gh          ✓         v2.49.0 — PR fetch available
pip-audit   ✗         not on PATH — Python A03 will report "tool missing"
govulncheck ✗         not on PATH — Go A03 will report "tool missing"
```

Exits 0 always. Never fails. The model reads the table, notes what's degraded, and adjusts its instructions to the user accordingly.

### 3.3 Hardening scan_patterns.sh

- Add a `--emit=summary` flag: instead of printing every rg hit, print just the category-level counts (`A01: 3 hits, A04: 1 hit, A06: 0 hits`). Useful when the model wants to triage before deep-reading.
- Make the grep fallback explicit: if `rg` is not found, automatically fall back to `grep -rnE` with the same patterns and print a header warning that grep fallback is active.
- Scope vendor/generated exclusions more tightly: add `--glob '!__pycache__'`, `--glob '!*.pyc'`, `--glob '!.venv'`, `--glob '!env/'` to the common excludes.

### 3.4 Hardening dependency_audit.sh

- When a tool is missing (pip-audit, govulncheck, etc.), emit a structured line the model can pass through to the report: `A03 TOOL MISSING: pip-audit not on PATH — install with: pip install pip-audit`. This matches the last30days pattern of reporting degradation honestly rather than silently skipping.
- Add Bun support: check for `bun.lockb` and run `bun audit` if `bun` is on PATH.
- Add `uv` support: if `uv.lock` is present and `uv` is on PATH, run `uv pip audit`.

---

## Phase 4: Multi-harness distribution

**Goal:** installable via Claude Code marketplace, `npx skills add`, and manual git clone. Consistent behavior across all three install paths.

### 4.1 .skillignore

Create `skills/security-review/.skillignore` to exclude from the `.skill` bundle:
- `tests/`
- `fixtures/`
- `.git/`
- `*.sh.bak`

### 4.2 build-skill.sh

Add `skills/security-review/scripts/build-skill.sh` - packages the skill into a `dist/security-review.skill` file (a zip with a predictable internal layout) for upload to claude.ai and other harnesses that accept skill bundles. Mirror the last30days build script pattern.

### 4.3 Release workflow

Add `.github/workflows/release.yml`: on push of a tag matching `v*`, build the `.skill` bundle and publish it as a GitHub Release artifact. The release body is generated from `CHANGELOG.md` for the matching version section.

### 4.4 Multi-harness install table in README

```
| Surface          | Install command                              | Updates          |
|------------------|----------------------------------------------|------------------|
| Claude Code      | /plugin marketplace add linnalihe/agent-skill-securityreview | Auto via marketplace |
| Codex / Cursor / Gemini CLI / 50+ others | npx skills add linnalihe/agent-skill-securityreview -g | npx skills update security-review -g |
| claude.ai (web)  | Download security-review.skill from latest release → claude.ai > Customize > Skills > + > Upload | Re-download and re-upload |
| Manual           | git clone ... + ln -s | git pull in working tree |
```

---

## Phase 5: Tests and CI

**Goal:** every script change is tested; every SKILL.md structural contract is enforced.

### 5.1 Scanner tests

`tests/test_scan_patterns.sh` - runs `scan_patterns.sh` against known-bad fixture files and asserts expected hits:

```bash
# sqli_sample.js contains: db.query("SELECT * FROM users WHERE id = " + req.params.id)
output=$(bash "$SKILL_DIR/scripts/scan_patterns.sh" . tests/fixtures/sqli_sample.js)
echo "$output" | grep -q "A05 Injection" || { echo "FAIL: A05 Injection not detected in sqli_sample.js"; exit 1; }
echo "$output" | grep -q "sqli_sample.js" || { echo "FAIL: file not cited in output"; exit 1; }
echo "PASS: A05 SQLi detection"
```

Cover one fixture per OWASP category so each pattern bank has a passing test.

### 5.2 Dependency audit tests

`tests/test_dependency_audit.sh` - creates a minimal fixture package.json with a known-vulnerable package version and asserts the script produces `npm audit` output (or a "tool missing" message, not a silent skip).

### 5.3 SKILL.md frontmatter validation

`tests/test_frontmatter.sh` - checks that SKILL.md has required frontmatter fields (name, version, description, allowed-tools, user-invocable). Mirrors last30days' `tests/test_skill_version.py` pattern. This is the canary that fails when someone edits frontmatter incorrectly.

### 5.4 CI validate workflow

`.github/workflows/validate.yml`:

```yaml
on: [push, pull_request]
jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install ripgrep
        run: sudo apt-get install -y ripgrep
      - name: Run scanner tests
        run: bash tests/test_scan_patterns.sh
      - name: Run frontmatter validation
        run: bash tests/test_frontmatter.sh
```

---

## Phase 6: CHANGELOG.md + versioning

**Goal:** structured version history so users know what changed between releases.

Use the same format as last30days' CHANGELOG.md:

```markdown
# Changelog

## v1.1.0 - 2026-MM-DD

### Added
- `--pr=<number>` argument that fetches the diff via gh CLI automatically
- Bun and uv support in dependency_audit.sh (A03)

### Fixed
- scan_patterns.sh grep fallback now activates automatically when rg is not on PATH

## v1.0.0 - 2026-MM-DD

Initial production release. OWASP Top 10:2025 coverage across all three modes (PR/Diff, Full Audit, Snippet).
```

Version in `plugin.json` and SKILL.md frontmatter must match on every release. The CI validate workflow checks this (same pattern as last30days' `tests/test_version_consistency.py`).

---

## Implementation order

Work the phases in order. Each phase is independently mergeable.

| Phase | Branch name | Estimated scope |
|-------|-------------|-----------------|
| 1 - Package scaffolding | `feat/package-scaffolding` | New files only, no edits to existing SKILL.md |
| 2 - SKILL.md hardening | `feat/skill-md-contract` | SKILL.md rewrite; the largest single piece of work |
| 3 - Script hardening | `feat/script-hardening` | Edits to scan_patterns.sh, dependency_audit.sh; new preflight.sh |
| 4 - Distribution | `feat/multi-harness-distribution` | Manifests, build script, release workflow |
| 5 - Tests and CI | `feat/tests-ci` | New files only; validate.yml, test scripts, fixtures |
| 6 - Changelog | `feat/changelog` | New CHANGELOG.md; version bump to 1.0.0 everywhere |

Phases 1, 3, and 5 can be done in parallel once Phase 2 is merged (they don't depend on each other). Phase 4 depends on Phase 1 (manifests) and Phase 3 (scripts must be stable before building a release artifact). Phase 6 is the last step before the first public release.

---

## What the skill looks like when it's done

A user in Claude Code types:

```
/security-review --pr=142
```

The model:
1. Reads SKILL.md (from the versioned plugin cache, per STEP 0)
2. Runs the stale-clone check
3. Runs `preflight.sh` - confirms rg and gh are available
4. Runs `gh pr diff 142` to get the diff
5. Maps changed files to OWASP categories
6. Runs `scan_patterns.sh` scoped to changed files
7. Deep-reads every pattern hit in context
8. Deep-reads security-sensitive hunks that had zero hits (A06, A10)
9. Runs `dependency_audit.sh` if manifest files changed
10. Emits a review starting with the badge and merge recommendation

Output (abbreviated):

```
🔒 security-review v1.0.0 · reviewed 2026-06-28

**Recommendation: Request changes**

PR #142 adds a user profile update endpoint. One critical SQL injection and one missing ownership check found.

## 🔴 Must fix before merge

### Unparameterized query - A05 Injection (CWE-89)

**`src/routes/profile.js:47`**

The user ID is interpolated directly into the SQL string. Any authenticated user can modify this to read or write any row in the users table.

[before/after diff]

...

## What I checked but didn't flag

- Session token validation on the new endpoint (line 12): correctly uses `req.session.userId`, not a user-supplied value.
- Password update path: correctly uses bcrypt, not MD5 or SHA-1.
```

Every finding cites a real file and line. The merge recommendation is on line 1. The reviewer knows what was checked and what wasn't. No invented vulnerabilities. No working exploits. No silent skips.
