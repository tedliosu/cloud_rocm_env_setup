# Security Policy

## Security Scope and Trust Model

This repository treats bootstrap inputs as security-sensitive because setup
can fetch external software, configure package trust, install persistent
system state, and invoke privileged package operations. Repository-owned paths
use explicit source identities and narrowly reviewed version, digest,
signature, key, or package metadata where the adopted upstream supports a
maintainable check. Unexpected changes to an owned trust contract should fail
closed and receive manual review rather than being accepted automatically.

Transport security and artifact provenance are different controls. HTTPS does
not prove that an upstream account, server, release pipeline, or artifact is
uncompromised, and a digest published by the same mutable origin is primarily
evidence against corruption. A repository-recorded exact digest proves that a
later download matches the bytes this project reviewed; it does not prove that
the original bytes were benign or independently produced.

The project does not pipe mutable network content directly into a privileged
shell. Network retrieval and privileged execution are separate trust
decisions. Package names, plausible branding, search ranking, and visual URL
similarity are not source authentication. Optional diagnostics may be skipped
when their provenance cannot be established safely.

The scheduled provenance monitor checks the pinned AMD DevCloud
repository-bootstrap package against its reviewed canonical URL, absence of a
redirect, exact SHA-256, and exact package version. It reports drift by failing;
it does not update or bless new metadata. This narrow check and the local
modeled security tests do not establish end-to-end supply-chain security or
guarantee resistance to upstream, hosting, signing, transport, runner, or
account compromise.

## Reporting a Vulnerability

Do not open a public issue for a vulnerability that should remain confidential.
Use [GitHub private vulnerability reporting](https://github.com/tedliosu/cloud_rocm_env_setup/security/advisories/new)
instead.

Include the affected commit, practical impact, reproduction details, relevant
provider and environment versions, and any known mitigation. Do not include
credentials, private keys, access tokens, or unrelated sensitive data.

Reports are reviewed as maintainer availability permits. The project does not
currently promise a response or remediation deadline.

## Supported Versions

Security fixes target the current `main` branch and currently validated
environment generations. Older commits, provider images, ROCm stacks, and
package combinations are not guaranteed to receive fixes.
