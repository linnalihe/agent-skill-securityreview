# Changelog

## v1.0.0 — 2026-06-28

Initial production release.

### Added

**Package structure**
- Canonical `skills/security-review/` layout compatible with Claude Code marketplace, `npx skills add`, OpenClaw, and all Agent Skills hosts
- Plugin manifests: `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `.agents/plugins/marketplace.json`
- SessionStart hook (`hooks/hooks.json` + `hooks/scripts/check-tools.sh`) that checks for rg/git/gh at session start and prints an advisory — never blocks the session
- `AGENTS.md` contributor guide covering the two-layer design, rules, and security hygiene
- `.skillignore` to exclude tests and fixtures from the distributable bundle

**SKILL.md contract**
- Full frontmatter: name, version, description, argument-hint, allowed-tools, user-invocable, license, homepage, repository, author
- STEP 0 stale-clone self-check at the top of the file (defends against Claude Code's marketplaces directory lagging the versioned plugin cache)
- Output contract section before all execution steps, with 7 named output laws:
  - LAW 0: mandatory badge on first line of output
  - LAW 1: merge recommendation mandatory and first
  - LAW 2: no invented vulnerabilities — every finding requires a real file:line
  - LAW 3: no working exploits
  - LAW 4: never fix by hiding
  - LAW 5: pass through script output verbatim before synthesizing
  - LAW 6: "what I checked but didn't flag" section mandatory in every review
- Named failure modes documented inline in each law
- `$SKILL_DIR` substitution throughout (install-path independent across all harnesses)
- Mandatory preflight step before any review work
- Mode detection (Mode A: PR/diff, Mode B: full audit, Mode C: snippet) with explicit failure cases
- Mandatory A06/A10 reasoning pass even when the scanner finds nothing in those categories
- Load-only-relevant-reference-files rule

**Scripts**
- `scripts/preflight.sh`: tool status table (rg, git, gh, jq, npm, pip-audit, govulncheck, bundler-audit, cargo-audit, bun, uv); always exits 0; degrades gracefully
- `scripts/scan_patterns.sh`: badge emission on first line; `--emit=summary` flag for triage; automatic grep fallback when rg is missing; per-category hit count summary; tighter vendor excludes (`__pycache__`, `.venv`, `env/`)
- `scripts/dependency_audit.sh`: badge emission; structured `A03 TOOL MISSING:` lines (not silent skips); Bun (`bun.lockb` + `bun audit`) and uv (`uv.lock` + `uv pip audit`) support; "no manifests found" message

**Tests and CI**
- `tests/test_scan_patterns.sh`: 10 scanner regression tests covering badge emission, A01/A04/A05/A08/A10 detection, and `--emit=summary` mode
- `tests/test_frontmatter.sh`: 15 checks covering required frontmatter fields, version consistency between SKILL.md and plugin.json, and presence of all 7 output laws
- `tests/fixtures/`: synthetic known-bad code samples (sqli_sample.js, hardcoded_secret.py, insecure_deserialize.py, open_redirect.js, silent_catch.js)
- `.github/workflows/validate.yml`: CI workflow running both test suites on every push and PR
