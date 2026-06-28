# A02:2025 Security Misconfiguration

Rank: #2 (up from #5). 100% of applications tested had some form of misconfiguration.

## What it is

The system, framework, server, or cloud service is set up insecurely: unnecessary features
enabled, default accounts/passwords left in place, verbose error output, missing security
headers, or inconsistent hardening across environments.

## Key CWEs

- CWE-16 Configuration (umbrella)
- CWE-611 Improper Restriction of XML External Entity Reference (XXE)
- CWE-776 XML Entity Expansion ("billion laughs")
- CWE-260/13 Password in Configuration File
- CWE-489 Active Debug Code
- CWE-526 Exposure of Sensitive Information Through Environmental Variables
- CWE-547 Use of Hard-coded, Security-relevant Constants
- CWE-614 Sensitive Cookie in HTTPS Session Without 'Secure' Attribute
- CWE-1004 Sensitive Cookie Without 'HttpOnly' Flag
- CWE-942 Permissive Cross-domain Policy with Untrusted Domains

## Detection signals

**Generic / config files**

- Debug/dev mode flags left `true` in a production config (`DEBUG = True`, `app.debug = true`,
  `NODE_ENV` not set to `production`, ASP.NET `<compilation debug="true">`).
- Stack traces or framework error pages reachable in production (custom 500 handler missing).
- Default credentials referenced or unchanged (`admin/admin`, `root/root`, vendor default
  strings) in seed data, fixtures, or docs implying they ship to prod.
- Directory listing enabled (`Options +Indexes` in Apache, `autoindex on` in Nginx with no
  override).
- Cloud storage bucket policies/ACLs with public read/write (`"Principal": "*"` in an S3 policy,
  a GCS bucket set to `allUsers`).
- Missing or weak security headers in server/middleware config:
  `Strict-Transport-Security`, `X-Content-Type-Options: nosniff`, `Content-Security-Policy`,
  `X-Frame-Options`/`frame-ancestors`, `Referrer-Policy`.
- XML parser configuration that doesn't disable external entity resolution
  (`DocumentBuilderFactory` without `setFeature("...disallow-doctype-decl", true)` in Java;
  `libxml2`/`lxml` parsing without `resolve_entities=False`; .NET `XmlReaderSettings` with
  `DtdProcessing.Parse`).
- Secrets/API keys/passwords committed directly in config files, `.env` files checked into git,
  or hardcoded constants (overlaps with A04 - flag in both if it's a cryptographic key).
- Same configuration values (especially credentials) reused identically across dev/staging/prod.

**JavaScript/Node**

```js
// VULNERABLE
app.use(cors()); // wide open by default
// or
res.header('Access-Control-Allow-Origin', '*');
```

```js
// VULNERABLE: verbose errors leak to client
app.use((err, req, res, next) => {
  res.status(500).json({ error: err.message, stack: err.stack });
});
```

**Python**

```python
# settings.py - VULNERABLE in production
DEBUG = True
ALLOWED_HOSTS = ["*"]
```

**Java**

```java
// VULNERABLE: XXE
DocumentBuilderFactory dbf = DocumentBuilderFactory.newInstance();
DocumentBuilder db = dbf.newDocumentBuilder(); // external entities allowed by default
```

## Fix patterns

```js
// FIXED: explicit origin allowlist
app.use(cors({ origin: ['https://app.example.com'], credentials: true }));

// FIXED: generic error to client, full detail to logs only
app.use((err, req, res, next) => {
  logger.error(err); // full detail server-side
  res.status(500).json({ error: 'Internal server error' }); // nothing sensitive to client
});

// Security headers (e.g. via helmet)
app.use(helmet({
  contentSecurityPolicy: { directives: { defaultSrc: ["'self'"] } },
  hsts: { maxAge: 63072000, includeSubDomains: true, preload: true },
}));
```

```python
# FIXED
DEBUG = False
ALLOWED_HOSTS = ["app.example.com"]
```

```java
// FIXED: disable external entities
DocumentBuilderFactory dbf = DocumentBuilderFactory.newInstance();
dbf.setFeature("http://apache.org/xml/features/disallow-doctype-decl", true);
dbf.setXIncludeAware(false);
dbf.setExpandEntityReferences(false);
```

**Other fixes:**

- Build one automated, repeatable hardening process for environment setup so dev/stage/prod are
  configured identically except credentials (which differ per environment).
- Remove default accounts, sample apps, and unused features/ports/services before shipping.
- Review cloud storage permissions explicitly - never leave default-public.
- Add an automated config-diff or compliance check (e.g. CIS Benchmarks) to CI.
- Use identity federation / short-lived credentials instead of static secrets where the
  platform supports it.

## False-positive notes

- A debug flag inside a `docker-compose.dev.yml` or test-only config is fine - confirm which
  environment a config file actually targets before flagging.
- Some frameworks send detailed errors only when explicitly running in a `development`
  environment variable - verify the actual deployed value, not just the code default.
