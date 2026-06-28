# Security Review: <PR title / branch>

**Recommendation:** <Request changes | Approve with comments | Approve>
**Standard:** OWASP Top 10:2025

<1-2 sentence summary: what this PR does, and the headline security takeaway.>

---

## 🔴 Must fix before merge

### <short title> - A0X <category name> (CWE-XXX)

**`path/to/file.ext:line`**

<what's wrong and why it matters, in plain language - one or two sentences.>

```diff
- vulnerable line(s)
+ suggested fix
```

<repeat for every Critical/High finding>

## 🟡 Worth addressing

### <short title> - A0X <category name> (CWE-XXX)

**`path/to/file.ext:line`**

<description + suggested fix, same format as above, for Medium findings>

## 🔵 Nits / hardening opportunities

- <short title> (`path/to/file.ext:line`) - <one-line description> [A0X]
- <repeat for Low/Informational findings - these can be one-liners, no diff required>

## What I checked but didn't flag

<briefly note security-sensitive areas touched by this PR that were reviewed and found OK -
this tells the reader the review was thorough, not just "no patterns matched.">

## Couldn't verify from this diff alone

<anything that depends on context outside the diff - e.g. "assumes the rate-limiting middleware
registered in app.js still wraps this new route - please confirm.">
