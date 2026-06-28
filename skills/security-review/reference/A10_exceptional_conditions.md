# A10:2025 Mishandling of Exceptional Conditions

Rank: #10. **New category for 2025.** Like A06, this is largely **reasoning-only** - the bugs
are in control flow and error-path logic, which pattern matching catches only partially (broad
catch blocks, missing default cases are greppable; fail-open business logic usually isn't).

## What it is

The application fails to prevent, detect, or properly respond to abnormal/unpredictable
conditions - leading to crashes, undefined state, resource exhaustion, information leaks via
error messages, or (most dangerously) "failing open" instead of "failing closed."

## Key CWEs

- CWE-636 Not Failing Securely ('Failing Open')
- CWE-755/703/754 Improper Handling/Check of Exceptional Conditions
- CWE-209/550 Generation of Error Message Containing Sensitive Information
- CWE-476 NULL Pointer Dereference
- CWE-460 Improper Cleanup on Thrown Exception
- CWE-234 Failure to Handle Missing Parameter
- CWE-396/397 Catching/Throwing Overly Generic Exceptions

## Detection signals

**Greppable signals**

```js
// VULNERABLE: swallowed error, no logging, no cleanup
try {
  await doSensitiveOperation();
} catch (e) {} // silently continues as if nothing happened

// VULNERABLE: stack trace leaked to client
app.use((err, req, res, next) => res.status(500).send(err.stack));
```
```python
# VULNERABLE: bare except, broad catch hides real failures
try:
    charge_card(amount)
except Exception:
    pass  # transaction state now unknown - did it charge or not?
```
```java
// VULNERABLE: generic catch, no rollback
try {
    debitAccount(from, amount);
    creditAccount(to, amount);
} catch (Exception e) {
    // no rollback of the debit if credit fails - money vanishes
}
```
Grep for: empty `catch`/`except` blocks, `except:`/`except Exception:` with no re-raise or
specific handling, `catch (Exception e)`/`catch (Throwable t)` generic catches, error responses
that include `err.stack`/`traceback`/full exception text in the HTTP response body.

**Reasoning-only signals (the more important half)**

1. **Multi-step operations**: does every step have a defined rollback if a *later* step fails?
   Walk the sequence (e.g. debit → credit → log) and ask what state the system is in if it dies
   between any two steps. "Fail closed" means: on any uncertainty, treat the transaction as
   *not* completed and roll back everything; don't try to resume partway through.
2. **Security checks specifically**: does a thrown exception during an authorization/validation
   check result in access being *denied* (fail closed) or *granted* (fail open)? E.g.
   `if (authCheckThrows) { return true; }` style logic, or a try/catch around an auth check
   where the catch block defaults to "allow."
3. **Resource cleanup**: are file handles/connections/locks released in a `finally`
   block / `with` statement / try-with-resources, or only on the happy path? A failure that
   skips cleanup repeated many times is a resource-exhaustion DoS.
4. **Missing limits**: is there any cap on retries, payload size, recursion depth, or
   concurrent requests for an operation that consumes a resource? Absence enables a DoS via
   resource exhaustion.
5. **Default/missing cases**: does a `switch`/`match` over a status or type have a default
   case that does something safe, or does an unhandled value silently fall through into
   unintended behavior?

## Fix patterns

```js
// FIXED: handle at the point of failure, fail closed, log, don't leak detail to the client
try {
  await doSensitiveOperation();
} catch (err) {
  logger.error('doSensitiveOperation failed', { err }); // full detail server-side (see A09)
  throw new AppError('Operation failed, please try again'); // generic message to caller
}

// FIXED: generic error handler never leaks internals
app.use((err, req, res, next) => {
  logger.error(err);
  res.status(500).json({ error: 'Internal server error' });
});
```

```python
# FIXED: rollback on partial failure, specific exception handling
def transfer(from_acct, to_acct, amount):
    with db.transaction():           # all-or-nothing
        debit(from_acct, amount)
        credit(to_acct, amount)
        log_transaction(from_acct, to_acct, amount)
    # if any step raises, the transaction context rolls back everything
```

```java
// FIXED: fail closed on auth check failure
boolean authorized;
try {
    authorized = authService.check(user, resource);
} catch (Exception e) {
    log.error("Auth check failed", e);
    authorized = false; // default DENY on any uncertainty, not allow
}
if (!authorized) throw new ForbiddenException();
```

**Other fixes:**

- Catch exceptions at the specific point they occur, not several layers up with a generic
  catch-all - specific handling lets you respond meaningfully instead of guessing.
- Always have a single, centralized global exception handler as a backstop, in addition to
  (not instead of) specific handling at each failure point.
- Roll back the entire multi-step operation on any failure - never try to resume partway
  through.
- Add rate limits, payload size limits, timeouts, and resource quotas everywhere a request can
  consume a resource - "unlimited" is itself a vulnerability.
- Scrub error messages shown to users; log full detail server-side only (pairs directly with
  A09).
- Handle identical repeated errors as aggregated statistics rather than flooding logs (helps
  A09's alerting signal-to-noise too).

## False-positive notes

- A broad catch block that re-throws or logs-and-rethrows (rather than swallowing) is generally
  fine - the problem is specifically catching-and-continuing as if nothing happened, or
  catching-and-defaulting to an unsafe state.
- Not every empty catch is exploitable - but flag it anyway at least as Low/Medium, since
  "exception silently discarded" is exactly the kind of thing that becomes a real bug later when
  the surrounding code changes and nobody notices the failure path stopped working.
