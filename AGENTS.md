# security-review skill

Agent Skills package for reviewing pull requests and codebases for OWASP Top 10:2025 security vulnerabilities. Installable across Claude Code (most common host), Codex, Cursor, GitHub Copilot, Gemini CLI, and 50+ other Agent Skills hosts. Bash scripts with ripgrep-based pattern scanning and ecosystem-aware dependency auditing.

## Structure

- `skills/security-review/SKILL.md` — canonical skill definition / runtime spec the model reads when the slash command fires
- `skills/security-review/scripts/scan_patterns.sh` — ripgrep-based OWASP pattern scanner (all 10 categories)
- `skills/security-review/scripts/dependency_audit.sh` — ecosystem-aware supply chain audit (npm/pip/uv/bun/go/ruby/rust)
- `skills/security-review/scripts/preflight.sh` — tool availability check; always exits 0; degrades gracefully
- `skills/security-review/reference/A0X_*.md` — one file per OWASP category: key CWEs, detection signals by language, fix patterns with before/after code, false-positive notes
- `skills/security-review/templates/` — output formats (PR review comment, full finding report)
- `hooks/hooks.json` — SessionStart hook registration
- `hooks/scripts/check-tools.sh` — lightweight session-start tool check (rg, git, gh); never blocks the session
- `.claude-plugin/plugin.json` — Claude Code marketplace manifest
- `.codex-plugin/plugin.json` — Codex plugin manifest
- `.agents/plugins/marketplace.json` — Agent Skills ecosystem listing
- `tests/` — scanner regression tests and frontmatter validation
- `PLAN.md` — build plan documenting architecture decisions and implementation phases

## Orientation

This is an Agent Skills package, not a standalone CLI tool. The product is the slash-command-invoked skill (`/security-review` in most harnesses); the scripts are implementation detail.

Feature design starts from the slash-command UX. A new script flag with no SKILL.md integration is incomplete - the model invoking the skill won't know the flag exists.

The two-layer design:
- **SKILL.md** is the prose contract the model reads and follows step by step. It defines modes, output laws, named failure modes, and which scripts to run in which order.
- **Scripts** are what SKILL.md instructs the model to invoke via Bash. They emit a mandatory badge line as their first stdout line so the model's correct behavior (passing through output verbatim) produces the required output anchor automatically.

## Commands

```bash
# Run the pattern scanner directly (dev/testing)
bash skills/security-review/scripts/scan_patterns.sh .
bash skills/security-review/scripts/scan_patterns.sh --emit=summary .

# Scoped to specific files (PR/diff mode)
bash skills/security-review/scripts/scan_patterns.sh . src/auth/login.js src/routes/user.js

# Run the dependency audit
bash skills/security-review/scripts/dependency_audit.sh .

# Run the preflight check
bash skills/security-review/scripts/preflight.sh

# Run tests
bash tests/test_scan_patterns.sh
bash tests/test_frontmatter.sh
```

## Rules

- **Every new script flag needs a corresponding SKILL.md step.** If SKILL.md doesn't reference a flag, no harness will ever use it. The scripts are implementation; SKILL.md is the interface.
- **Scripts always emit the badge as their first stdout line.** This ensures the model's default correct behavior (pass-through) produces the required output anchor without depending on model compliance at synthesis time.
- **preflight.sh always exits 0.** Missing tools degrade coverage; they do not abort the review. The script reports what's missing so the model can tell the user what couldn't be checked.
- **check-tools.sh (the session hook) always exits 0.** It is advisory only. It must never block the model from starting.
- **Never commit real credentials, tokens, or genuinely-vulnerable production code in fixtures.** Test fixtures must use synthetic, obviously-fake examples (e.g., `secret = "FAKE_KEY_FOR_TESTING_ONLY"`) that the scanner will catch but no real system will accept.
- **A03 tool-missing lines must appear in the report.** When `dependency_audit.sh` can't run an ecosystem audit because the tool is absent, it emits `A03 TOOL MISSING: ...`. The model must pass this through to the report - treating a missing tool as "no findings" is a LAW 5 violation.
- **A06 and A10 are reasoning-only categories.** The scanner can catch a greppable subset, but the real bugs in these categories require reading the code's logic. SKILL.md explicitly instructs a deliberate reasoning pass over these areas even when the scanner finds nothing.

## Security hygiene

- Never commit real API keys, tokens, credentials, browser cookies, or `.env` contents.
- Test fixtures must use obviously-fake credential values (e.g. `api_key = "FAKE_KEY_FOR_TESTING_ONLY"` not a real-looking key).
- Do not weaken or disable the security workflow (`.github/workflows/security.yml` when added) without explaining why in the PR description.
- The skill is defensive only. Any PR that adds offensive capability (working exploits, attack automation, detection evasion) should be rejected.

## Maintaining SKILL.md

Update SKILL.md when:
- Adding a new script flag (so the model knows it exists and when to use it)
- Adding a new OWASP sub-pattern or reference file section
- Changing the step execution order
- Documenting a new named failure mode (a class of wrong output the model produced that required a structural fix)
- Changing the mode-detection logic (what triggers PR vs. full audit vs. snippet mode)

The output laws in SKILL.md (LAW 0 through LAW 6) are the formatting contract. They live at the top of the file - before any steps - because rules buried past line 500 get missed when the model reads the file in chunks. If you add a new law, add it to the top-of-file contract section, not at the end.

## Named failure modes

Document new failure modes in SKILL.md with:
- A concrete description of the wrong output (what the model produced)
- The date it was first observed (if known)
- The root cause
- The structural fix (not just a note to "do better")

Named failure modes are not blame - they are the mechanism that makes SKILL.md a regression-resistant contract rather than aspirational prose.
