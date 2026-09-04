# Guarantees

- Target cloud environments:
    - Hot Aisle MI300X, single-GPU VM instances
    - (optional) Azure `Standard_NV24ads_V710_v5` instances
        - Assumed base image: **NVV5 V710 ROCm Linux Image**, **Gen2** variant as of mid-2026; independently verified to be built on Ubuntu 24.04 ([product page on Microsoft Marketplace](https://marketplace.microsoft.com/en-us/product/amdinc1746636494855.nvv5_v710_linux_rocm_image))
    - Exact kernel, ROCm, and `amdgpu` kernel module versions are intentionally recorded by probe logic in scripts rather than hard-coded here.
- Reproducible, *minimal* environment setup with *selectively* pinned Python dependencies, to minimize maintenance upkeep while also making the most important packages relatively version stable and reproducible
- Safe, resumable bootstrap scripts with reboot handling
- Minimal validation to detect obviously broken environments (e.g., ROCm availability, basic workload execution)

# Non-Goals

- Genuinely production ready environment setup
- Bundling in this repository of any actual code for the workloads listed in [Target Workloads](#target-workloads), whether the workloads are public OR private
- Redistribution of proprietary drivers, runtimes, binaries, and source code
- Academic and course provided program implementations that have not been explicitly approved for public release (please see [Private ONLY](#private-only) section under [Target Workloads](#target-workloads))
- General-purpose firewall reconciliation, source-IP allowlisting, dynamic DNS, or VPN infrastructure

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
    - Custom hipCollections `static_map` kernel-embedded aggregation computation.
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

# TODOs

## Current Focus

### Experimental AMD DevCloud hipCIM and CuPy Path

- [ ] Add a narrow AMD DevCloud MI300X setup and validation path for packaged hipCIM and CuPy:
    - Keep AMD DevCloud instance provisioning manual.
    - Automate the demonstrated in-VM bare-OS ROCm and packaged hipCIM/CuPy setup needed for the prospective Canny presentation path.
    - Use an ordinary Python virtual environment with pip and packaged `amd-cupy`; do not source-build ordinary CuPy or introduce Conda merely for consistency with another environment.
    - Target one known MI300X environment and a fixed or constrained package recipe rather than arbitrary ROCm and package combinations.
    - Probe and record the actual OS, ROCm, Python, `amd-cupy`, and `amd-hipcim` versions in a version-stamped environment record.
    - Add a small packaged hipCIM correctness smoke relevant to the supported Canny workload.
    - Run the Canny-critical CuPy custom-kernel smoke once it is implemented, without bundling the application project itself.
    - Fail clearly when the known environment or package assumptions no longer hold.
    - Do not require packaged hipDF for the initial hipCIM/CuPy path unless the presentation or supported workload genuinely needs it.
    - Do not source-build or forward-port hipDF, create a compatibility solver, or require feature parity with Hot Aisle and Azure.

### Canny-Critical CuPy Custom-Kernel Validation Coverage

- [ ] Add a richer CuPy custom-kernel smoke test for capabilities required by the supported CuPy Canny workload:
    - Cover representative custom and JIT-compiled kernel capabilities required by the supported CuPy Canny workload.
    - Exercise templates and `atomicCAS`.
    - Exercise both 32-bit and 64-bit integer paths, including behavior relevant to `int32` and `uint64`.
    - Scope the exact coverage across `ElementwiseKernel`, `RawKernel`, and `RawModule` during implementation based on the smallest representative tests for the supported workload.
    - Treat this as validation of required supported-workload primitives rather than optional feature exploration.
    - Treat a failure as a potential CuPy, ROCm, compiler, or runtime compatibility defect rather than assuming it is specific to this repository.
    - Keep the test small and deterministic so that it remains appropriate for environment smoke validation.
    - Do not make completing this coverage a prerequisite for publishing the Hot Aisle Quick Start.

### CuPy Build Logging

- [ ] Preserve the full CuPy source and wheel build output in an explicit build log:
    - Store the log in the existing setup logs location.
    - Keep enough live terminal output to show that the build is progressing.
    - If the build fails, print the log path and a useful tail or other bounded failure context.
    - Preserve the underlying build command's exit status when logging its output.

### hipCollections Aggregation Methodology

- [ ] Update the planned hipCollections aggregation methodology and documentation:
    - Prefer host-bulk `insert_or_apply` for the planned `static_map` aggregation workload.
    - Avoid using a custom kernel-embedded aggregation implementation as the primary methodology.
    - Explain that this reduces benchmarking confounds caused by custom implementation skill rather than the library primitive itself.
    - Do not redesign the existing `STATIC_MAP_HOST_BULK_EXAMPLE` smoke test solely for this documentation change.

### Hot Aisle Quick Start and Common Use Path

- [ ] Add instructions for using this repository on Hot Aisle MI300X:
    - Document the Hot Aisle setup command.
    - Explain `--show-plan-only` and the optional setup flags.
    - Explain expected reboot and rerun behavior.
    - Document the standard validation command and optional validation flags.
    - Document the manual Ollama setup and validation path.
    - Document the final manual ComfyUI setup and validation steps.

### Recovery and Resumability

- [ ] Document recovery from a failed setup stage:
    - Inspect and resolve the original error.
    - Identify the virtual environment, repository clone, or other artifacts owned by the failed stage.
    - Delete stage-owned artifacts only when rebuilding them is necessary.
    - Delete only the relevant `.done` marker to force that stage to rerun.
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
    - Supporting additional targets should require a validated repository use case rather than being added solely for architecture-family symmetry.

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

## Project Information

- [ ] Add a note that links to custom public projects will be added when those projects are ready to be showcased with this repository.

- [ ] Add a contributing section:
    - Issues are welcome.
    - Pull requests are not currently accepted because of limited review bandwidth.
    - This policy may change in the future.

## Conditional Documentation Maintenance

- [ ] After the Hot Aisle common-use path is established, add equivalent Azure Pro V710 setup and validation instructions.

- [ ] Add structured validation receipt output, including the shared UFW classification, after a common summary and reporting design is justified.

- [ ] Add a linked table of contents if the README becomes too long to navigate comfortably.

# LLM Assistance Usage Disclaimer

- All code and documentation in this repository were drafted with assistance from ChatGPT and Gemini models publicly available circa 2026, but all final code review, integration, validation, testing, etc. were done by me, a human.
