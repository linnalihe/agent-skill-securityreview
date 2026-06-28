# A08:2025 Software or Data Integrity Failures

Rank: #8. Distinct from A03 (Supply Chain): this is about failing to *verify the integrity* of
code/data at the point it's trusted and used, at a lower level than the supply chain as a whole.

## What it is

Code or infrastructure treats data/updates/objects as trusted without verifying they actually
came from where they claim to, or weren't tampered with - most commonly: insecure
deserialization, unsigned auto-updates, and unverified third-party content inclusion.

## Key CWEs

- CWE-502 Deserialization of Untrusted Data
- CWE-829 Inclusion of Functionality from Untrusted Control Sphere
- CWE-830 Inclusion of Web Functionality from an Untrusted Source
- CWE-494 Download of Code Without Integrity Check
- CWE-345 Insufficient Verification of Data Authenticity
- CWE-915 Improperly Controlled Modification of Dynamically-Determined Object Attributes

## Detection signals

**Insecure deserialization - the highest-impact signal in this category**

```python
# VULNERABLE
import pickle
state = pickle.loads(request_data)  # arbitrary code execution if request_data is attacker-controlled

import yaml
config = yaml.load(user_supplied_yaml)  # unsafe loader can instantiate arbitrary Python objects
```
```java
// VULNERABLE
ObjectInputStream ois = new ObjectInputStream(socket.getInputStream());
Object obj = ois.readObject(); // classic Java deserialization RCE vector
```
```php
// VULNERABLE
$obj = unserialize($_COOKIE['state']);
```
```js
// VULNERABLE (Node) - rare but watch for) custom binary deserializers or
// node-serialize style libraries operating on client-supplied data
```
Grep for: `pickle.loads`, `yaml.load(` (without `Loader=yaml.SafeLoader`), `unserialize(`,
`ObjectInputStream`, `readObject()`, `Marshal.load` (Ruby) - applied to anything that
originates from a request, cookie, or other client-controlled source. The giveaway in traffic:
a base64 blob starting with `rO0` (Java serialized object signature) flowing through a
cookie/param.

**Unverified updates / includes**

- Auto-update logic that downloads and applies an update with no signature/checksum
  verification.
- A `<script src="...">`/CDN include, plugin loader, or DNS CNAME pointing at a third-party
  domain where that third party also receives the app's cookies (check for a subdomain
  delegated to a different company - any cookies set on the parent domain leak to them).
- CI/CD that pulls a build artifact or container base image by a mutable tag (`:latest`) rather
  than a pinned digest, with no signature check.

## Fix patterns

```python
# FIXED: don't deserialize untrusted data into native objects at all - use a data format with
# no executable-object semantics (JSON), and validate the schema
import json
data = json.loads(request_data)
validate_against_schema(data)  # e.g. with pydantic/marshmallow/jsonschema

# If YAML is required:
config = yaml.safe_load(user_supplied_yaml)
```

```java
// FIXED: avoid native Java deserialization of untrusted data entirely.
// If state must round-trip through the client, sign it (e.g. JWT/HMAC) and verify before trusting,
// or better, keep state server-side and pass only an opaque session reference.
```

**Other fixes:**

- Verify digital signatures/checksums on every auto-update and on artifacts pulled into CI/CD.
- Pin container base images and dependencies to a digest, not a mutable tag.
- Don't delegate a subdomain to a third party that will also receive that domain's cookies -
  isolate third-party services on a separate domain, or use `SameSite`/scoped cookies carefully.
- If you must accept serialized state from a client, sign it (HMAC) and verify the signature
  before deserializing, and prefer a safe format (JSON + schema validation) over native object
  serialization.
- Add a code-review gate for any change to CI/CD config, build scripts, or artifact sources.

## False-positive notes

- `pickle`/native deserialization used purely on data the application itself produced and never
  exposed to the client (e.g. internal cache files never touched by user input) is lower risk -
  but still flag as Medium/hardening-opportunity, since trust boundaries shift over time and
  this pattern is easy to accidentally expose later.
- YAML loaded with an explicit safe loader (`yaml.safe_load`, `SafeLoader`) is fine - confirm the
  loader actually in use before flagging.
