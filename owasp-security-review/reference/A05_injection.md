# A05:2025 Injection

Rank: #5. Highest CVE count of any category (62k+) - dominated by SQL injection and XSS.
Includes SQL, NoSQL, OS command, ORM, LDAP, and Expression Language (EL/OGNL) injection.
(LLM prompt injection is a related but separate risk - see OWASP's GenAI/LLM Top 10, not this
list.)

## What it is

Untrusted input is sent to an interpreter (database, shell, browser, template engine) in a way
that lets the attacker control part of the command/query rather than just supplying data to it.

## Key CWEs

- CWE-89 SQL Injection
- CWE-78 OS Command Injection
- CWE-79 Cross-site Scripting (XSS)
- CWE-90 LDAP Injection
- CWE-94 Code Injection / CWE-95 Eval Injection
- CWE-917 Expression Language Injection
- CWE-643 XPath Injection
- CWE-564 SQL Injection: Hibernate (HQL concatenation)

## Detection signals

**The universal signal across every variant: string concatenation or interpolation of
user-controlled input directly into a command/query/template, instead of using a parameterized
API.**

**SQL / ORM - any language**

```js
// VULNERABLE
db.query(`SELECT * FROM users WHERE id = ${req.params.id}`);
const q = "SELECT * FROM accounts WHERE custID='" + req.query.id + "'";
```
```python
# VULNERABLE
cursor.execute(f"SELECT * FROM users WHERE id = {user_id}")
cursor.execute("SELECT * FROM users WHERE name = '%s'" % name)
```
```java
// VULNERABLE - including HQL/JPQL, not just raw JDBC
String hql = "FROM accounts WHERE custID='" + request.getParameter("id") + "'";
session.createQuery(hql);
```
Grep for: `+ req.` / `f"...{` / string `.format(` / `%` formatting / template-literal
backticks immediately adjacent to `SELECT`/`INSERT`/`UPDATE`/`DELETE`/`WHERE` keywords or query
builder calls; also any `.createQuery(`, `.createNativeQuery(` (Hibernate/JPA) built via
concatenation.

**OS command**

```js
// VULNERABLE
exec(`nslookup ${req.query.domain}`);
```
```python
# VULNERABLE
os.system(f"ping {hostname}")
subprocess.run(f"convert {filename} out.png", shell=True)
```
Grep for: `shell=True` (Python), `exec(`/`execSync(`/`spawn(...,{shell:true})` (Node),
`Runtime.getRuntime().exec(` (Java) combined with any string built from a request parameter.

**XSS (output side, not input side)**

```js
// VULNERABLE - React: dangerouslySetInnerHTML with unsanitized input
<div dangerouslySetInnerHTML={{ __html: userComment }} />
```
```python
# VULNERABLE - Flask/Jinja2 with autoescape disabled, or |safe filter on user input
{{ user_bio | safe }}
```
Grep for: `dangerouslySetInnerHTML`, `v-html` (Vue), `|safe` (Jinja2), `Html.Raw(` (.NET),
`innerHTML =` assignments fed by request/user data, `{% autoescape false %}`.

**Eval / dynamic code**

```js
// VULNERABLE
eval(userInput);
new Function(userInput)();
```
```python
# VULNERABLE
eval(user_input)
exec(user_input)
```

## Fix patterns

```js
// FIXED: parameterized query
db.query('SELECT * FROM users WHERE id = ?', [req.params.id]);

// FIXED: safe command construction - avoid shell entirely, pass args as an array
const { execFile } = require('child_process');
execFile('nslookup', [domain]); // no shell interpretation of metacharacters
```

```python
# FIXED: parameterized query
cursor.execute("SELECT * FROM users WHERE id = %s", (user_id,))

# FIXED: avoid shell=True, pass args as a list
subprocess.run(["ping", "-c", "4", hostname])  # still validate hostname format first
```

```java
// FIXED: parameterized HQL
Query query = session.createQuery("FROM accounts WHERE custID = :id");
query.setParameter("id", custId);
```

```jsx
// FIXED: let React escape by default - don't use dangerouslySetInnerHTML for user content;
// if HTML rendering is genuinely required, sanitize first with a library like DOMPurify
<div>{userComment}</div>
```

**Other fixes:**

- Always prefer a safe/parameterized API over building queries by hand - this is the only
  complete fix, not a mitigation.
- Where dynamic table/column names are unavoidable (can't be parameterized), validate against
  a strict allowlist of known-safe identifiers - never pass user input straight through.
- Add context-aware output encoding everywhere user content is rendered (HTML, attribute, JS,
  URL contexts each need different encoding).
- Add SAST/DAST scanning to CI to catch these classes automatically going forward.

## False-positive notes

- A query built with string concatenation where every piece is a *hardcoded* string (no user
  input in the concatenated parts) is not injection - check that user-controlled data actually
  reaches the dangerous sink before flagging.
- An ORM's own query-builder methods (`.where('id', '=', id)` style) are generally safe even
  though they "build" a query - the risk is specifically raw/native query strings or `.raw(...)`
  escape hatches.
