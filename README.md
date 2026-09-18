# Cloud ROCm Environment Setup

This repository bootstraps and smoke-validates practical ROCm cloud VMs for
ML and GPGPU development. Provider setup scripts keep cloud-specific
orchestration explicit, shared helpers own only genuinely common primitives,
and the main validator checks provider-neutral workload capabilities.

The design favors reproducible minimal environments, conservative system
mutation, small real workload checks, and maintenance costs that remain
realistic for a small project. Optional and experimental paths stay separate
from baseline guarantees.

# Purpose and Motivation

Installing packages, importing a library, or detecting a GPU does not by
itself establish that a ROCm environment is usable. Driver, runtime, compiler,
ABI, package, and provider-image interactions can still break real work. This
project therefore probes the live environment, runs small representative
workloads, and records what actually worked instead of treating installation
success as sufficient evidence.

The project is cloud-first because maintaining edge-case or unsupported local
ROCm hardware can consume substantial effort for limited practical value. CUDA
remains the maintainer's local environment for daily development, while
bounded ROCm cloud environments provide portability validation, comparative
understanding, and experience with another GPU ecosystem. Different
implementations can expose hidden assumptions and provide an independent
correctness and portability check, though agreement across them is not proof
of correctness.

Cloud images, kernels, drivers, ROCm releases, and package combinations change.
The repository therefore treats measured versions and validation results as
version-stamped evidence for particular environment generations, not permanent
promises about every image a provider has offered or will offer. It validates
the VM and host GPU stack intentionally: containers may help selected
workloads, but they do not remove the kernel, driver, device-access,
permissions, and runtime boundary on which ROCm execution depends.

The goal is to automate recurring setup and debugging pain without becoming
production infrastructure as code or a universal cloud abstraction. By
capturing experience from systems and cloud environments that many users may
not have the hardware access, budget, or time to investigate together, the
repository offers reusable, empirically validated guidance for similar use
cases while keeping its support and maintenance surface deliberately bounded.

# Guarantees

- Target cloud environments:
    - Hot Aisle MI300X, single-GPU VM instances
    - (optional) Azure `Standard_NV24ads_V710_v5` instances
        - Assumed base image: **NVV5 V710 ROCm Linux Image**, **Gen2** variant as of mid-2026; independently verified to be built on Ubuntu 24.04 ([product page on Microsoft Marketplace](https://marketplace.microsoft.com/en-us/product/amdinc1746636494855.nvv5_v710_linux_rocm_image))
    - (experimental) AMD DevCloud **Single GPU Plan MI300X Droplet**
      instances provisioned with the Ubuntu 24.04 Bare OS image
        - The root-to-user handoff and in-VM bootstrap through the common
          minimum baseline are accepted for the tested environment generation.
          The packaged AMD RAPIDS gate and first-class provider support remain
          pending.
    - Exact kernel, ROCm, and `amdgpu` kernel module versions are intentionally reported by probe logic in scripts rather than hard-coded here.
    - Provider support applies to validated environment generations, not every image or software version a provider serves. Supporting a replacement generation does not imply continued support for the previous one. If provisioning cannot reliably select a supported generation, provider support may temporarily be marked transitional or suspended.
- Reproducible, *minimal* environment setup with Python dependencies constrained selectively when demonstrated compatibility, ABI, or reproducibility reasons justify it
- Safe, resumable bootstrap scripts with reboot handling
- Minimal validation to detect obviously broken environments (e.g., ROCm availability, basic workload execution)
- Project-specific ROCm library and runtime selection remains process-scoped:
    - Setup does not add project ROCm paths to system dynamic-loader configuration or run `ldconfig` merely to make them globally visible.
    - Setup does not persist `LD_LIBRARY_PATH`, `ROCM_HOME`, `ROCM_PATH`, `HIP_PATH`, or similar runtime and build-selection variables in shell startup files.
    - A deliberately dedicated environment with a pinned system stack may add that stack's exact versioned `bin` directory to `PATH`. This narrow executable-selection exception does not permit persistent library or runtime-selection variables or reliance on a mutable `/opt/rocm` alternative.
    - AMD DevCloud setup maintains that project-owned `/opt/rocm-7.2.3/bin` profile block immediately after the ROCm userland stage and prints a temporary current-shell `PATH` command plus command-scoped `ROCM_HOME=/opt/rocm-7.2.3` and `LD_LIBRARY_PATH=/opt/rocm-7.2.3/lib` guidance. A rerun prints the guidance again while completed stages remain skipped; no separate path-report log is required. Setup does not change those runtime-selection variables in the invoking shell.
    - The common main validator asks the `hipconfig` selected through `PATH` for its complete ROCm root, resolves and reports the canonical directory, and supplies that directory as `ROCM_HOME` plus its `lib` directory as `LD_LIBRARY_PATH` only within the validator process and its children.
    - The validator entry script owns that environment selection and passes selected paths explicitly into helpers that need them; helpers do not implicitly choose or modify the caller's ROCm environment.

# Non-Goals

- Genuinely production ready environment setup
- Bundling the complete application projects or workload implementations listed in [Target Workloads](#target-workloads), whether the workloads are public OR private; small repository-owned validation smokes remain in scope
- Redistribution of proprietary drivers, runtimes, binaries, and source code
- Academic and course provided program implementations that have not been explicitly approved for public release (please see [Private ONLY](#private-only) section under [Target Workloads](#target-workloads))
- General-purpose firewall reconciliation, source-IP allowlisting, dynamic DNS, or VPN infrastructure
- Expansion to entirely new cloud providers, GPU-platform families, or workload categories is currently frozen while the existing baseline is completed and stabilized. The already-planned experimental AMD DevCloud path remains in scope.
- Acting as a general unofficial ROCm platform-enablement layer:
    - Narrow unsupported-platform experiments may be used for concrete diagnostics, upstream bug reproduction, or explicitly approved compatibility investigations.
    - An isolated successful build, JIT kernel, example, or smoke test does not create a baseline support promise, maintenance obligation, or precedent for additional unsupported platform combinations.
    - The existing Azure `gfx1101` hipCollections diagnostic patch and optional CuPy `gfx1100` fallback with a manual HSA override are narrow exceptions, not precedents for broader unsupported-platform support.
    - Azure Pro V710 support does not currently include hipCIM, hipDF, or general RAPIDS-on-RDNA support. Such support would require sufficiently explicit and mature upstream targeting followed by deliberate adoption within this repository's scope and maintenance budget.

# Target Workloads

## Public or To Be Made Public
- Custom Canny edge detection operator written with CuPy from first principles
- ResNet-50 vs ViT-B/16 classification and resource usage performance project
- ComfyUI 2D image generation:
    - FLUX.x [dev] (where "x" is 1 or greater)
- Ollama-powered LLM inferencing:
    - Use **local** `open-webui` install for GUI frontend, for streamlined experience and software maintenance; please see [official Open WebUI documentation](https://docs.openwebui.com/getting-started/quick-start/connect-a-provider/starting-with-ollama/) for more relevant configuration details
    - Target model families:
        - Gemma (3 and above)
        - gpt-oss (2025 version and newer)
        - Mistral Small (3 and above)
        - (optionally) Llama (3.3 and above)
    - Please see [Additional Notes](#additional-notes) sub-section for why Ollama runtime setup and validation are intentionally excluded from bootstrap scripts.
- HIP micro-benches:
    - Elias Konstantinidis's mixbench
    - Custom hipCollections `static_map` aggregation using host-bulk `insert_or_apply`.
        - This favors the library primitive over custom kernel-embedded aggregation to reduce benchmarking confounds from custom implementation skill.
    - (optional) gather-GEMM via Triton with scrambled row maps

## Private ONLY
- MLP in CuPy from first principles trained with vanilla mini-batch SGD and MSE loss, with training, validation, and testing on MNIST_784 dataset provided by Scikit-Learn OpenML
- Comparison of classification performance and loss curves of various custom Voice Activity Detection models implemented in PyTorch
- CUDA/HIP custom co-rank based iterative mergesort from first principles

## Additional Notes
1. Ollama is intentionally **not** installed by the bootstrap scripts:
    - Ollama installation and model pulls are manual because, as of mid-2026, models pulled from the default Ollama registry cannot be pinned to exact immutable versions.
    - There has also been documented partial coupling between Ollama runtime versions and model versions hosted on the default registry.
    - On ROCm systems, fragile driver/runtime/hardware/etc. combinations may also cause GPU hangs or other inference-time failures.  Therefore, this repository also does not treat Ollama inference as an automated bootstrap validation step.
2. High-capacity solid state storage (100GB+) recommended for Flux-class and LLM model weights when configuring cloud environment(s).
3. Version-stamped CuPy custom-kernel acceptance evidence:
    - On 2026-09-05, the tiny semantic and million-attempt scale `atomicCAS`/template cases passed for `int32`, `int64`, and high-range `uint64` on a Hot Aisle MI300X VF with ROCm 7.2.4, source-built CuPy 14.1.1, and NumPy 2.5.2.
    - On 2026-09-09, the same cases passed on an Azure Radeon Pro V710 MxGPU with ROCm 7.2.0, source-built CuPy 14.1.1, and NumPy 2.5.3. The direct Numba 0.67.0 smoke also confirmed that Numba selected the intended TBB threading layer.
    - The direct CuPy and Numba smokes and the complete strict main validator passed on Azure. The complete validator took approximately 2 minutes 35 seconds. These results record the tested environments rather than promising compatibility with every future image or package generation.
4. The optional source-built CuPy environment is requested during setup with `--source-built-cupy-env-setup`.
    - Requesting this environment also installs the selected oneAPI TBB libraries during the earlier APT phase, before any Python virtual environment is created.
    - When present, validation runs both the CuPy custom-kernel smoke and the Numba smoke as one complete environment check.
    - If the environment is absent, validation skips that entire check unless `--fail-on-no-source-built-cupy-env` requires it to be present.
    - The Numba smoke requires the selected threading layer to be TBB. Canny requires CuPy and Numba-relevant behavior, while the explicit TBB selection is retained for the private MLP workload's parallel CPU activation functions.
5. Cross-platform execution of a representative smoke can provide an independent portability and correctness check because different compiler, runtime, and hardware implementations may expose different hidden assumptions.
    - A CUDA-side development check does not make CUDA a supported bootstrap environment and does not substitute for ROCm acceptance.
    - Keep bootstrap coverage at the level of durable platform capabilities rather than bundling private workload regressions or reenacting historical upstream bugs.
6. Version-stamped experimental AMD DevCloud handoff evidence:
    - On 2026-09-09, the root-to-user handoff was accepted on a disposable Ubuntu 24.04 VM. Testing covered fresh account creation, the exact `*` password marker, a separate key-only SSH login, full passwordless sudo, idempotent reruns, and conservative refusal and preservation of a conflicting existing account.
    - On 2026-09-10, the root-only sudoers-rejection test passed both locally and on the disposable VM. The real ordinary-user preflight then passed from separate SSH sessions for two independently created valid users, including their home, repository access, effective required groups, and full noninteractive-sudo contract.
    - The retained root and ordinary-user clones were checked after credential-prompted HTTPS cloning. None had a configured credential helper, a standard Git credential-store file, or credentials embedded in the origin URL.
    - These results establish the initial account handoff and preflight behavior only; they do not establish ROCm, GPU, or packaged-workload readiness on AMD DevCloud.
7. Version-stamped AMD SMI architecture-query evidence:
    - On 2026-09-10, Azure ROCm 7.2.0 with AMD SMI 26.2.1 reported an AMD Radeon Pro V710 MxGPU, native `gfx1101`, and driver 6.16.13 through `amd-smi static --gpu 0 --asic --driver --json`.
    - On the same date, Hot Aisle ROCm 7.2.4 with AMD SMI 26.2.2 reported an AMD Instinct MI300X VF, native `gfx942`, and driver 6.16.13 through the same JSON fields.
    - The common architecture query now uses AMD SMI rather than deprecated ROCm SMI. The matching field shape across those two observations supports one narrow shared parser; it does not make either provider's package names or driver version a cross-provider requirement.
8. Experimental packaged hipCIM recipe evidence:
    - As of 2026-09-10, the maintainer reports that hipCIM Canny from the ROCm 7.2.0 AMD Python index passed on the intended ROCm 7.2.3 system-stack combination.
    - This supports developing one pinned DevCloud recipe. It is not yet repository acceptance of the automated setup, the future packaged RAPIDS gate, other hipCIM functions, hipDF, or a general cross-version package matrix.
9. Version-stamped pristine AMD DevCloud evidence:
    - On 2026-09-12, an actual single-GPU Bare OS instance reported Ubuntu 24.04.4 under KVM, kernel 6.8.0-124, and AMD PCI device `1002:74b5` before AMDGPU installation.
    - The AMD device appeared as a PCI processing accelerator, with no loaded `amdgpu` module or `/dev/kfd`. A Virtio display already provided `/dev/dri`, so generic DRI-directory presence is not evidence that the AMD GPU stack is installed or ready.
    - No AMDGPU/ROCm packages, AMD repositories, matching `/opt` paths, DKMS command, or ROCm tools were detected. The DigitalOcean Ubuntu mirror and droplet-agent repository were normal provider state rather than AMD stack state.
    - UFW matched the exact shared FRESH fingerprint and the SSH session used server port 22. These observations define the initial admission fixture without pinning incidental hostname, CPU, storage, kernel patch, Ubuntu point release, mirror URL, or pending-upgrade details.
10. Version-stamped experimental AMD DevCloud driver-checkpoint evidence:
    - On 2026-09-13, the complete repository-local shell suite, its separate root-only scenario, and the applicable root handoff, separate SSH login, UFW transition, and reboot-acknowledgement checks passed on a disposable Ubuntu Server 24.04 VMware VM. That VM supplied host-side workflow evidence only, not AMDGPU or GPU evidence.
    - An actual fresh AMD DevCloud Bare OS instance then completed the root-to-user handoff, ordinary-user preflight, UFW FRESH-to-BASELINE transition, existing-package upgrade, tmux installation, acknowledged system-upgrade reboot, pinned AMD repository bootstrap, pinned AMDGPU DKMS and versioned AMD SMI installation, and acknowledged driver reboot.
    - After reboot, the running `6.8.0-124-generic` kernel reported installed DKMS module `amdgpu/6.16.13-2327507.24.04`, a loaded `amdgpu` module, `/dev/kfd` owned by the `render` group, and one AMD Instinct MI300X VF with native `gfx942` and AMD SMI driver version `6.16.13`.
    - The transitive `rocm-core7.2.3` dependency maintained `/opt/rocm` through Debian alternatives with canonical target `/opt/rocm-7.2.3`. Setup recognizes that exact link as a driver-stage artifact but continues to use the versioned root directly. A completed-state rerun skipped every prior stage and repeated the post-driver verifier successfully.
    - This acceptance establishes the experimental setup through the driver checkpoint. It does not yet establish the ROCm userland, common validator baseline, packaged RAPIDS environment, or workload readiness.
11. Version-stamped experimental AMD DevCloud common-baseline evidence:
    - On 2026-09-17, a fresh single-GPU Bare OS instance at reviewed commit `49df627` completed the root-to-user handoff, exact UFW baseline, both acknowledged reboot boundaries, pinned repository and driver stages, complete `rocm7.2.3` userland, versioned ROCm profile block, common system prerequisites, and baseline Python environment. The system upgrade changed the reported point release from Ubuntu 24.04.4 to 24.04.5 while retaining kernel `6.8.0-124-generic`.
    - The post-setup environment report observed AMDGPU DKMS `6.16.13-2327507.24.04`, AMD SMI `26.2.2.70203-90~24.04`, one AMD Instinct MI300X VF with native `gfx942`, `rocm7.2.3` `7.2.3.70203-90~24.04`, HIP `7.2.53211-c2d9476115`, Python 3.12.3, and PyTorch 2.11.0 with ROCm 7.2.
    - The common default validator passed its strict UFW and ROCm checks, HIP and hipCollections smokes, PyTorch audio/codec CPU ABI smoke, ResNet-50 and ViT-B/16 GPU forward-and-backward checks, and Triton fp16 matmul smoke. The absent optional source-built CuPy and ComfyUI environments were skipped as designed.
    - The accepted post-setup workflow is `./validate/bin/validate_main.sh` followed by the read-only `./setup/amd_devcloud/bin/amd_devcloud_acceptance_probe.sh`. Its standard output may be retained as acceptance evidence when useful; setup does not own a persistent report artifact and does not depend on creating one.
    - This acceptance establishes the experimental automated ROCm userland and common minimum baseline. It does not yet establish the packaged AMD RAPIDS environment, hipCIM correctness gate, optional hipDF components, or first-class DevCloud support.

# TODOs

## Current Focus

### Experimental AMD DevCloud hipCIM and CuPy Path

- [ ] Develop the DevCloud packaged RAPIDS setup and validator gate together:
    - Use an ordinary Python virtual environment with pip, packaged `amd-cupy` and `amd-hipcim`, and the exact ROCm 7.2.0 AMD Python index, `https://pypi.amd.com/rocm-7.2.0/simple/`, on the pinned ROCm 7.2.3 system stack. Follow the documented `--extra-index-url` installation model and let pip honor wheel metadata for transitive dependencies rather than reconstructing them locally. Explicitly declare the shared GPU-array workloads' direct Python requirements and their established compatibility ranges, consistent with the source-built CuPy environment. Do not introduce Conda or generalize this observed cross-patch recipe into a supported version matrix.
    - Add one coherent packaged RAPIDS shared workload-environment gate to the common provider-neutral validator. When active, it must run every check defined as required by that environment rather than silently accepting a partial result.
    - Include the implemented Canny-critical CuPy custom-kernel smoke, the Numba behavior relevant to Canny, and the selected TBB backend coverage justified by the shared private MLP workload.
    - Add a small direct hipCIM/cuCIM-versus-scikit-image Canny comparison using each library's float32 grayscale conversion, `sigma=1.5`, thresholds `15/255` and `35/255`, and `mode="nearest"` on a deterministic repository-owned fixture.
    - Keep that comparison backend-neutral so the same script can run against cuCIM on CUDA for inexpensive development checks. Add an opt-in debug-output directory that writes the fixture and both final Canny result images, with a disagreement image when useful; ordinary validation must not create those artifacts.
    - Report pixel disagreement percentage without dilation or other edge post-processing, and set any pass tolerance only after recording a representative preliminary measurement and confirming it on DevCloud. Do not copy the application image or custom Canny implementation, and do not turn the smoke into a benchmark.
    - Complete local and CUDA-capable iteration before scheduling paid cloud acceptance when those checks can answer the remaining questions. Test earlier when a provider-only measurement or assumption blocks safe implementation. Treat each DevCloud VM as an ephemeral, explicitly coordinated acceptance round and consolidate the remaining ROCm-only questions rather than assuming an earlier instance still exists.
    - Keep individual validation scripts separate where useful; the environment gate and CLI behavior, rather than Python file layout, define the validation contract.
    - Allow optional absence to skip the entire packaged environment gate, while any future strict-presence flag must fail when the environment is absent.
    - Add bounded checks for the packaged gate's optional-absence, strict-presence, and required-check failure behavior alongside its implementation.
    - Fail clearly when the known environment or package assumptions no longer hold.
    - Do not require packaged hipDF for the initial hipCIM/CuPy path. Its later adoption within the same DevCloud packaged environment is decided but remains a separate deferred task, not a presentation deadline.
    - Keep the future hipDF direct requirements and ROCm 7.2.3 AMD Python index separate from the ROCm 7.2.0 hipCIM/CuPy requirements input. Resolve the more patch-sensitive hipDF group first and the hipCIM/CuPy group second, using ordinary dependency metadata for both, followed by `pip check` and complete workload validation. This tested ordering is not a claim of general index interoperability or wheel provenance. If the later operation breaks hipDF, fail and revisit demonstrated constraints rather than using `--no-deps` or mirroring the transitive closure.
    - Packaged hipDF may join the broader RAPIDS gate when that keeps orchestration simpler. Do not source-build or forward-port hipDF, create a compatibility solver, or require feature parity with Hot Aisle and Azure.

### Repository Contract and Test-Structure Review

- [ ] Perform a bounded retrospective audit of the existing implementation, tests, README, and agent agreement after the current DevCloud path is established:
    - Check whether subsystem behavior, interfaces, invariants, failure semantics, provider gates, and support claims still match the intended project contract rather than relying on passing tests alone.
    - Review helper and test placement, provider/common boundaries, duplicated or contradictory policy, stale rationale, and details that accumulated in the wrong documentation section.
    - Review whether package declarations are owned by the clearest inspectable manifest instead of being duplicated across requirements files, provider variables, and shell commands. Include both pip requirements and requirements-like APT package lists that setup stages read explicitly; do not assume every installation or runtime concern belongs in a declarative file.
    - Inspect stylistic differences such as `grep` versus Bash matching, here-documents versus other text construction, `case` versus `if`/`elif`, and mutable test globals versus explicit data flow only for concrete effects on auditability, testability, portability, failure behavior, maintainability, or control-flow clarity.
    - Prefer the clearest semantic model, including explicit state machines when the problem is inherently detailed. Do not normalize equally valid styles, refactor merely to reduce branches, or begin broad cleanup without first recording specific problems and why they matter.

- [ ] Evaluate organization of the growing local shell-test surface:
    - Compare the current `tests/run_local_tests.sh`, possible focused test drivers, and Bats based on readability, failure reporting, maintenance cost, portability, and execution on development and provider environments.
    - Determine how Bats would be installed reproducibly on arbitrary provider VMs and whether an added bootstrap dependency or vendored framework is justified.
    - Do not adopt a framework or split drivers until the expected organizational benefit outweighs dependency and maintenance costs.

### Hot Aisle Quick Start and Common Use Path

- [ ] Add instructions for using this repository on Hot Aisle MI300X:
    - Document the Hot Aisle setup command.
    - Explain `--show-plan-only` and the optional setup flags.
    - Explain expected reboot and rerun behavior.
    - Explain that setup installs tmux before the intentional reboot, then document starting or resuming a named tmux session after reconnecting for long post-reboot stages.
    - Document the standard validation command and optional validation flags.
    - Document the manual Ollama setup and validation path.
    - Document the final manual ComfyUI setup and validation steps.

### Recovery and Resumability

- [ ] Document recovery from a failed setup stage:
    - Inspect and resolve the original error.
    - Identify the virtual environment, repository clone, or other artifacts owned by the failed stage.
    - Delete stage-owned artifacts only when rebuilding them is necessary.
    - Delete only the relevant completed or pending marker when the documented recovery procedure specifically requires it.
    - Rerun the setup script so completed stages remain skipped.
    - Document the exact marker and artifact locations instead of recommending broad directory deletion.

- [ ] Document approximate setup and validation times:
    - Minimal setup and validation on Hot Aisle MI300X.
    - Full setup and validation on Hot Aisle MI300X.
    - Minimal setup and validation on Azure Pro V710.
    - Full setup and validation on Azure Pro V710.
    - Present these as rough observations rather than guarantees.

## Known Compatibility Notes

### ComfyUI

- [ ] Revalidate and document the `filelock` shutdown warning observed with ComfyUI version 0.19.0 on Azure Pro V710:
    - An `Exception ignored ImportError` message may appear when stopping ComfyUI with `CTRL+C`.
    - Previous testing found no resulting corruption of model weights or workflows.
    - Users should still save open workflows before exiting the Web UI or stopping the server.
    - Confirm that the [linked upstream issue comment](https://github.com/Comfy-Org/ComfyUI/issues/12846#issuecomment-4029573105) still supports describing this as harmless Python dependency noise.

### Hot Aisle System Updates

- [ ] Document that some Hot Aisle VM images may require user confirmation during `apt-get upgrade` because of preinstalled kernel upgrades.
    - Revalidate this behavior against the current noninteractive upgrade logic before publishing the note.

### Azure PyTorch Attention

- [ ] Document the experimental attention warning emitted by PyTorch 2.11.x on Azure Pro V710.
    - Explain that the repository intentionally leaves the experimental attention implementation disabled by default.
    - Treat enabling it as an optional per-workload experiment.

### Azure Non-Root System Log Access

- [ ] Audit whether the ordinary Azure bootstrap user can inspect system logs needed for routine ROCm and cloud debugging without routinely using sudo:
    - Test the required `journalctl` access on the current Azure image.
    - Treat non-root log access as the behavioral requirement rather than assuming a particular group is sufficient.
    - Inspect the current group and ACL behavior; do not assume membership in `adm` alone solves it.
    - Keep this as a bounded permissions audit rather than a general Linux authorization framework.

### hipDF

- [ ] Document why hipDF source builds are excluded from the supported bootstrap:
    - Local testing found compatibility failures across newer ROCm ecosystem combinations.
    - Installing an older ROCm stack over provider-installed ROCm libraries risks package conflicts or package stomping.
    - Forward-porting hipDF and maintaining downstream compatibility patches is outside the repository's scope.
    - Keep packaged hipDF validation as a possible later extension of the explicitly aligned experimental AMD DevCloud path, separate from the supported Hot Aisle and Azure baseline.

## CuPy Build and Architecture Behavior

- [ ] Document why the supported Hot Aisle and Azure paths build CuPy from source:
    - Current ROCm versions and less commonly validated targets such as Azure Pro V710 `gfx1101` may not be adequately supported by prebuilt wheels.
    - The source build uses the native detected HIP architecture by default.

- [ ] Document `CUPY_BUILD_GFX11_FALLBACK=1`:
    - When the native architecture is `gfx1101`, this option also builds CuPy for `gfx1100`.
    - This makes an optional `HSA_OVERRIDE_GFX_VERSION=11.0.0` experiment possible because the required `gfx1100` code objects are present.
    - Without compatible code objects, using the override may cause a segmentation fault or another runtime failure.
    - Never enable the HSA override by default.

- [ ] Document the motivation and limits of the `gfx1100` fallback:
    - Some tested `gfx1101` problem shapes selected substantially slower native rocBLAS or hipBLAS kernels.
    - Treat override-assisted results as optional compatibility or performance experiments, not baseline validation results.
    - Do not promise that the override improves every workload.

- [ ] Document the automated validation boundary:
    - Default validation does not set `HSA_OVERRIDE_GFX_VERSION=11.0.0` automatically.
    - The main validator refuses to run when it inherits a non-empty `HSA_OVERRIDE_GFX_VERSION`, so its results remain native baseline validation.
    - Validation of the dual-target build is left to the user because there is currently no known documented and reliable way to independently determine, from the resulting CuPy build itself, which HIP architectures were compiled into it.
    - Document how users can manually run `cupy_numpy_smoke.py` with the override as a runtime sanity check.
    - Make clear that this manual check confirms only whether the tested workload runs successfully. It does not independently enumerate or verify every architecture compiled into CuPy.
    - Warn that running with an incompatible override may cause a segmentation fault or another runtime failure.

- [ ] Document the exact architecture scope of the dual-target build:
    - `CUPY_BUILD_GFX11_FALLBACK=1` adds `gfx1100` only when the detected native architecture is `gfx1101`.
    - Other RDNA 3 targets, including discrete GPU targets such as `gfx1102` and integrated GPU targets such as `gfx1103` and `gfx1104`, do not receive the same dual-target build behavior.
    - There are no equivalent fallback environment variables for those targets or for other architecture families.
    - Broader support for these architectures in newer ROCm releases does not imply support by this repository's CuPy build logic.
    - This repository currently limits the fallback behavior to the validated Azure Pro V710 `gfx1101` use case.
    - Supporting additional targets remains subject to the scope freeze and requires a validated repository use case rather than being added solely for architecture-family symmetry.

## Expected Warnings and Optional Utilities

### Hugging Face Hub

- [ ] Document that unauthenticated Hugging Face Hub warnings are expected:
    - Environment setup does not assume that the user will provide an API token.
    - Users may configure a token manually after considering the security implications of storing credentials on a cloud VM.

### fastfetch

- [ ] Document the fastfetch validation boundary:
    - Azure users may optionally install fastfetch from an official GitHub release during setup.
    - fastfetch is not required by any supported workload, so the main validation script does not validate it.
    - Users can run `fastfetch` manually to confirm the optional installation.
    - After the DevCloud setup path and Hot Aisle quick-start documentation are complete, decide whether DevCloud should offer the same optional GitHub-release convenience. If adopted, share the identical release pin and package filename rather than duplicating them across provider variables.

## Project Information

- [ ] Add a note that links to custom public projects will be added when those projects are ready to be showcased with this repository.

- [ ] Add a contributing section:
    - Bugs, regressions, documentation fixes, compatibility reports, and improvement suggestions within existing scope are welcome.
    - Requests for entirely new providers, GPU-platform families, or workload categories are currently declined.
    - Narrow unsupported-platform diagnostic reports may be considered, but requests for ongoing unofficial platform enablement are not accepted as support obligations.
    - Pull requests are not currently accepted because of limited review bandwidth.
    - This policy may change in the future.

## Conditional Documentation Maintenance

- [ ] After the Hot Aisle common-use path is established, add equivalent Azure Pro V710 setup and validation instructions.

- [ ] Add structured validation receipt output, including the shared UFW classification, after a common summary and reporting design is justified.

- [ ] If the maintainer explicitly decides to permit additional maintainers, document a lightweight maintainer role and selection policy:
    - Treat demonstrated collaboration, access to enough cloud resources for meaningful validation, and relevant ROCm, GPU, Linux, cloud, or workload experience as candidate considerations rather than current acceptance criteria.
    - Keep important project knowledge and decisions reconstructible from the repository rather than private conversations or one maintainer's memory.
    - Do not create governance machinery before the role and actual need are approved.

- [ ] If recurring in-scope remote HIP/C++ development demonstrates a need, evaluate optional provider-aware clangd setup guidance:
    - Determine how clangd should use the provider or system ROCm installation before deciding whether bootstrap automation is justified.
    - Treat it as an optional developer convenience rather than a baseline capability or validation gate unless a later supported workflow proves otherwise.
    - Do not promise it for every provider. The separate MI300X-versus-H200 execution-motif study does not currently create a tooling requirement for this repository.

- [ ] Add a linked table of contents if the README becomes too long to navigate comfortably.

# LLM Assistance Usage Disclaimer

- All code and documentation in this repository were drafted with assistance from ChatGPT and Gemini models publicly available circa 2026. Architecture, support boundaries, semantics, interfaces, invariants, acceptance or rejection decisions, and final integration approval remain human-owned.
- Human review is contract-first and risk-weighted. It includes deeper inspection of high-risk behavior and selective implementation review supported by tests and behavioral summaries; it does not claim exhaustive line-by-line inspection of every agent-assisted change.
- This disclosure provides transparency about the development process; it is not by itself proof of originality, complete provenance, or license compliance.
- Reports of suspected similarity to third-party material or licensing concerns are welcome so that affected code or documentation can be reviewed and, when appropriate, replaced.
