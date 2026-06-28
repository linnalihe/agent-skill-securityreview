# A06:2025 Insecure Design

Rank: #6. Introduced in 2021. **This category is reasoning-only - there is no pattern bank that
reliably catches it.** A perfect implementation of an insecure design is still insecure; the
flaw is in what the system was built to do, not a coding mistake.

## What it is

Missing or ineffective security controls *by design* - the threat was never modeled, so no
control exists to defend against it. Distinct from insecure *implementation* (A01/A05/etc.),
where a control exists but has a bug. Business-logic flaws live here.

## Key CWEs

- CWE-841 Improper Enforcement of Behavioral Workflow
- CWE-799 Improper Control of Interaction Frequency
- CWE-602 Client-Side Enforcement of Server-Side Security
- CWE-501 Trust Boundary Violation
- CWE-656 Reliance on Security Through Obscurity
- CWE-434 Unrestricted Upload of File with Dangerous Type
- CWE-1125 Excessive Attack Surface
- CWE-269 Improper Privilege Management

## How to actually find these (questions, not patterns)

For every business workflow touched by the code under review, ask:

1. **What are the limits, and are they enforced server-side?** (max quantity per order, max
   group size, rate of an action, spend limits.) If a limit exists only in UI logic or as a
   "soft" suggestion, that's a finding.
2. **What happens at scale/automation?** Could this flow be hit thousands of times per second
   by a script instead of once by a human? (bot/scalper purchasing, mass account creation,
   vote/like stuffing.)
3. **Is any state trusted from the client that should be server-computed?** (price, discount,
   "isAdmin" flag, item availability, a previous step's result passed back and trusted rather
   than re-derived.)
4. **Does the account-recovery / identity-proofing flow rely on something guessable or
   shareable?** ("security questions," anything where more than one person could plausibly know
   the answer.)
5. **Is there a trust-boundary crossing with no re-validation?** (data validated on the client,
   then trusted as-is once it reaches the server; data trusted because it came from "another
   internal service" with no verification.)
6. **Is privilege escalation possible through normal use of a feature** rather than a bug -
   e.g. a "downgrade my plan" feature that can be chained to bypass a paywall?
7. **File uploads**: is the file type/content validated server-side (not just by extension or
   client-declared MIME type), and is it stored/served in a way that prevents it from being
   executed (e.g. uploaded to a non-executable path, served with a forced
   `Content-Disposition: attachment` and a safe content-type)?

## Example findings (from real-world patterns)

- A group-booking flow with a documented "15 attendees before deposit required" rule, but the
  check only fires in the UI - the API accepts a booking for 600 seats across all venues in a
  handful of requests with no server-side cap.
- A flash-sale page with no protection against bots: a scripted client can buy 100% of limited
  stock in milliseconds, locking out real users - no purchase-rate or per-account/per-IP limit
  exists anywhere in the flow.
- A password-reset flow built on "what's your mother's maiden name" - this is unfixable via
  better validation; the design itself needs to be replaced (e.g. with a verified-channel reset
  link/OTP).
- A file upload endpoint that checks the file extension client-side only, accepts any file
  type server-side, and serves uploaded files from the same domain/path as the app (so an
  uploaded `.html`/`.svg` with embedded script executes in the app's origin).

## Fix patterns

- Move every business-rule limit found only in frontend code into server-side enforcement,
  ideally in the domain/model layer so it can't be bypassed by hitting the API directly.
- Add rate limiting and anomaly detection (e.g. "N purchases from one account/IP within
  T seconds") to flows that are valuable to automate.
- Replace knowledge-based recovery with a verified channel (email/SMS link or OTP) plus
  appropriate rate limiting and expiry.
- Re-derive trusted values (price, permissions, availability) server-side on every request;
  never accept them as given from the client.
- Validate uploaded file content (magic bytes, not just extension/MIME claim), store uploads
  outside the served web root or in object storage with no execute permission, and serve them
  with `Content-Disposition: attachment` and a locked-down `Content-Type`.

## How to flag these in a review

Because fixing these is a design/business decision (what's a legitimate vs. abusive use
pattern, what limit is reasonable), **don't auto-apply a fix**. Flag clearly: describe the
missing control, give a concrete abuse scenario, and recommend a fix approach - but leave the
actual threshold/business-rule decision to the team that owns the product behavior.

## References for deeper threat modeling

- OWASP Cheat Sheet: Secure Design Principles
- The Threat Modeling Manifesto (threatmodelingmanifesto.org)
- OWASP SAMM (Software Assurance Maturity Model) - Design/Threat Assessment practice
