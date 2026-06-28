# /security-review

An AI agent skill that reviews pull requests and codebases for security vulnerabilities against the [OWASP Top 10:2025](https://owasp.org/Top10/2025/) - the current, official list of the most critical web application security risks.

Give it a PR number, a file path, or a code snippet. It tells you what's exploitable, why, and exactly how to fix it - with before/after diffs, not just prose.

---

## What it does

**Three review modes:**

| Mode | When to use it | Trigger |
|------|----------------|---------|
| **PR / Diff review** | Before merging a pull request | `/security-review --pr=142` or "review this PR" with a diff in context |
| **Full codebase audit** | Onboarding a new repo, periodic audit, incident follow-up | `/security-review` in a repo with no diff context |
| **Snippet review** | A single file or pasted block | Paste code and ask "is this safe?" |

**What you get in every review:**

- A top-line merge recommendation (Request changes / Approve with comments / Approve) on the first line - never buried
- Findings grouped by severity: Critical, High, Medium, Low/Informational
- Each finding includes: OWASP category code, CWE number, exact file and line, plain-language exploit scenario, and a concrete fix as a diff
- A "What I checked but didn't flag" section so you know the review was thorough, not just "no patterns matched"
- A "Couldn't verify from this diff alone" section for anything that depends on context outside what was shared

**Coverage:**

| Code | Category | How it's caught |
|------|----------|-----------------|
| A01 | Broken Access Control | Pattern scan + reasoning over access-control paths |
| A02 | Security Misconfiguration | Pattern scan (debug flags, XXE-permissive parsers, missing headers) |
| A03 | Software Supply Chain Failures | `dependency_audit.sh` runs npm audit / pip-audit / govulncheck / bundler-audit / cargo-audit per ecosystem |
| A04 | Cryptographic Failures | Pattern scan (MD5/SHA1/DES, Math.random() for secrets, disabled TLS verification, hardcoded keys) |
| A05 | Injection | Pattern scan (string-built SQL, shell=True, eval, dangerouslySetInnerHTML) |
| A06 | Insecure Design | Reasoning only - the model reads business-logic paths the scanner can't reach |
| A07 | Authentication Failures | Pattern scan + reasoning (hardcoded credentials, enumerable error messages, session handling) |
| A08 | Software/Data Integrity Failures | Pattern scan (pickle.loads, yaml.load, :latest Docker tags, mutable CI action refs) |
| A09 | Security Logging & Alerting Failures | Pattern scan + reasoning (sensitive data in logs, silent catch blocks) |
| A10 | Mishandling of Exceptional Conditions | Reasoning only - empty except blocks, stack traces returned to clients, broken transaction rollback |

**Severity tiers:**

| Severity | Definition |
|----------|-----------|
| **Critical** | Remotely exploitable, no auth required, high impact (RCE, auth bypass, full data exposure) |
| **High** | Exploitable with some precondition, or high impact but harder to reach (IDOR, missing auth on admin routes, SSRF, stored XSS) |
| **Medium** | Real weakness but limited blast radius (missing security headers, weak password policy, reflected XSS needing user interaction) |
| **Low / Info** | Defense-in-depth gap, hardening opportunity (missing rate limiting on a low-value endpoint, outdated-but-unaffected dependency) |

**Hard limits:**

- Defensive only. It finds and fixes vulnerabilities; it never writes working exploits, malware, or offensive tooling.
- No fixing by hiding. It won't silence an exception to stop a crash or disable a CSP header to make a test pass.
- Design-level findings (A06, most of A10) are flagged for human judgment, not auto-fixed - they require business-context decisions the skill can't resolve unilaterally.
- If a finding touches data that may already be exposed, it notes that credential rotation or notifying affected parties may be needed - that's a process and legal decision for your team.

---

## Install

### Claude Code (recommended)

```
/plugin marketplace add linnalihe/agent-skill-securityreview
```

The Claude Code marketplace handles updates automatically. To force an update check:

```
claude plugin update security-review@agent-skill-securityreview
```

### Codex, Cursor, Gemini CLI, GitHub Copilot, and other Agent Skills hosts

```bash
npx skills add linnalihe/agent-skill-securityreview -g
```

The `-g` flag installs globally so the skill is available across all your projects. Drop it to install project-locally into `./.skills/` instead.

Update later with:

```bash
npx skills update security-review -g
```

### claude.ai (web)

1. Download `security-review.skill` from the [latest release](https://github.com/linnalihe/agent-skill-securityreview/releases/latest)
2. Go to [claude.ai > Customize > Skills](https://claude.ai/customize/skills)
3. Click **+** > **Create skill** > **Upload a skill** and upload the file

Enable **Code execution and file creation** under Capabilities - skills won't run without it.

### Manual (developer / contributor)

```bash
git clone https://github.com/linnalihe/agent-skill-securityreview.git
ln -s "$(pwd)/agent-skill-securityreview/skills/security-review" ~/.claude/skills/security-review
```

The symlink keeps your install in sync with the working tree as you edit. No re-copy needed.

---

## Prerequisites

The skill degrades gracefully when tools are missing - it always tells you what it couldn't check rather than silently skipping - but for full coverage you want:

| Tool | Why it's needed | Install |
|------|-----------------|---------|
| `rg` (ripgrep) | Fast pattern scanning across all 10 OWASP categories. Falls back to `grep` if missing, but slower and less accurate. | `brew install ripgrep` / `apt install ripgrep` |
| `git` | Diff access for PR and branch reviews. Required for Mode A; not needed for snippet review. | Ships with most systems |
| `gh` (GitHub CLI) | Fetches PR diffs by number (`--pr=142`) without manual copy-paste. | `brew install gh` then `gh auth login` |
| `pip-audit` | Python dependency audit (A03). | `pip install pip-audit` |
| `govulncheck` | Go dependency audit (A03). | `go install golang.org/x/vuln/cmd/govulncheck@latest` |
| `bundler-audit` | Ruby dependency audit (A03). | `gem install bundler-audit` |
| `cargo-audit` | Rust dependency audit (A03). | `cargo install cargo-audit` |

`npm audit` runs automatically when Node is detected - no extra install needed beyond having `npm` on PATH.

---

## Usage examples

```
/security-review --pr=142
```
Fetches PR #142 via the GitHub CLI, maps changed files to OWASP categories, runs the pattern scanner scoped to only the changed files, deep-reads security-sensitive hunks, and produces a review with a merge recommendation.

```
/security-review
```
Full codebase audit from the current directory. Scans everything, runs `dependency_audit.sh` against any manifest files found, and produces a `finding_report.md`-format output.

```
/security-review src/auth/login.js
```
Scoped audit of a single file. Useful when you've just written something security-sensitive and want a quick check before committing.

---

## How it works

1. **Mode detection.** Is this a PR diff, a full repo, or a snippet? The mode determines what gets fetched and which scripts run.
2. **Preflight check.** The skill checks which tools (rg, git, gh, ecosystem audit tools) are available and notes any degradation upfront.
3. **File-to-category mapping.** Changed files are mapped to likely OWASP categories before any line-by-line reading, so reasoning budget goes to the right places.
4. **Pattern scan.** `scripts/scan_patterns.sh` runs ripgrep across all 10 categories scoped to the relevant files. Every hit is a candidate, not a finding - the scanner casts a wide net fast.
5. **Context read.** Every pattern hit is read in surrounding context (the full function, not just the matched line) before being reported. This eliminates false positives from test fixtures, commented-out code, and similar.
6. **Reasoning pass.** Categories that grep can't catch (A06 Insecure Design, A10 Exceptional Conditions, access-control logic) get a deliberate reasoning pass over security-sensitive code paths, even when the scanner found nothing.
7. **Supply chain audit.** `scripts/dependency_audit.sh` detects manifest files and runs the right native audit tool per ecosystem.
8. **Structured output.** Findings are grouped by severity, each with OWASP code, CWE, file:line, exploit scenario, and a concrete fix diff. The merge recommendation is always the first line.

---

## Files in this repo

```
skills/security-review/
├── SKILL.md                    # The skill contract - what the model reads and follows
├── scripts/
│   ├── scan_patterns.sh        # Ripgrep-based OWASP pattern scanner
│   ├── dependency_audit.sh     # Ecosystem-aware supply chain audit
│   └── preflight.sh            # Tool availability check (rg, git, gh, audit tools)
├── reference/
│   └── A0X_*.md               # One reference file per OWASP category: CWEs, detection signals, fix patterns, false-positive notes
└── templates/
    ├── pr_review_comment.md    # Output format for Mode A (PR review)
    └── finding_report.md       # Output format for Mode B (full audit)
tests/
└── fixtures/                   # Known-bad code samples for scanner regression tests
```

---

MIT license. Defensive security only.
