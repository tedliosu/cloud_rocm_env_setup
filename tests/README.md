# Testing Guide

This repository combines fast local shell tests with small real GPU workloads
and provider acceptance. These layers answer different questions; a green local
suite does not by itself establish that a cloud image, driver, or ROCm runtime
works.

## Local Checks

From the repository root, run:

```bash
tests/run_shellcheck.sh
tests/run_local_tests.sh
```

`run_shellcheck.sh` analyzes every tracked or unignored shell file. The local
test driver runs each registered test in a separate Bash process and prints the
test path before running it. Its explicit `LOCAL_TESTS` array is the canonical
local-test registry; individual test files may also be run directly with
`bash path/to/test.sh`.

One AMD DevCloud root-bootstrap scenario requires root and is skipped by the
ordinary local driver when it is not running as root. Run that test separately
on a suitable Ubuntu test host only after reviewing its privileged account and
sudoers boundary:

```bash
sudo -H bash setup/amd_devcloud/tests/root_bootstrap_cli_test.sh
```

## Coverage Layers

| Layer | What it protects | What it does not prove |
| --- | --- | --- |
| ShellCheck | Common shell mistakes and source-file analysis | Runtime behavior or correct project policy |
| Local parser and filesystem tests | OS, package, AMD SMI, UFW, marker, symlink, profile, and path handling | Actual provider state or privileged package mutation |
| Mocked setup orchestration | Command arguments and ordering, exact package policy, resumability, scoped environment, and failure propagation | That APT, DKMS, reboot, or a GPU driver succeeds on a live image |
| Root-only local checks | Selected privileged account and sudoers failure behavior | ROCm or GPU readiness |
| Validation-gate tests | Optional/required presence, complete gate scheduling, scoped ROCm variables, and child-failure propagation | Correctness of the mocked workload itself |
| Real workload smokes | Small HIP, PyTorch, CuPy, Numba, hipCIM, hipCollections, and Triton behavior | Exhaustive application correctness or broad package compatibility |
| Provider acceptance | The complete tested setup and validation path for one recorded environment generation | Future provider images or arbitrary ROCm, GPU, and Python matrices |

Current dated provider and workload evidence is recorded under the top-level
README's [Additional Notes](../README.md#additional-notes). That evidence
complements local tests rather than turning paid cloud runs into part of every
development iteration.

## Test Doubles and Scenarios

Shell tests sometimes redefine a function or put a temporary executable first
in `PATH`. This is intentional when a real system command would be privileged,
destructive, provider-specific, expensive, or impossible to control locally.

A useful orchestration test still checks production behavior beyond the double,
such as command arguments, ordering, environment selection, state transitions,
failure propagation, or preservation of diagnostic artifacts. Temporary
commands reject unexpected argument shapes, and mutable observations are reset
between scenarios. Important filesystem and parsing primitives use real local
behavior where practical; kernel, device, driver, and package-manager claims
ultimately require provider acceptance.

The suite intentionally remains plain shell at its current scale. Detailed
test-validity rules and the concrete triggers for reconsidering Bats are in
[AGENTS.md](../AGENTS.md).

## Where Tests Live

- `setup/amd_devcloud/tests/` covers the experimental DevCloud handoff,
  admission states, pinned ROCm setup, paths, and packaged environment.
- `setup/common/tests/` covers shared setup, safety, parsing, failure, and
  resumability primitives.
- `validate/tests/` covers validation helpers and capability-gate
  orchestration.
- `tests/run_local_tests.sh` registers the local behavioral suite.
- `tests/run_shellcheck.sh` owns repository-wide shell static analysis.

When reporting a test problem, describe the contract or realistic regression
at issue rather than optimizing for test count or coverage percentage.
