# Review and Reporting Policy

External review is welcome, especially for bugs, regressions, documentation
problems, compatibility observations, safety issues, and maintainability
concerns within the repository's existing scope.

This project is currently **review-only for external participants**:

- GitHub issues are the accepted public contribution channel.
- Pull requests are not currently accepted. An unsolicited pull request may be
  closed without detailed review because the maintainer cannot commit to
  reviewing arbitrary or large external diffs.
- A request to review code does not authorize editing the repository, opening
  a pull request, changing support policy, or expanding project scope.
- The maintainer retains architecture, implementation, integration, and final
  acceptance responsibility.

This policy may change after the project is more stable and sustained
collaboration demonstrates that additional review capacity actually exists.

## Useful Issue Reports

Before filing an issue, read the relevant part of the top-level `README.md`,
search for an existing report, and identify the exact commit reviewed or
tested. Ordinary issue reporters do not need to read all of `AGENTS.md`, locate
the responsible source file, or diagnose the cause. Reviewers examining
implementation contracts should also consult [AGENTS.md](AGENTS.md);
test-focused reviewers may start with the [testing guide](tests/README.md).

A useful report includes:

- a concise description of the problem and its practical impact;
- the affected command, provider, behavior, or documentation section, and the
  file or function if already known;
- the exact commit and, for runtime failures, the relevant provider, OS,
  kernel, GPU, ROCm, and package versions;
- reproducible steps or direct evidence when available;
- expected and observed behavior;
- whether the finding is confirmed, suspected, or a question; and
- the smallest plausible correction boundary, if one is apparent.

Do not post credentials, access tokens, private keys, private application code,
or unredacted logs containing sensitive information. For a security issue that
should not be disclosed publicly, follow [SECURITY.md](SECURITY.md) and use the
repository's enabled private vulnerability-reporting channel rather than a
public issue.

Requests for entirely new providers, GPU-platform families, or workload
categories are outside the current scope freeze. A narrow unsupported-platform
diagnostic may still be useful evidence, but it does not create a support or
maintenance obligation.

## Finding the Right Area

If the responsible code is unclear, file the issue with the observed command
and behavior; the maintainer can route it. These broad areas are enough:

| Observed problem | Repository area |
| --- | --- |
| Provider setup, package installation, permissions, or reboot behavior | `setup/<provider>/` |
| Behavior shared by multiple setup paths | `setup/common/` or `lib/` |
| Validation options, skipped checks, false success, or workload smoke failure | `validate/` |
| Local test behavior or missing contract coverage | `tests/` and the relevant subsystem test directory |
| Support claim, instructions, or reporting policy | `README.md`, `CONTRIBUTING.md`, or `SECURITY.md` |
| Confidential vulnerability | GitHub private vulnerability reporting; see `SECURITY.md` |

Misclassification is not a reason to avoid reporting a reproducible in-scope
problem.

## Review Approach

Reviews should be bounded and risk-weighted. A reviewer may examine the whole
repository for context while taking primary responsibility for one or more
specific lenses, such as:

- privileged mutation, sudo, SSH, UFW, reboot, and recovery safety;
- shell failure propagation, resumability, ShellCheck, and test structure;
- Python environments, package indexes, resolver behavior, and ABI handling;
- validation correctness, false-success risks, and missing negative tests;
- provider/common boundaries and support claims;
- newcomer usability and documentation coherence; or
- software provenance, licensing, and public-release hygiene.

Prefer concrete findings over general requests to rewrite or standardize the
repository. Passing tests show that their encoded contracts passed; they do not
prove that those contracts are correct. Conversely, stylistic differences are
not defects unless they have a concrete effect on correctness, safety,
auditability, portability, or maintenance.

Review findings should be delivered before proposed implementation. This lets
the maintainer accept a diagnosis without implicitly accepting a particular
architecture or a large generated patch.

## Reusable Review Brief

The following brief may be given to a human reviewer or an independent
AI-assisted review tool, including a Gemini-powered tool such as Antigravity.
Replace the placeholders and narrow the assigned lens when possible.

```text
Perform a read-only, bounded review of cloud_rocm_env_setup.

Review target: <full commit SHA or immutable tag>
Assigned review lens: <specific subsystem or concern>

Before reviewing:
1. Inspect the current Git state at the exact review target.
2. Read the complete top-level README.md, AGENTS.md, and CONTRIBUTING.md.
3. Treat the repository as authoritative; do not reconstruct policy from
   unrelated chat history.

Boundaries:
- Do not edit files, stage, commit, push, open a pull request, or change issue
  state.
- Do not run privileged, destructive, provider-mutating, or paid-cloud actions.
- Do not assume a cloud VM remains available. Identify provider-only questions
  separately from findings that static, local, or mocked evidence can answer.
- Do not broaden supported providers, GPU families, workloads, or package
  matrices.
- Do not turn planning labels, examples, observations, or vague reporting
  language into implementation requirements.
- Do not propose a broad rewrite merely for consistency.

Review priorities:
- contracts, invariants, failure propagation, preservation of unknown state,
  and false-success risks;
- privileged or destructive behavior and recovery boundaries;
- provider-specific versus shared ownership;
- setup-to-validation gate correspondence;
- dependency and package-source ownership;
- contradictions between code, tests, README.md, and AGENTS.md;
- missing tests only where they protect a meaningful repository contract; and
- provenance or licensing concerns supported by specific evidence.

For each finding, report:
- severity and confidence;
- file and precise location;
- the concrete behavior or inference at issue;
- evidence and practical impact;
- whether the repository contradicts itself or human intent is needed; and
- the smallest reasonable correction boundary.

Separate confirmed findings from questions, optional improvements, and items
that require a real provider measurement. End with a short prioritized summary.
Do not implement fixes during this review.
```

AI-generated review findings are leads, not proof. They should be checked
against the cited code, documented contracts, tests, and real provider evidence
before they enter the backlog or drive implementation.
