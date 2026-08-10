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

### Quick Start and Common Use Path

- [ ] Add instructions for using this repository:
    - Document the setup command for each supported provider.
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

### hipDF

- [ ] Document why hipDF source builds are excluded from the supported bootstrap:
    - Local testing found compatibility failures across newer ROCm ecosystem combinations.
    - Installing an older ROCm stack over provider-installed ROCm libraries risks package conflicts or package stomping.
    - Forward-porting hipDF and maintaining downstream compatibility patches is outside the repository's scope.
    - Keep any packaged hipDF validation on an explicitly aligned environment separate from the supported Hot Aisle and Azure baseline.

## CuPy Build and Architecture Behavior

- [ ] Document why CuPy is built from source:
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
    - Default validation does not run CuPy with `HSA_OVERRIDE_GFX_VERSION=11.0.0`.
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

- [ ] Add a linked table of contents if the README becomes too long to navigate comfortably.

# LLM Assistance Usage Disclaimer

- All code and documentation in this repository were drafted with assistance from ChatGPT and Gemini models publicly available circa 2026, but all final code review, integration, validation, testing, etc. were done by me, a human.
