# Repository Agent Instructions

These instructions apply to the entire repository. They are intended to remain
useful even when no prior conversation or external recovery context is
available.

## Sources of truth and context recovery

1. Read this file and the complete top-level `README.md` before planning work.
2. Treat the current Git repository as authoritative for implementation and
   commit state. Historical conversation summaries describe intent, not proof
   that a change was applied.
3. Treat the organized `README.md` TODO section as the single canonical
   technical backlog and its ordering as the current priority order.
4. Do not create `TODO.md`, maintain a parallel backlog in another file, or
   rely on chat memory as the only record of open work.
5. External recovery notes, receipts, and conversations may be supplied by the
   maintainer, but the repository must not require files outside the checkout
   to understand its supported behavior or current backlog.
6. If external context conflicts with committed code, report the discrepancy.
   Do not silently assume the external description was implemented.
7. Newer dated receipts supersede older planning assumptions about the same
   environment or decision. Preserve version-specific findings as historical
   evidence rather than permanent project requirements.

`AGENTS.md` is a maintained working agreement, not an immutable historical
record. Update it through the same review and approval workflow when durable
scope decisions, realistic effort estimates, maintainer availability
constraints, or repository practices materially change. Treat estimates as
planning aids rather than commitments, and qualify or remove them when they
become stale. Such updates must not create a parallel technical backlog or
silently override current committed behavior.

When removing a completed README TODO, inspect every nested bullet first and
classify it as one of the following:

- completed implementation or documentation that can be removed from the
  active backlog;
- a durable scope or safety boundary that belongs in `Guarantees`,
  `Non-Goals`, or user documentation;
- a separate deferred task that must remain in the backlog;
- wording superseded by a later decision that should be removed.

Do not let completing a parent TODO accidentally delete the repository's only
reference to separate future work. Structured validation receipts and the
general firewall-management non-goal are examples of information that was
preserved this way.

## Context-compaction durability

Agents may not have reliable access to the client's live context-usage counter
or exact compaction threshold. When the maintainer reports high context usage,
or when an agent detects that conversation compaction has occurred, audit newly
established durable decisions against current Git, `README.md`, and `AGENTS.md`
before beginning the next substantial task.

Context pressure alone does not authorize repository edits. If durable
information is missing, propose the smallest appropriate README or AGENTS
change and preserve the normal review and approval gate. Do not create raw
conversation dumps, parallel backlogs, or speculative TODOs merely to preserve
chat context. Do not rewrite information that Git or existing documentation
already records adequately.

## Project contract

This repository bootstraps and smoke-validates practical ROCm cloud VMs for
ML and GPGPU development. It should answer whether a supported environment can
run the repository's small HIP, PyTorch, CuPy, Triton, ComfyUI, and selected
optional validation paths without obvious stack breakage.

Keep the repository narrow:

- It is a VM bootstrap and smoke-validation project.
- It is not production infrastructure as code.
- It is not a general cloud orchestrator.
- It is not a benchmark framework.
- It is not a downstream ROCm distribution or compatibility solver.
- It does not promise support for every ROCm release, GPU architecture, or
  package combination.
- It does not bundle the application projects named as supported workloads.

The maintainer has limited bandwidth while completing a master's program.
Prefer the smallest reproducible change that improves setup, validation,
diagnostics, or documentation. If a change begins turning into its own
subsystem, stop and reconsider its scope.

Decline requests for entirely new cloud providers, GPU-platform families, or
fundamentally new workload categories while the existing baseline is completed
and stabilized. Bugs, regressions, documentation fixes, compatibility reports,
and improvements within existing scope remain welcome. The already-planned
experimental AMD DevCloud path remains in scope.

Keep this scope freeze until the existing baseline is essentially
feature-complete. Reopening broader expansion also requires at least two
additional fairly active human maintainers and an explicit maintainer decision.
That staffing prerequisite does not automatically authorize expansion.

Useful runtime targets are approximately:

- baseline setup plus validation: around 20 minutes on a healthy VM;
- setup with optional components plus validation: preferably no more than
  around 40 minutes;
- validation on an already provisioned VM: approximately 3 to 5 minutes.

These are rough planning targets, not performance guarantees.

## Provider boundaries

### Supported environments

The supported cloud environments are:

- Hot Aisle single-GPU MI300X, `gfx942`, as the primary high-throughput target;
- Azure `Standard_NV24ads_V710_v5`, Radeon Pro V710 MxGPU, `gfx1101`, as an
  optional compatibility and fallback target.

Keep provider orchestration explicit in the corresponding setup scripts.
Share only boring primitives through common utility files. Do not replace the
provider scripts with a generic multi-cloud framework.

When documenting manual provider-side provisioning, prefer one CLI path as
canonical when practical because it is searchable, copyable, and reviewable.
GUI or TUI instructions may be optional convenience guidance, but do not
maintain two equally authoritative provisioning workflows without a
demonstrated user need.

Cloud images change. Probe the actual OS, kernel, ROCm path, driver, GPU
architecture, and relevant package versions. Do not turn an observed image
version into a permanent cross-provider assumption. Unknown but plausible
provider versions should normally be reported and validated rather than
automatically downgraded.

Support applies to validated environment generations. Reporting and validating
an unknown generation does not commit the project to adopting or maintaining
it. A provider migration is maintenance within existing scope, but does not
obligate support for both old and new generations simultaneously. If they
require materially divergent bootstrap logic, prefer one validated generation
and explicitly reject, retire, or suspend support for the other instead of
building a multi-generation compatibility subsystem. If provisioning cannot
reliably select a supported generation, describe the provider as transitional
or not reliably supported until that changes.

### Experimental AMD DevCloud path

AMD DevCloud is not currently part of the Hot Aisle and Azure guarantee. Its
legitimate role is a narrow experimental MI300X environment for packaged AMD
hipCIM, CuPy, and, only when genuinely needed, packaged hipDF components.

Controllable bare-OS provisioning may make DevCloud a stronger reproducibility
target. Promotion to first-class support requires demonstrated reproducibility
of setup, permissions, ROCm reconstruction, the packaged environment,
validation, recovery, and documentation, followed by explicit maintainer
approval. Keep it experimental until then; architectural appeal alone is not
evidence of readiness.

Preserve these boundaries:

- AMD DevCloud instance provisioning remains manual.
- Automate only the demonstrated root-to-user handoff and in-VM bare-OS ROCm
  and packaged environment.
- Require the root bootstrap to run as root and receive the target username and
  authorized-key material explicitly. It may create or recognize one
  password-disabled ordinary user, establish only the required groups and
  reviewed sudo policy, and validate the resulting static state. Preserve valid
  custom or unknown account state rather than becoming a general account
  reconciliation engine.
- Install the project-owned authorized-key state with the intended user and
  group ownership, mode `0700` for `.ssh`, and mode `0600` for
  `authorized_keys`. Do not modify `sshd_config`, disable root SSH, or broaden
  the task into general SSH-server management.
- Select the password-disabled user's sudo contract explicitly before encoding
  it; do not assume full `NOPASSWD` sudo without that decision. Install only a
  project-owned sudoers fragment, write it atomically with root ownership and
  mode `0440`, and validate the complete sudoers policy with `visudo --check`.
- Require a separate SSH login test before ending the root session. Static
  server-side checks do not prove that the intended client authentication and
  network path work.
- A root-owned clone under `/root` may remain as an audit and recovery artifact
  when it contains no retained credentials and is checked out at a reviewed
  immutable commit or tag. Do not replace it with piping a mutable network
  response into a root shell.
- Begin ordinary-user setup with a small read-only handoff preflight. Verify
  the current non-root identity, home, repository access, effective required
  groups, and the explicitly adopted sudo contract without claiming ROCm or
  GPU readiness before those components are installed.
- Use an ordinary Python virtual environment with pip for the demonstrated
  packaged recipe. Do not introduce Conda without a concrete compatibility
  requirement.
- Use packaged `amd-cupy`; do not source-build ordinary CuPy merely for symmetry.
- Target one known MI300X environment and a fixed or constrained recipe.
- Probe and record the actual environment and package versions.
- Fail clearly when the known assumptions stop holding.
- Do not require feature parity with Hot Aisle or Azure.
- Do not support arbitrary ROCm and Python package matrices.
- Do not source-build or forward-port hipDF.
- Do not create or maintain a downstream GPU-library patch collection for this
  path.

The README records a prospective Canny presentation use case. Do not assume
that presentation is confirmed or that the maintainer is continuously
available before its date. Ask for current scheduling context before turning
that possibility into a deadline-driven expansion.

## Closed decisions that must not be reopened implicitly

### RX 7600 XT retirement

The RX 7600 XT `gfx1102` desktop is retired inventory awaiting sale or handoff,
not an active ROCm workstation.

- Do not recommend additional local `gfx1102` testing as a prerequisite for
  retirement or sale.
- Do not make repository work depend on restoring that machine.
- Do not repeat the already completed cloud-substitution drill.
- Sale listing, pricing, packaging, and handoff are personal logistics, not
  repository tasks.

### Hot Aisle substitution and profiling

The Hot Aisle MI300X substitution and hardware-counter profiling question has
been answered sufficiently. Do not repeat it merely to reconfirm retirement.

Observed `rocprof-compute` behavior from ROCm 7.2.4 and profiler 3.4.0 was
version-specific. In particular, isolated Python dependencies, a pandas 2.3.3
workaround, ROCPD use, application replay behavior, and analyzer warnings must
not become permanent bootstrap assumptions.

`rocprof-compute` automation is deferred, not permanently prohibited. If a
future project genuinely requires repeatable MI-series profiling, a small
version-aware helper may be worthwhile after probing the then-current tools.
It must not delay the current bootstrap, documentation, or experimental
DevCloud work.

The longer-term H200 versus MI300X execution-motif study belongs in a separate
project. Do not turn it into this repository's backlog unless the maintainer
explicitly changes scope.

## Baseline versus experimental behavior

Baseline validation must use the native detected architecture and ordinary
provider-supported environment. Experimental knobs and performance results
must be opt-in and labeled non-baseline.

Never enable `HSA_OVERRIDE_GFX_VERSION` by default. It changes the architecture
reported to the runtime but does not create missing code objects. An override
can cause segmentation faults, invalid-device-function failures, or other
runtime errors when binaries were not compiled for the reported target.

The optional Azure CuPy `gfx1101` plus `gfx1100` build is an intentional narrow
compatibility and performance mechanism. Do not generalize it to `gfx1102`,
`gfx1103`, `gfx1104`, other RDNA targets, or unrelated architecture families
without a validated repository use case. Any such expansion remains subject to
the scope freeze.

Do not silently let an externally set HSA override contaminate a baseline
result. Follow the README's documented validation boundary and keep any manual
override-assisted smoke explicitly experimental.

Treat `ROCBLAS_USE_HIPBLASLT` as a version- and architecture-sensitive
performance option, not a correctness requirement or universal speedup.

Do not make this repository a general unofficial platform-enablement layer.
Apply the following distinction:

1. For an official or explicitly supported upstream platform, normal repository
   support may be considered within project scope and maintenance budget.
2. For an explicitly experimental upstream platform, repository support may be
   considered deliberately, but upstream experimentation does not automatically
   create a repository support obligation.
3. For an unsupported platform, a narrow experiment may be used for a concrete
   diagnostic, upstream bug reproduction, or explicitly approved compatibility
   investigation. It must not create a baseline support promise, continuing
   maintenance obligation, or precedent for other unsupported matrix cells.

Source-level portability, successful CuPy JIT execution, and isolated passing
examples or smoke tests are evidence about the tested combination, not proof of
upstream platform support. Do not add general repository workarounds merely to
make unsupported libraries run on unsupported GPU families or providers.

The existing hipCollections `gfx1101` validation patch and optional CuPy
`gfx1100` fallback with manual `HSA_OVERRIDE_GFX_VERSION` use are grandfathered
narrow diagnostic or compatibility exceptions. Preserve their explicit scope;
do not remove them under this policy or treat them as precedents. Azure V710
support does not currently include hipCIM, hipDF, or general RAPIDS-on-RDNA
support. Emerging upstream RDNA work may justify a future deliberate review,
but does not itself expand this repository's support contract.

## Canny and CuPy validation

The custom CuPy Canny workload critically depends on custom and JIT-compiled
CuPy primitives. Templates, `atomicCAS`, and both 32-bit and 64-bit integer
paths are required compatibility coverage, not optional feature exploration.

The implemented smoke uses one primitive-level `ElementwiseKernel`, not a
miniature union-connect or connected-components algorithm. It runs both a tiny
deterministic semantic case and a million-attempt scale case for `int32`,
`int64`, and high-range `uint64` values. Preserve its independent NumPy
references for final values and `atomicCAS` returned-old-value counts. Do not
expand it into CCL, root chasing, hysteresis, or performance benchmarking.

On ROCm 7.2 HIPRTC, the smoke deliberately uses the version-sensitive
`__hip_internal` type traits without a fallback that could hide interface
drift. Its CUDA NVRTC branch uses `cuda::std` traits as an inexpensive local
development check. A CUDA pass does not substitute for ROCm acceptance.

A failure may identify a CuPy, ROCm, compiler, or runtime defect affecting
other users. Do not automatically dismiss it as an application-only problem.
The packaged hipCIM correctness smoke and the custom CuPy primitive smoke answer
different questions; one must not be used as a substitute for the other.

Do not copy the full Canny application into this repository. Application work
belongs in its own project.

CuPy installation is environment-dependent. The supported Hot Aisle and Azure
paths intentionally build pinned upstream CuPy from source and preserve their
existing architecture handling. The experimental AMD DevCloud packaged
environment instead uses packaged `amd-cupy`. Do not force either installation
model onto the other environments merely for structural consistency.

Setup and validation CLI terminology must distinguish the source-built CuPy
environment from the packaged AMD DevCloud RAPIDS environment. The
source-built environment is shared by multiple workloads, so its validation
gate includes both the CuPy custom-kernel smoke and the Numba smoke. Canny
depends on CuPy and Numba-relevant behavior. The explicit oneTBB selection,
however, is retained for the private MLP workload's Numba `parallel=True` and
`prange` CPU activation functions, not because Canny requires TBB and not
because Numba or oneTBB are CuPy dependencies.

The MLP backend comparison measured its ReLU-heavy network at approximately
14.5 minutes with default TBB versus approximately 19 minutes with OpenMP.
Reducing the thread count provided relatively little ReLU benefit, while
sigmoid-heavy networks slowed substantially with fewer threads, so the
all-thread default and TBB were intentionally retained. Do not claim a TBB
advantage over workqueue; that comparison was not performed.

For the source-build paths, retain the underlying CuPy build exit status, keep
a full explicit log, provide useful bounded failure context, and avoid hiding
all progress from the terminal.

## hipCollections and hipDF boundaries

The current hipCollections validation smoke uses the
`STATIC_MAP_HOST_BULK_EXAMPLE`. Keep that smoke separate from the documented
aggregation methodology; do not redesign it merely to mirror the workload
methodology.

For the documented aggregation methodology, prefer host-bulk
`insert_or_apply` over a custom kernel-embedded aggregation implementation.
This reduces benchmarking confounds caused by custom implementation skill
rather than the library primitive itself.

Preserve immutable hipCollections and ROCmDS-CMake dependency pins and the
purpose of narrow compatibility patches. Do not remove an ugly workaround only
because cleaner-looking code seems possible. First identify the validated
compatibility reason and test the replacement on the relevant targets.

Packaged hipDF on an explicitly aligned experimental environment is distinct
from hipDF source builds. Source-building, forward-porting, and maintaining
rocThrust, rocPRIM, libhipcxx, or hipDF compatibility patches remain outside
the supported baseline and normal maintenance budget.

## UFW safety contract

Hot Aisle and Azure both invoke the shared conservative UFW initializer. Azure
network security controls are defense in depth, not a replacement for the
guest firewall. Future providers may skip or relax guest-firewall validation
when UFW is unavailable or not user-controlled.

The UFW state model is intentionally narrow:

- `FRESH`: UFW is installed, exactly inactive, has no UFW-added user rules,
  and has the expected package-default policies. Only this state may be
  modified automatically.
- `BASELINE`: UFW is exactly active, has default-deny incoming and
  default-allow outgoing policies, and has exactly the project-created TCP/22
  rule set. This state is a no-op.
- `CUSTOM`: UFW output is interpretable but differs from FRESH and the exact
  project baseline. Preserve it and report diagnostics.
- `UNKNOWN`: required output cannot be interpreted confidently. Preserve it,
  report diagnostics, and refuse automatic firewall changes.

The governing principle is:

```text
recognize EMPTY state
recognize OUR exact baseline
otherwise hands off
```

The complete known `ufw status` output is deliberately part of the exact FRESH
and BASELINE fingerprints, alongside `ufw show added` and the selected
`/etc/default/ufw` values. Do not replace that recognition with first-line-only
status parsing unless the maintainer explicitly reopens this decision. An
output or formatting change conservatively producing a non-baseline
classification is an acceptable false negative; recognizing changed behavior
as the known baseline is not.

Do not build a general UFW reconciliation engine. Do not reset UFW, delete or
reorder existing rules, broaden restricted SSH access, loosen default-deny
outgoing configurations, or repair active custom configurations.

Use exact C-locale interfaces for classification. Do not use fuzzy checks such
as `grep active`, because `inactive` contains `active`. Prefer exact status
lines, `ufw show added`, and exact values from `/etc/default/ufw`. Parsing
failure must reduce confidence and must never increase willingness to modify.

Before initializing FRESH state over SSH, use the current SSH session to verify
that the server-side port is TCP/22. Do not discover an arbitrary SSH port and
adopt it as a new project baseline. Apply changes in this order:

1. allow TCP/22;
2. set default allow outgoing;
3. set default deny incoming;
4. enable UFW.

If UFW is missing, refresh APT metadata only on that missing-package path before
installing it. Do not force an extra metadata refresh when UFW is already
installed, and do not add cache-age tracking without a demonstrated need.

UFW validation shares the setup classifier and remains observational:

- default strict mode: only BASELINE passes;
- `--relax-ufw-checks`: classify and report every state without gating the
  overall validation run;
- `--skip-ufw-checks`: perform and report no UFW validation;
- skip and relax are mutually exclusive.

Do not restore the old fuzzy active-state check or automatic repair guidance.
Do not add independent semantic parsing for active state, policies, or TCP/22
beyond the inputs required by the shared classifier.

## Bash and repository structure conventions

Preserve existing code style unless it interferes with correctness, safety, or
the explicit task. Do not opportunistically normalize surrounding Bash.

- Constants belong near the top of the appropriate file.
- Constants tightly coupled to common classifier functions may remain beside
  those functions; do not create `comm_shared_vars.sh` merely for structural
  symmetry.
- Functions used across file boundaries must not use a leading underscore.
- Private helpers and private working variables may use leading underscores.
- Prefer braced variable references, especially for private variables.
- Document function arguments using the surrounding `# Usage:` style and add
  concise `# Returns:` documentation when return status is meaningful.
- Existing setup entry scripts intentionally use a marked main section instead
  of a `main` function. Do not begin new setup actions before that marker.
- Idempotent checks that must run on every invocation should normally remain
  outside milestone-wrapped stages.
- Non-stage setup helpers follow the existing `_dont_wrap` suffix convention.
- Keep locale changes scoped with a subshell when exact parsing requires
  `LC_ALL=C`, unless the repository later adopts an explicit global locale
  contract.
- Avoid implied cross-function global mutation when numbered arguments and
  printed return values remain simple.
- Avoid magic sentinel strings for unavailable observations.
- Account for `set -euo pipefail`, pipeline status, command-substitution status,
  and commands that may legitimately return nonzero.
- Preserve the underlying command's exit status when adding logging pipelines.

Use Bash where the existing runner requires Bash. POSIX-compatible helper code
is welcome when it remains natural, but do not refactor working Bash merely to
claim POSIX compliance.

## System safety and package handling

Provider-supported OS, driver, kernel, and APT state should remain conservative.

- Do not casually downgrade or mix system ROCm package generations.
- Do not globally replace ROCm libraries, TBB, or dynamic-linker configuration
  when a local environment or narrow wrapper is sufficient.
- Do not make Docker mandatory. The provider VM and its host ROCm stack are
  part of the validation target.
- Use timeouts selectively for network fetches, package operations, clones,
  downloads, or commands known to block. Do not put timeouts around everything.
- Treat optional repository failures separately from core Ubuntu, AMD, or
  provider failures.
- Never recommend broad artifact deletion for stage recovery. Identify the
  exact stage marker and artifacts owned by that stage.

Ollama installation and model pulls remain manual because mutable registry
artifacts cannot currently be pinned reliably enough for the bootstrap
contract. Fastfetch remains optional and outside workload validation.

## Validation and evidence rules

Setup success is not equivalent to workload success. Validate important
packages by importing and exercising them with a small real workload.

Prefer:

```text
probe -> run small real workload -> record result -> document limitation
```

over:

```text
assume -> abstract -> generalize -> discover drift later
```

Keep baseline validation fast, deterministic, and native. Optional or
experimental checks must be clearly separated and must not contaminate baseline
claims.

Keep the main validator provider-neutral and capability-oriented across Hot
Aisle, Azure, and potentially AMD DevCloud. Provider or environment
fingerprints should mainly determine whether checks are applicable rather than
create separate provider-specific validation implementations. Add provider
specialization only when a concrete environmental difference requires it.

Treat each validation CLI gate as a meaningful environment or capability
bundle. If an optional environment is absent and not explicitly required,
skipping that entire gate is acceptable. If its strict-presence flag is used,
absence must fail. Once a gate is active, schedule every check defined as part
of it; do not report a broad gate as passing after silently skipping a required
constituent. Ordinary fail-fast behavior is still valid because a failed
constituent fails the gate rather than partially passing it.

The future packaged AMD DevCloud RAPIDS gate should cover the shared workload
environment: complete Canny capability through packaged `amd-cupy` and Numba,
the selected TBB backend coverage justified by the private MLP, and the
required packaged hipCIM correctness check. hipCIM may remain in a separate
Python script, and packaged hipDF may be folded into the broader gate only if
it is deliberately adopted. Small orchestration duplication between this gate
and the source-built CuPy gate is preferable to introducing a fine-grained
capability framework.

Receipts should record observed reality rather than force historical versions.
The general structured receipt and validation-summary design is deferred until
it is justified. A narrow experimental path may still record a simple
version-stamped environment record without first building a general receipt
framework.

Do not canonize observed cloud performance numbers as guarantees. Distinguish
cold-start, JIT, and cache effects from steady-state measurements when timing
is relevant.

## Editing and review workflow

Before editing:

1. inspect `git status`, the relevant committed code, and the README backlog;
2. determine what is already implemented;
3. state the smallest expected file and diff boundary;
4. identify any deviation from a previously reviewed prototype or behavior;
5. ask for approval first when the maintainer requested a plan or review gate.

When a proposed action, pause, refusal, or scope boundary materially follows
from this file or the README, identify the relevant section and briefly connect
it to the decision. This is especially important when a request appears to
conflict with an approval gate, safety boundary, closed decision, or canonical
backlog priority. Do not add citations mechanically to every routine action
when they would not improve clarity.

During editing:

- Use the smallest coherent diff.
- Preserve unrelated user changes in a dirty worktree.
- Do not modify files outside the repository unless explicitly authorized.
- Do not create multiple backup, context, or TODO files inside the repository
  as an alternative to Git.
- Do not use stashes unless they materially simplify a real conflict, and do
  not create a pile of stashes.
- Keep setup, validation, documentation, and provider-policy changes in focused
  commits when their behavior and rollback boundaries differ.

After editing:

- show or summarize the exact diff for maintainer review;
- run `git diff --check`;
- run syntax checks for changed shell and Python files;
- run ShellCheck consistently with the repository's sourced-file structure;
- test important state matrices with mocks when live cloud access is unnecessary;
- use a supported cloud instance only when local or mocked checks can no longer
  answer the acceptance question;
- do not make expensive cloud testing the first iteration step;
- do not stage, commit, or push unless explicitly authorized.

The maintainer commonly reviews `git diff` in another terminal before allowing
staging. Respect that pause. When authorized to commit, stage only the reviewed
files and inspect the staged diff before committing. When authorized to push,
verify the intended commits and remote branch first.

Use concise commit titles and explanatory body paragraphs consistent with
recent repository history. For commits co-authored with Codex, preserve the
established closing clause:

```text
Co-authored by Yensong Ted Li and Codex
```

Never push merely because a commit was requested. Push only when the maintainer
explicitly authorizes it.

## Completion and handoff checklist

Before claiming a task complete:

1. verify the requested behavior, not just syntax;
2. confirm no unrelated files changed;
3. reconcile the README backlog with the completed work;
4. preserve any nested deferred task or durable non-goal before removing a
   completed TODO;
5. report tests that ran and important tests that still require a real provider;
6. distinguish committed, staged, unstaged, and pushed state precisely;
7. leave the next task governed by the README rather than inventing a parallel
   plan from historical context.

If a task would require new authority, a broader maintenance promise, or a
material change to the README's current ordering, stop and ask the maintainer
instead of inferring permission.
