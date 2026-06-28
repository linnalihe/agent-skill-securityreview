# A09:2025 Security Logging & Alerting Failures

Rank: #9. Hard to test for / underrepresented in CVE data, but consistently voted in by the
community because the impact (slow or missed breach detection) is severe - the cited real-world
example involved a breach that went undetected for over seven years due to lack of logging.

## What it is

Without adequate logging, monitoring, and *alerting* (not just logging - someone/something has
to actually notice), breaches go undetected for long periods and incident response/forensics
become impossible.

## Key CWEs

- CWE-778 Insufficient Logging
- CWE-117 Improper Output Neutralization for Logs (log injection)
- CWE-532 Insertion of Sensitive Information into Log File

## Detection signals

- Authentication code (login, password reset, MFA challenge, privilege change) with **no**
  logging call on the failure path - success-only logging is a common version of this bug.
- Access-control denial (A01) that isn't logged - if every IDOR/authz failure is silently
  rejected with no log entry, there's no way to detect an attacker probing for one.
- User input written directly into a log message with no encoding/sanitization - allows log
  injection (forging fake log entries, breaking log parsers, or injecting control characters).
  ```js
  // VULNERABLE: newline/control chars in `username` can forge fake log lines
  logger.info(`Login attempt for user: ${req.body.username}`);
  ```
- Sensitive data (passwords, full credit card numbers, tokens, session IDs, health/PII data)
  passed into a logging call - even temporarily during debugging.
  ```python
  # VULNERABLE
  logger.debug(f"User {user.email} logged in with password {password}")
  ```
- Logs written only to local disk with no shipping to a central, tamper-resistant store - a
  compromised host can delete its own evidence.
- No structured/correlated way to detect repeated failures (no counter, no rate-based alert
  hook) around sensitive actions.
- Error handling (cross-reference A10) that catches an exception but never logs it - the system
  has no record that anything went wrong at all.

## Fix patterns

```js
// FIXED: log failures with context, no sensitive data, encoded output
logger.warn('Login failed', {
  emailHash: hash(req.body.email), // avoid raw PII where a hash/ID suffices
  ip: req.ip,
  reason: 'invalid_credentials',
  // never log the password itself
});
```

```python
# FIXED
logger.warning("Login failed", extra={"user_id": user.id, "ip": request.remote_addr})
# never include the raw password/token in any log line, at any log level, even "debug"
```

**Other fixes:**

- Log every security-relevant event - successes *and* failures - for: login, logout, password
  change/reset, MFA challenge, access-control denial, privilege change, and high-value
  transactions.
- Use structured logging (JSON) so a log pipeline can parse and alert on it reliably; ensure
  the logging library encodes/escapes values automatically rather than naive string
  interpolation.
- Ship logs to a central, append-only store separate from the application host so a compromised
  host can't erase its own trail.
- Define concrete alert thresholds (e.g. N failed logins from one IP/account in T minutes) and
  an actual response playbook - logging without anyone/anything watching doesn't help.
- Consider honeytokens (fake credentials/records that should never be touched in normal use) -
  any access to them is a near-zero-false-positive breach signal.

## False-positive notes

- Verbose logging in a clearly test/dev-only code path is fine if it provably can't run in
  production (check the guard condition, not just the comment).
- Logging a user ID or hashed identifier (not raw PII) for correlation purposes is the
  recommended pattern, not a finding - don't flag every appearance of user-identifying data in
  logs, only raw secrets/PII/payment data.
