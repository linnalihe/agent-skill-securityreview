# A07:2025 Authentication Failures

Rank: #7 (unchanged since 2021; slight name change from "Identification and Authentication
Failures"). 36 CWEs mapped.

## What it is

The system can be tricked into treating an invalid/incorrect user as legitimate - via credential
stuffing, brute force, weak password policy, broken session management, or missing/ineffective
MFA.

## Key CWEs

- CWE-287 Improper Authentication
- CWE-307 Improper Restriction of Excessive Authentication Attempts (no lockout/throttle)
- CWE-384 Session Fixation
- CWE-613 Insufficient Session Expiration
- CWE-798/259/1392/1393 Hard-coded or default credentials
- CWE-640 Weak Password Recovery Mechanism
- CWE-521 Weak Password Requirements
- CWE-308 Use of Single-factor Authentication

## Detection signals

**Generic / cross-language**

- Login endpoint with no rate limiting, lockout, or progressive delay after failed attempts -
  check for any throttling middleware/logic around the auth route; absence is the finding.
- Login/registration/password-reset error messages that differ for "user doesn't exist" vs.
  "wrong password" (enables account enumeration) - e.g. `"No account with that email"` vs.
  `"Incorrect password"`.
- Session ID generated with a non-cryptographic source (cross-reference A04), or the *same*
  session ID kept across the login transition (session fixation) instead of regenerating after
  authentication.
- Session/auth token placed in the URL (`?session=...`, `?token=...`) rather than a header or
  secure cookie - it'll end up in logs, browser history, and `Referer` headers.
- No session invalidation on logout (cookie/token isn't actually revoked server-side, or the
  client just discards it locally while the server-side session stays valid).
- Hardcoded credentials anywhere in source - `password = "..."`, `if username == "admin" and
  password == "..."`, seed/fixture data with weak defaults that ships into a real environment.
- New-password validation that *only* checks length/character-class complexity but never checks
  against a breached-password list, and/or forces periodic rotation (NIST 800-63b now advises
  against forced rotation - it pushes users toward weaker, incrementing passwords).
- JWT verification missing `aud`/`iss`/`exp` checks, or accepting `alg: none` /
  algorithm-confusion (a token signed with HS256 accepted when the verifier expects RS256, or
  vice versa - check the library defaults).

**JavaScript/Node**

```js
// VULNERABLE: no rate limit, enumerable error messages
app.post('/login', async (req, res) => {
  const user = await User.findOne({ email: req.body.email });
  if (!user) return res.status(401).json({ error: 'No account with that email' }); // enumerable
  if (!bcrypt.compareSync(req.body.password, user.passwordHash)) {
    return res.status(401).json({ error: 'Incorrect password' }); // enumerable
  }
  req.session.userId = user.id; // existing session ID reused, not regenerated
  res.json({ ok: true });
});
```

**Python**

```python
# VULNERABLE: hardcoded credential fallback
if username == "admin" and password == "changeme123":
    return grant_admin_session()
```

## Fix patterns

```js
// FIXED
app.post('/login', loginRateLimiter, async (req, res) => {
  const user = await User.findOne({ email: req.body.email });
  const valid = user && await bcrypt.compare(req.body.password, user.passwordHash);
  if (!valid) {
    await logFailedLogin(req.body.email, req.ip); // for alerting, see A09
    return res.status(401).json({ error: 'Invalid username or password' }); // uniform message
  }
  req.session.regenerate(() => {              // new session ID after auth - prevents fixation
    req.session.userId = user.id;
    res.json({ ok: true });
  });
});
```

**Other fixes:**

- Enforce MFA wherever feasible, especially for admin/privileged accounts.
- Check new/changed passwords against a breached-password list (e.g. via a k-anonymity API like
  HaveIBeenPwned's range search) and a top-10k-worst-passwords list.
- Align length/complexity policy with NIST 800-63b: favor length over forced complexity/rotation;
  only force a reset when a breach is suspected/confirmed.
- Use a vetted session/auth library rather than hand-rolling session management; regenerate the
  session ID on privilege change (login, role elevation); invalidate server-side on logout and
  on idle/absolute timeout.
- Verify JWT `aud`, `iss`, `exp`, and pin the expected signing algorithm explicitly (don't trust
  the algorithm declared in the token header).
- Remove every hardcoded/default credential before merge - no exceptions for "just for now."

## False-positive notes

- Rate limiting implemented at the infrastructure/API-gateway layer (not visible in this repo's
  application code) means the absence of in-app throttling isn't necessarily a finding -
  confirm before flagging, and note the assumption either way in the review.
- A clearly-test-only fixture/mock credential used solely in test files (never read by
  production code paths) is not a finding by itself, but flag it as Low if there's any risk it
  could be deployed or if the test file pattern is loose enough to be bundled into a build.
