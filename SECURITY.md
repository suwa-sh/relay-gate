# Security Policy

## Reporting a vulnerability

Please report vulnerabilities via GitHub's **Private vulnerability reporting**:
<https://github.com/suwa-sh/relay-gate/security/advisories/new>

Do not open public issues for security problems.

## Scope notes

- relay-gate targets air-gapped, on-premises environments. Findings that assume internet exposure of the runtime are generally out of scope.
- Behavior that matches the documented specification (`docs/specs/latest/`) — e.g., operators being able to abort/rerun runs by design — is not considered a vulnerability. If you believe the specification itself is unsafe, open a regular issue instead.
