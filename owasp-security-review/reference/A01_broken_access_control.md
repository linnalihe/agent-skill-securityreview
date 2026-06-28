# A01:2025 Broken Access Control

Rank: #1 (held #1 since 2021). 100% of applications tested had some form of this.

## What it is

The app fails to enforce that a user can only act within their own permissions. Includes
insecure direct object references (IDOR), missing function-level access control, privilege
escalation, CORS misconfiguration, force-browsing to unauthenticated pages, and metadata/JWT
tampering.

## Key CWEs

- CWE-284 Improper Access Control / CWE-285 Improper Authorization (the umbrella)
- CWE-639 Authorization Bypass Through User-Controlled Key (classic IDOR)
- CWE-862 Missing Authorization / CWE-863 Incorrect Authorization
- CWE-352 Cross-Site Request Forgery (CSRF)
- CWE-918 Server-Side Request Forgery (SSRF)
- CWE-601 URL Redirection to Untrusted Site ('Open Redirect')
- CWE-200/201/359 Exposure of sensitive information to an unauthorized actor
- CWE-548 Exposure of Information Through Directory Listing
- CWE-1275 Sensitive Cookie with Improper SameSite Attribute

## Detection signals

**Generic / cross-language**

- An object identifier (`id`, `acct`, `userId`, `orderId`...) is taken from a request
  (`req.params`, `req.query`, path variable, body) and used directly in a DB lookup, file path,
  or API call **with no check that the current authenticated user owns/may access that record**.
- A route/controller exists for an admin or privileged action with no role/permission check
  visible in that handler (and none in shared middleware that provably wraps it).
- Authorization logic that only exists in frontend JS/mobile code (hiding a button) with no
  matching server-side check - confirm by grepping the backend route for the same check.
- `Access-Control-Allow-Origin: *` (or a regex that's too permissive) combined with
  `Access-Control-Allow-Credentials: true`.
- Directory listing enabled in a web server config, or `.git`/`.env`/backup files reachable
  under the web root.
- A server-side request (HTTP client call) is built from user-controlled input without an
  allowlist of destinations → SSRF.
- A redirect target (`Location` header, `res.redirect(...)`) built from user input without
  validating it's an allowed/internal destination → open redirect.
- JWT verification code that checks the signature but never checks `exp`, `aud`, or `iss`, or
  that decodes the token without verifying the signature at all (e.g. `jwt.decode(token)`
  without `verify=True`/a verify call in many libraries defaults differently - check the library).

**JavaScript / TypeScript (Express, Next.js, etc.)**

```js
// VULNERABLE: no ownership check
app.get('/api/orders/:id', auth, async (req, res) => {
  const order = await Order.findById(req.params.id);
  res.json(order);
});
```
grep for: route handlers using a path/query param in a `find`/`findById`/`findOne` call with no
subsequent `.owner`/`.userId` comparison against `req.user`.

**Python (Flask/Django/FastAPI)**

```python
# VULNERABLE
@app.route("/api/orders/<order_id>")
@login_required
def get_order(order_id):
    return jsonify(Order.query.get(order_id))
```

**Java (Spring)**

```java
// VULNERABLE: @PreAuthorize missing, or present but checking wrong scope
@GetMapping("/api/orders/{id}")
public Order getOrder(@PathVariable Long id) {
    return orderRepository.findById(id).orElseThrow();
}
```

## Fix patterns

**Enforce ownership in the query itself**, not as an after-the-fact check:

```js
// FIXED
app.get('/api/orders/:id', auth, async (req, res) => {
  const order = await Order.findOne({ _id: req.params.id, ownerId: req.user.id });
  if (!order) return res.status(404).json({ error: 'Not found' }); // 404, not 403 - don't leak existence
  res.json(order);
});
```

```python
# FIXED
@app.route("/api/orders/<order_id>")
@login_required
def get_order(order_id):
    order = Order.query.filter_by(id=order_id, owner_id=current_user.id).first_or_404()
    return jsonify(order)
```

```java
// FIXED
@GetMapping("/api/orders/{id}")
@PreAuthorize("@orderSecurity.isOwner(#id, authentication)")
public Order getOrder(@PathVariable Long id) { ... }
```

**Other fixes:**

- Deny by default: every new route requires an explicit auth/role decorator or middleware -
  don't allow "public unless restricted."
- Centralize the access-control check in one reusable place (middleware/decorator/policy
  object) rather than re-implementing it per route.
- Tighten CORS to an explicit origin allowlist; never combine `*` with credentialed requests.
- SSRF: validate destination against an allowlist of hosts/IP ranges; block requests to
  link-local/metadata IPs (`169.254.169.254`, etc.) by default.
- Open redirect: validate the redirect target is a relative path or matches an allowlisted host.
- Set cookies with `Secure`, `HttpOnly`, and `SameSite=Lax`/`Strict` as appropriate.
- Rate-limit sensitive endpoints to reduce damage from automated IDOR enumeration.
- Log access-control failures (see A09) and alert on repeated failures from one
  user/IP.

## False-positive notes

- A missing check is *not* a finding if the data is genuinely public (e.g. a public product
  catalog) - confirm the data's sensitivity before flagging.
- Shared middleware can implement the check upstream of the handler - trace the full request
  path (router → middleware chain → handler) before concluding a check is missing.
