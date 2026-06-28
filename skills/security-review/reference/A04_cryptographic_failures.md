# A04:2025 Cryptographic Failures

Rank: #4. Covers missing encryption, weak/broken crypto, key leakage, and weak randomness.

## What it is

Sensitive data (passwords, payment data, health records, PII, tokens, business secrets) isn't
adequately protected in transit or at rest, or the cryptography used to protect it is broken,
misconfigured, or relies on insufficient randomness.

## Key CWEs

- CWE-327 Use of a Broken or Risky Cryptographic Algorithm
- CWE-321 Use of Hard-coded Cryptographic Key
- CWE-330 Use of Insufficiently Random Values / CWE-338 Cryptographically Weak PRNG
- CWE-916 Use of Password Hash With Insufficient Computational Effort
- CWE-759/760 One-Way Hash without (or with predictable) Salt
- CWE-319 Cleartext Transmission of Sensitive Information
- CWE-329 Not Using a Random IV with CBC Mode
- CWE-295/296/297 Improper Certificate Validation

## Detection signals

**Generic / cross-language**

- `MD5` or `SHA1`/`SHA-1` used anywhere near "password", "hash", "token", or "signature" -
  these are broken for security purposes (collision-prone; MD5/SHA1 are fine for non-security
  checksums only - check the context).
- A hardcoded key, IV, salt, or secret as a string literal in source (`"my-secret-key"`,
  `SECRET = "..."`, a base64 blob assigned to a `key`/`iv` variable).
- `Math.random()` (JS), `random.random()` (Python's non-`secrets` module), or any
  non-cryptographic PRNG used to generate a token, session ID, password-reset code, or API key.
- TLS/cert verification disabled: `verify=False` (Python requests), `rejectUnauthorized: false`
  (Node), `NoopHostnameVerifier`/`X509TrustManager` that does nothing (Java), `curl -k` /
  `CURLOPT_SSL_VERIFYPEER, 0` in build/deploy scripts.
- AES used in ECB mode, or CBC mode with a fixed/zero/reused IV.
- A password used directly as an encryption key instead of through a KDF
  (PBKDF2/Argon2/scrypt).
- Sensitive data sent over plain HTTP, or `http://` URLs for endpoints handling
  credentials/tokens/payment data.

**JavaScript/Node**

```js
// VULNERABLE
const hash = crypto.createHash('md5').update(password).digest('hex');
const token = Math.random().toString(36); // predictable, not cryptographically secure
```

**Python**

```python
# VULNERABLE
import hashlib
hashed = hashlib.md5(password.encode()).hexdigest()

import random
reset_token = str(random.randint(100000, 999999))  # predictable PRNG
```

**Java**

```java
// VULNERABLE
MessageDigest md = MessageDigest.getInstance("MD5");
Cipher cipher = Cipher.getInstance("AES/ECB/PKCS5Padding"); // ECB mode
```

## Fix patterns

```js
// FIXED: password hashing
const bcrypt = require('bcrypt');
const hash = await bcrypt.hash(password, 12); // or argon2

// FIXED: secure random token
const token = crypto.randomBytes(32).toString('hex');
```

```python
# FIXED: password hashing
from argon2 import PasswordHasher
ph = PasswordHasher()
hashed = ph.hash(password)

# FIXED: secure random token
import secrets
reset_token = secrets.token_urlsafe(32)
```

```java
// FIXED: password hashing (use a library, e.g. Spring Security's Argon2PasswordEncoder)
Argon2PasswordEncoder encoder = Argon2PasswordEncoder.defaultsForSpringSecurity_v5_8();
String hash = encoder.encode(rawPassword);

// FIXED: AES-GCM (authenticated encryption) instead of ECB/CBC
Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
```

**Other fixes:**

- Classify data sensitivity; ensure anything sensitive is encrypted at rest and in transit.
- Enforce TLS ≥ 1.2 everywhere; add HSTS; never disable certificate validation, including in
  test/dev code that might get copy-pasted into production paths.
- Never hardcode keys/secrets - load from a secrets manager/KMS/HSM, and rotate immediately if
  one is found committed to source history (not just removed going forward).
- Use authenticated encryption (AES-GCM) rather than plain CBC/ECB.
- Store secrets out of source control entirely; add a pre-commit secret scanner if none exists.
- Don't retain sensitive data longer than necessary - discard or tokenize/truncate it.

## False-positive notes

- MD5/SHA1 used purely as a non-security checksum (e.g. detecting file changes, cache keys) is
  not a cryptographic failure - confirm the *purpose* of the hash before flagging as Critical;
  still worth a Low/informational note recommending SHA-256 for clarity, but don't treat it the
  same as a broken password hash.
- `Math.random()` used for non-security randomness (UI animation jitter, A/B test bucketing)
  is fine - the issue is specifically when it backs a security-relevant value (tokens, IDs,
  password reset codes, anything an attacker could predict to their advantage).
