---
name: owasp-security-review
description: "Use this skill when reviewing source code, a pull request, a diff, or a codebase for security vulnerabilities, bugs, or potential data leaks - including requests like 'security review', 'audit this code', 'check for vulnerabilities', 'OWASP scan', 'is this PR safe to merge', 'find security bugs', 'pentest this', or any code review where security/hardening matters. Implements detection and remediation guidance for all 10 categories of the OWASP Top 10:2025 Application Security Risks (Broken Access Control, Security Misconfiguration, Software Supply Chain Failures, Cryptographic Failures, Injection, Insecure Design, Authentication Failures, Software/Data Integrity Failures, Security Logging & Alerting Failures, Mishandling of Exceptional Conditions). Trigger this proactively any time code touching auth, access control, payments, file uploads, deserialization, crypto, secrets, SQL/shell/template construction, or error handling is being written, edited, or reviewed - not just when security is mentioned explicitly. This skill is strictly DEFENSIVE: it finds and fixes vulnerabilities. It must never be used to write malware, working exploits, or offensive tooling."
license: Use freely, modify for your own security review workflows.
---

# OWASP Top 10:2025 Security Review Skill

## Purpose

This skill turns an agent into a security reviewer that checks code against the
[OWASP Top 10:2025](https://owasp.org/Top10/2025/) - the current, official list of the
most critical web application security risks. It is built for two concrete jobs:

1. **Reviewing a pull request / diff** before merge (most common use case).
2. **Auditing a full codebase** on request (onboarding a new repo, periodic audit, incident follow-up).

It is **defensive only**. The goal is always: find the bug, explain why it's exploitable in
plain terms, and propose a concrete fix. Never produce a weaponized exploit, never write
code whose purpose is to attack a system, and never "fix" one vulnerability by introducing
another (e.g. silencing an error by swallowing exceptions, or "fixing" XSS by disabling CSP).

## Core principle: pattern-matching finds the obvious, reasoning finds the real bugs

Two-thirds of these categories (A01, A02, A04, A05, A08) have mechanical signatures that
regex/static patterns catch reliably. The rest (A03 partially, A06, A07 partially, A09, A10)
are **business-logic or process failures** that no pattern bank catches - they require
actually reading the code path and asking "what happens if this input is malicious / this
step fails / this check is bypassed?" Do not stop at the pattern scan. Treat it as a fast
first pass that narrows where to spend deep-reasoning attention, not as the review itself.

## Step 0: figure out the mode

| Signal | Mode |
|---|---|
| "review this PR", a git diff is present, branch comparison requested | **Mode A: PR/Diff Review** |
| "audit this repo/codebase", no diff context, onboarding a new project | **Mode B: Full Audit** |
| A single file or snippet is pasted with no repo context | **Mode C: Snippet Review** - apply the same category checklist, scoped to what's visible; note in the output what can't be verified without seeing the surrounding code (e.g. "can't confirm this query is parameterized upstream") |

## Mode A: Pull Request / Diff Review

1. **Get the diff.** Prefer `git diff <base>...<head>` or `git diff --stat` first to see scope,
   then the full diff. If reviewing a hosted PR, use whatever tool/MCP is available to fetch it.
2. **Map changed files to likely categories** before reading line-by-line - this focuses attention:

   | Path / file pattern | Likely categories |
   |---|---|
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
   | Anything implementing a business rule (limits, pricing, quotas, workflow states) | A06 |

3. **Run the pattern scan** (`scripts/scan_patterns.sh`) scoped to *only the changed files* listed
   in the diff - don't waste time re-scanning the whole repo for a PR review.
4. **Read every hit in context** - open the surrounding function, not just the matched line.
   Confirm it's real before flagging it (see false-positive notes in each reference file).
5. **Deliberately re-read security-sensitive hunks that got zero pattern hits.** Access-control
   bugs, business-logic flaws, and exceptional-condition mishandling are usually pattern-invisible.
   Ask explicitly: *what does this code do if the user is unauthorized / the input is hostile /
   a downstream call fails halfway through?*
6. **Check the diff for what's missing, not just what's added** - e.g. a new endpoint with no
   authorization check, a new external call with no timeout/error handling, a new dependency
   added with no version pin.
7. **Produce the review** using `templates/pr_review_comment.md` - grouped by severity, each
   finding citing the OWASP category + CWE + file:line + a concrete fix (as a diff/snippet, not
   just prose) + a one-line exploit scenario in plain language.
8. **Give a merge recommendation**: any Critical or High finding → "Request changes." Medium/Low
   → "Approve with comments." Always state this explicitly at the top of the review.

## Mode B: Full Codebase Audit

1. **Inventory** the repo: languages/frameworks in use, entry points (HTTP routes, CLI, queue
   consumers, scheduled jobs), trust boundaries (what's user-facing vs. internal-only), and where
   secrets/config live.
2. **Run `scripts/scan_patterns.sh`** across the whole tree and **`scripts/dependency_audit.sh`**
   against any manifest/lockfiles found.
3. **Triage** every hit, then deliberately deep-read the modules pattern-scanning is weak on:
   auth/session management, access-control middleware, payment/business-limit logic, error
   handlers, and the logging layer - even where no pattern fired.
4. **Produce the full report** using `templates/finding_report.md`.

## Severity rubric

Loosely follows OWASP's own exploitability × impact weighting (see each category's score table
on owasp.org) collapsed into four practical tiers:

| Severity | Definition | Examples |
|---|---|---|
| **Critical** | Remotely exploitable, no auth required, high impact (RCE, auth bypass, full data exposure) | SQL injection on an unauthenticated endpoint, hardcoded admin credential, insecure deserialization of untrusted input |
| **High** | Exploitable with some precondition (auth as a low-priv user, specific input) or high impact but harder to reach | IDOR on an authenticated endpoint, missing access control on an admin route, SSRF, stored XSS |
| **Medium** | Real weakness but limited blast radius or requires unusual conditions | Missing security headers, weak password policy, verbose error messages, reflected XSS needing user interaction |
| **Low / Informational** | Best-practice deviation, defense-in-depth gap, hardening opportunity | Missing rate limiting on a low-value endpoint, outdated-but-unaffected dependency, missing audit log on a non-sensitive action |

## Category quick reference

| Code | Category | Reference file | Mostly caught by |
|---|---|---|---|
| A01 | Broken Access Control | `reference/A01_broken_access_control.md` | pattern + reasoning |
| A02 | Security Misconfiguration | `reference/A02_security_misconfiguration.md` | pattern |
| A03 | Software Supply Chain Failures | `reference/A03_supply_chain.md` | tooling (`dependency_audit.sh`) |
| A04 | Cryptographic Failures | `reference/A04_cryptographic_failures.md` | pattern |
| A05 | Injection | `reference/A05_injection.md` | pattern + reasoning |
| A06 | Insecure Design | `reference/A06_insecure_design.md` | reasoning only |
| A07 | Authentication Failures | `reference/A07_authentication_failures.md` | pattern + reasoning |
| A08 | Software/Data Integrity Failures | `reference/A08_integrity_failures.md` | pattern |
| A09 | Security Logging & Alerting Failures | `reference/A09_logging_alerting.md` | pattern + reasoning |
| A10 | Mishandling of Exceptional Conditions | `reference/A10_exceptional_conditions.md` | reasoning only |

Load the specific reference file(s) relevant to the code being reviewed rather than all ten at
once - e.g. reviewing a login endpoint should pull A01, A04, A07; reviewing CI config should pull
A02, A03.

## Hard rules

- **Never write a working exploit/PoC payload beyond the minimum needed to illustrate the bug**
  (e.g. `' OR '1'='1` to illustrate SQLi is fine; a full automated exploitation script is not).
- **Never "fix" a vulnerability by hiding the symptom** - don't silence an error instead of
  handling it, don't catch-and-ignore an exception to stop a crash, don't disable a security
  control to make a test pass.
- **Flag design-level findings (A06, most of A10) for human judgment** rather than auto-applying
  a fix - these require business-context decisions (what's a legitimate vs. abusive booking
  pattern, what's the correct rollback behavior for a given transaction) that the skill cannot
  resolve unilaterally.
- **Apply mechanical fixes directly** when safe and unambiguous (hardcoded secret → env var +
  flag for rotation, MD5 → bcrypt/Argon2, missing security header → add it, unparameterized
  query → parameterize it) and say what you changed and why.
- If a finding touches data already exposed/leaked, note that rotating credentials or notifying
  affected parties may be needed - that's a process/legal decision for the user's team, not
  something to act on unilaterally.

## Files in this skill

- `reference/A0X_*.md` - one file per OWASP category: key CWEs, detection signals (by language),
  fix patterns with before/after code, false-positive notes.
- `scripts/scan_patterns.sh` - ripgrep-based first-pass scanner across all ten categories.
- `scripts/dependency_audit.sh` - detects manifests and runs the right native audit tool
  (`npm audit`, `pip-audit`, `govulncheck`, `bundler-audit`, `cargo-audit`) per ecosystem.
- `templates/finding_report.md` - full audit report format (Mode B).
- `templates/pr_review_comment.md` - PR review comment format (Mode A).
