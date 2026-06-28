# Security Review: <repo/project name>

**Mode:** Full Codebase Audit
**Date:** <date>
**Scope:** <what was reviewed - whole repo, specific services/directories, etc.>
**Standard:** OWASP Top 10:2025 (https://owasp.org/Top10/2025/)

## Summary

| Severity | Count |
|---|---|
| Critical | N |
| High | N |
| Medium | N |
| Low / Informational | N |

<2-4 sentences: overall posture, the most important 1-2 things to fix first, and anything that
was out of scope or couldn't be verified (e.g. "rate limiting may exist at the infra layer,
not visible in this repo").>

## Findings

### [CRITICAL] <short title>

- **Category:** A0X - <OWASP category name>
- **CWE:** CWE-XXX <name>
- **Location:** `path/to/file.ext:line`
- **Description:** <what's wrong, in plain language>
- **Why it's exploitable:** <concrete scenario - what an attacker would actually do>
- **Fix:**

  ```diff
  - vulnerable line(s)
  + fixed line(s)
  ```

- **Status:** <Fixed directly in this review / Needs human decision - see rationale>

<repeat per finding, grouped by severity: Critical, then High, then Medium, then Low/Info>

## Dependency / Supply Chain Audit (A03)

<output of scripts/dependency_audit.sh, summarized - tool used, vulnerable packages found,
recommended version bumps>

## Out of scope / Could not verify

<anything the review couldn't confirm without more context - infra-level controls,
runtime configuration not in the repo, third-party service configuration, etc.>

## Recommended next steps

1. <highest priority>
2. <next>
3. <ongoing - e.g. "add SAST/dependency scanning to CI so these are caught automatically">
