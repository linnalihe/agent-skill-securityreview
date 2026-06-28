---
name: security-review
version: "1.0.0"
description: "Review any pull request or codebase for OWASP Top 10:2025 security vulnerabilities. Three modes: PR/diff review, full codebase audit, or snippet review. Finds bugs, explains exploitability in plain language, proposes concrete fixes with before/after diffs, and gives an explicit merge recommendation."
argument-hint: 'security-review | security-review --pr=142 | security-review src/auth/login.js'
allowed-tools: Bash, Read, WebFetch
user-invocable: true
license: MIT
homepage: https://github.com/linnalihe/agent-skill-securityreview
repository: https://github.com/linnalihe/agent-skill-securityreview
author: linnalihe
---

# STEP 0: STALE-CLONE SELF-CHECK — RUN BEFORE READING BELOW

Before reading anything else in this file, check whether you loaded SKILL.md from a stale clone location. Claude Code auto-restores `~/.claude/plugins/marketplaces/` from `origin/main` on session start - this directory can lag the versioned plugin cache by one or more releases.

**Run this check:**

```bash
# sort -V (version sort) is GNU-only. macOS BSD sort silently falls back to lexicographic
# order, which breaks between e.g. 1.0.9 and 1.0.10. Use sort -t. -k1,1n -k2,2n -k3,3n
# as a portable numeric alternative that works on both GNU and BSD sort.
SKILL_CACHE_LATEST=$(find "$HOME/.claude/plugins/cache/agent-skill-securityreview/security-review" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)
SKILL_CACHE_MD=""
if [ -n "$SKILL_CACHE_LATEST" ]; then
  if [ -f "$SKILL_CACHE_LATEST/skills/security-review/SKILL.md" ]; then
    SKILL_CACHE_MD="$SKILL_CACHE_LATEST/skills/security-review/SKILL.md"
  elif [ -f "$SKILL_CACHE_LATEST/SKILL.md" ]; then
    SKILL_CACHE_MD="$SKILL_CACHE_LATEST/SKILL.md"
  fi
fi
echo "SKILL_CACHE_MD=$SKILL_CACHE_MD"
```

If the SKILL.md path you just Read contains `/.claude/plugins/marketplaces/` AND `$SKILL_CACHE_MD` is non-empty, STOP and re-read `$SKILL_CACHE_MD` before proceeding. Otherwise the SKILL.md you have is fine - continue.

---

# OUTPUT CONTRACT — READ BEFORE EMITTING ANY RESPONSE

These laws are at the top of the file because rules buried past line 500 get missed when the model reads SKILL.md in chunks. Do not synthesize a response without reading this section.

**BADGE (MANDATORY, FIRST LINE OF OUTPUT — LAW 0):**

The scripts (`scan_patterns.sh`, `dependency_audit.sh`, `preflight.sh`) emit the badge as their first stdout line. When you pass through script output verbatim, the badge appears automatically. If you are synthesizing your own output without running a script first, emit:

```
🔒 security-review v{VERSION} · reviewed {YYYY-MM-DD}
```

Replace `{VERSION}` with the installed version (`jq -r '.version' "$SKILL_DIR/../../.claude-plugin/plugin.json" 2>/dev/null || echo "?"`) and `{YYYY-MM-DD}` with today's date. One blank line after, then the review begins.

**Why the badge is mandatory:** it anchors the output format. Without it the model drifts into generic "code review" mode and drops the structured finding format, the OWASP codes, the CWE numbers, and the explicit merge recommendation. The badge is the single structural signal that the full SKILL.md contract was followed.

---

**LAW 1 - MERGE RECOMMENDATION IS MANDATORY AND MUST BE FIRST.**

For every PR/diff review (Mode A), the first content line after the badge is:

```
**Recommendation: [Request changes | Approve with comments | Approve]**
```

- Any Critical or High finding → **Request changes**
- Medium/Low only → **Approve with comments**
- No findings → **Approve**

Never bury the recommendation. Never omit it. Never make the reader parse the whole review to determine whether to block the merge.

**Named failure mode:** model produces a thorough finding list with severity-grouped sections but puts the recommendation at the end as a summary sentence. The reader looks at line 1. It must be line 1.

---

**LAW 2 - NO INVENTED VULNERABILITIES. EVERY FINDING REQUIRES A REAL LOCATION.**

Every finding must include a specific `file:line` from the actual code reviewed. Do not report "this pattern is likely present" or "this class of vulnerability is common in codebases like this" without a concrete location. If a check cannot be completed (file not accessible, context outside the diff, tool not available), say so explicitly in the "Couldn't verify" section - never speculate about what might be there.

**Named failure mode (pattern hit without context read):** model reads a `scan_patterns.sh` hit for `eval(` and reports "A05 Injection: eval() used on user input" without opening the file. The actual code is `eval("1 + 1")` in a test file with no user input. Read every hit in surrounding context (the full function, not just the matched line) before reporting it as a finding.

---

**LAW 3 - NO WORKING EXPLOITS.**

Illustrative payloads to demonstrate the bug class are allowed:
- `' OR '1'='1` to show SQL injection
- `<script>alert(1)</script>` to show XSS
- A command like `; cat /etc/passwd` to show shell injection

Full exploitation scripts, weaponized shellcode, chained payloads that would cause real damage in a real system, and working authentication bypass sequences are not allowed. If explaining a finding requires more than a brief illustrative payload, describe the attack path in plain language instead.

---

**LAW 4 - NEVER FIX BY HIDING.**

Do not:
- Silence an exception to stop a crash (`except: pass` instead of handling the error)
- Disable a security control to make a test pass (`// eslint-disable-next-line`)
- Add a `# nosec` / `// nosec` comment to suppress a scanner alert without fixing the underlying issue
- Remove a log line that was logging sensitive data without replacing it with a safe alternative

If the correct fix requires a design decision (what should this function do when the downstream call fails? what is the right error response to return to the user?), flag it for human judgment rather than applying the wrong mechanical fix.

---

**LAW 5 - PASS THROUGH SCRIPT OUTPUT VERBATIM BEFORE SYNTHESIZING.**

When `scan_patterns.sh` or `dependency_audit.sh` is invoked via Bash, read the full stdout before reasoning about findings. Never summarize scanner output without reading the actual hits. A "no findings" report for a category where the scanner had hits is a LAW 2 violation.

This applies to `A03 TOOL MISSING:` lines from `dependency_audit.sh` - these must appear in the report, not be silently omitted. An incomplete audit is not the same as a clean audit.

---

**LAW 6 - "WHAT I CHECKED BUT DIDN'T FLAG" IS MANDATORY.**

Every review (Mode A and Mode B) must include a section noting security-sensitive areas that were inspected and found clean. This tells the reader the review was thorough, not just "no patterns matched." A review with zero clean-bill entries is indistinguishable from a review that didn't look.

For Mode A: list the security-sensitive hunks in the diff that were read and found OK.
For Mode B: list the modules/directories with security relevance that were audited clean.

---

End of OUTPUT CONTRACT. Everything below is the execution contract.

---

# SKILL CONTRACT — READ BEFORE ANY TOOL CALL

You are inside the `/security-review` skill. This is a specific security review tool with a structured execution contract. Do NOT treat `/security-review` as a generic "check the code for bugs" prompt.

**What this skill is:** a defensive security review tool covering OWASP Top 10:2025. It finds vulnerabilities, explains why they're exploitable in plain language, and proposes concrete fixes with before/after diffs.

**What this skill is not:** a penetration testing tool, an exploit generator, an attack automation tool, or a generic code quality reviewer. Security findings are the focus; style issues, performance problems, and architectural suggestions are out of scope unless they have direct security implications.

---

# STEP 1: RESOLVE SKILL_DIR

`SKILL_DIR` is the directory containing the SKILL.md you just Read. Set it before any script invocation:

```bash
SKILL_DIR="<absolute path of the directory containing this SKILL.md>"
```

All script paths below use `$SKILL_DIR`. This is what makes the skill work correctly across every install path (Claude Code plugin cache, `npx skills` global install, symlinked checkout, OpenClaw, etc.) without enumerating install locations.

---

# STEP 2: PREFLIGHT

Before any review work, run:

```bash
bash "$SKILL_DIR/scripts/preflight.sh"
```

Read the output. Note any missing tools in your response before the review begins. The preflight never fails - it only reports. Adjust the review scope based on what's available:

- `rg` missing → pattern scanning uses grep fallback (slower, may miss some patterns - note this)
- `git` missing → diff access unavailable; Mode A requires manually pasted diff
- `gh` missing → `--pr=<number>` unavailable; user must paste the diff
- Ecosystem audit tools missing → note in the A03 section that the audit was incomplete

---

# STEP 3: DETECT MODE AND GET THE TARGET

**Parse the invocation for mode signals:**

| Signal | Mode |
|--------|------|
| `--pr=<number>`, "review PR #N", a diff is present in context, branch comparison | **Mode A: PR/Diff Review** |
| "audit this repo", "audit this codebase", a directory path with no diff context | **Mode B: Full Codebase Audit** |
| A single file path, a pasted code snippet, a file name mentioned without repo context | **Mode C: Snippet Review** |
| Nothing provided | **Ask** |

**If nothing was provided:** ask the user a single clarifying question:

> "What do you want me to review? A PR number (`--pr=142`), a path (`src/auth/`), or paste a snippet directly."

Wait for the answer. Never guess. Never start scanning the current directory blindly.

**Mode A - getting the diff:**

- If `--pr=<number>` was provided and `gh` is available:
  ```bash
  gh pr diff <number>
  ```
- If `--pr=<number>` was provided but `gh` is not available:
  > "I need the `gh` CLI to fetch PR #<number> automatically. Install with: `brew install gh && gh auth login`. Or paste the diff directly and I'll review it."
  Wait for the user.
- If a diff is already in context (pasted or from a previous tool call), use it directly.

**Mode B - inventory first:**

Before scanning, read enough of the repo to understand:
1. Languages and frameworks in use (check `package.json`, `requirements.txt`, `go.mod`, `Gemfile`, `Cargo.toml`, `pom.xml` as present)
2. Entry points: HTTP routes, CLI entrypoints, queue consumers, scheduled jobs
3. Trust boundaries: what's user-facing vs. internal-only
4. Where secrets/config live (`.env*`, `config/`, k8s secrets, CI env vars)

This mapping directs where reasoning budget goes. Skip it and you're scanning blind.

**Mode C - note scope limitations upfront:**

When reviewing a snippet without surrounding context, note at the top what can't be verified:
- "Cannot confirm whether this query is parameterized upstream"
- "Cannot verify whether the caller validates input before passing to this function"
- "Cannot check whether the session is validated before this endpoint is reached"

These are scope notes, not invented findings. They tell the reader what a complete review would need to check.

---

# STEP 4: MAP FILES TO CATEGORIES (Mode A and B)

Before reading line-by-line, map changed or in-scope files to likely OWASP categories. This focuses reasoning budget:

| Path / file pattern | Likely categories to check |
|---------------------|---------------------------|
| `**/auth/**`, `**/login*`, `**/session*`, middleware | A01, A07, A04 |
| `**/routes/**`, `**/controllers/**`, `**/handlers/**`, API endpoints | A01, A05, A10 |
| `**/models/**`, raw SQL, ORM query builders | A05, A01 |
| `package.json`, `requirements.txt`, `go.mod`, `Gemfile`, `pom.xml`, `Cargo.toml`, lockfiles | A03 |
| Dockerfile, k8s manifests, `*.config`, `.env*`, CI/CD YAML | A02, A03 |
| Crypto/hash/token/secret-handling code | A04 |
| File upload, dynamic includes, plugin loaders | A06, A08 |
| Deserialization (`pickle`, `unserialize`, `ObjectInputStream`, `yaml.load`) | A08 |
| `catch`/`except` blocks, error handlers, retry/transaction logic | A10, A09 |
| Logging calls, audit trail code | A09 |
| Business rules (limits, pricing, quotas, workflow states) | A06 |

---

# STEP 5: RUN THE PATTERN SCANNER

**For Mode A (PR/diff):** run scoped to only the changed files, not the whole repo.

```bash
# Get the list of changed files from the diff, then scan only those
bash "$SKILL_DIR/scripts/scan_patterns.sh" . <changed-file-1> <changed-file-2> ...
```

**For Mode B (full audit):** run in two passes. First a summary triage to see which categories have hits, then the full scan to read the actual lines:

```bash
# Pass 1: triage — see which categories have hits before reading thousands of lines
bash "$SKILL_DIR/scripts/scan_patterns.sh" --emit=summary <repo-root>

# Pass 2: full scan — read the actual hits for every category that had >0 hits in pass 1
bash "$SKILL_DIR/scripts/scan_patterns.sh" <repo-root>
```

If the triage pass shows zero hits for a category, you can skip the full-scan output for that category and go straight to the reasoning pass (Step 7). If it shows many hits (>20 in a single category), prioritize reading the highest-risk file paths first (auth, routes, models) before lower-risk ones.

**For Mode C (snippet):** skip the scanner. Reason directly over the pasted code.

**After the scan:**

- Read every hit in surrounding context. Open the enclosing function, not just the matched line.
- Confirm it's real before flagging. Check false-positive notes in `$SKILL_DIR/reference/A0X_*.md` for the relevant category.
- In Mode A: also check the diff for what's **missing** - a new endpoint with no authorization check, a new external call with no timeout, a new dependency with no version pin.

**Load only the relevant reference files** - not all ten. Reviewing a login endpoint: load A01, A04, A07. Reviewing CI config: load A02, A03. Load from `$SKILL_DIR/reference/`:

```bash
cat "$SKILL_DIR/reference/A01_broken_access_control.md"
```

---

# STEP 6: DEPENDENCY AUDIT (A03)

Run when any manifest or lockfile is in scope:

```bash
bash "$SKILL_DIR/scripts/dependency_audit.sh" <target-directory>
```

Pass through the output verbatim. Include any `A03 TOOL MISSING:` lines in the report - do not treat missing audit tools as "no findings."

---

# STEP 7: REASONING PASS FOR A06 AND A10

**Mandatory, even when the scanner found nothing in these categories.**

A06 (Insecure Design) and A10 (Mishandling of Exceptional Conditions) are pattern-invisible. The scanner's greppable subset catches a narrow slice. The real bugs require reading the code's logic.

For **A06**, ask explicitly for every business-logic function in scope:
- What happens if the user sends a price or quantity field directly from the client?
- What happens if a limit (rate limit, quota, booking cap) is enforced client-side only?
- What happens if a workflow state machine can be advanced out of order?
- What happens if a file upload bypasses content-type validation?

For **A10**, ask explicitly for every external call, transaction, and error handler:
- What happens if this downstream call fails halfway through a multi-step operation?
- What does the error response reveal to the caller? (stack trace? internal path? DB schema?)
- What happens if an exception is swallowed silently here?
- Is the transaction rolled back correctly if the second write fails after the first succeeds?

Flag design-level findings for human judgment rather than auto-applying a fix. These require business-context decisions you cannot resolve unilaterally.

---

# STEP 8: PRODUCE THE REVIEW

Use `$SKILL_DIR/templates/pr_review_comment.md` for Mode A, `$SKILL_DIR/templates/finding_report.md` for Mode B.

**Required structure for Mode A:**

```
🔒 security-review v{VERSION} · reviewed {YYYY-MM-DD}

**Recommendation: [Request changes | Approve with comments | Approve]**

<1-2 sentence summary: what this PR does, and the headline security takeaway.>

---

## 🔴 Must fix before merge

### <short title> — A0X <category name> (CWE-XXX)

**`path/to/file.ext:line`**

<what's wrong and why it matters in plain language - one or two sentences.>
<concrete exploit scenario: what an attacker would actually do.>

[before/after diff]

<repeat per Critical/High finding>

## 🟡 Worth addressing

<same format, for Medium findings>

## 🔵 Nits / hardening opportunities

- <short title> (`path/to/file.ext:line`) — <one-line description> [A0X]

## What I checked but didn't flag

<security-sensitive areas in this diff that were inspected and found clean>

## Couldn't verify from this diff alone

<anything that depends on context outside the diff>
```

**Required structure for Mode B:** use `$SKILL_DIR/templates/finding_report.md` directly.

**For Mode C:** use the Mode A format without the merge recommendation line. Note scope limitations at the top per Step 3.

---

# HARD RULES

- **Defensive only.** Never produce working exploits, attack automation, detection-evasion code, or tooling whose primary use is offensive.
- **Never fix by hiding.** See LAW 4.
- **Flag, don't auto-fix, design-level findings.** A06 and most of A10 require business-context decisions. Flag them for human judgment with enough context to make the decision, then stop.
- **Apply mechanical fixes directly when safe and unambiguous:** hardcoded secret → env var (and flag for rotation), MD5 → bcrypt/Argon2, missing security header → add it, unparameterized query → parameterize it. Say what you changed and why.
- **If a finding touches data already potentially exposed**, note that credential rotation or user notification may be needed. That's a process and legal decision for the user's team - do not act on it unilaterally.
- **Load only the relevant reference files per review.** Not all ten on every run. A06 doesn't need A01's reference file.

---

# REFERENCE FILES

Load from `$SKILL_DIR/reference/` as needed:

| File | Load when reviewing |
|------|---------------------|
| `A01_broken_access_control.md` | Auth middleware, route handlers, direct object references |
| `A02_security_misconfiguration.md` | Config files, Docker/k8s, CI/CD, framework settings |
| `A03_supply_chain.md` | Any manifest or lockfile change |
| `A04_cryptographic_failures.md` | Hashing, tokens, TLS, random number generation |
| `A05_injection.md` | SQL, shell, template, HTML sinks |
| `A06_insecure_design.md` | Business logic, limits, pricing, file upload, workflow |
| `A07_authentication_failures.md` | Login, session, password reset, MFA |
| `A08_integrity_failures.md` | Deserialization, CI pipelines, Docker image pulls |
| `A09_logging_alerting.md` | Logging calls, error handlers, audit trail |
| `A10_exceptional_conditions.md` | Error handlers, transactions, external calls, retry logic |
