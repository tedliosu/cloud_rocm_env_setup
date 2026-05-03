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
- Custom Canny edge detection pipeline written with CuPy from first principles
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
- MLP in CuPy from first principles trained with vanilla mini-batch SGD and MSE loss, with training and testing on MNIST_784 dataset provided by Scikit-Learn OpenML
- Comparison of classification performance and loss curves of various custom Voice Activity Detection models implemented in PyTorch
- CUDA/HIP custom co-rank based iterative mergesort from first principles

## Additional Notes
1. Ollama is intentionally **not** installed by the bootstrap scripts:
    - Ollama installation and model pulls are manual because, as of mid-2026, models pulled from the default Ollama registry cannot be pinned to exact immutable versions.
    - There has also been documented partial coupling between Ollama runtime versions and model versions hosted on the default registry.
    - On ROCm systems, fragile driver/runtime/hardware/etc. combinations may also cause GPU hangs or other inference-time failures.  Therefore, this repository also does not treat Ollama inference as an automated bootstrap validation step.
2. High-capacity solid state storage (100GB+) recommended for Flux-class and LLM model weights when configuring cloud environment(s).

# TODOs

- Refactor installation logic of CuPy into virtualenv with build logging once an updated version has been released with appropriate patches; make sure that CuPy version is parameterized with respect to function used to perform installation!
- "Exception ignored `ImportError`" message of `filelock` package experienced during shutdown of ComfyUI (as of version 0.19.0) via `CTRL+C` in the terminal on Azure Pro V710 instances is a confirmed issue; apparently according to [this GitHub issue comment](https://github.com/Comfy-Org/ComfyUI/issues/12846#issuecomment-4029573105) it is just 'Python dependency noise' and not any kind of real software breakage.
    - Testing confirms that starting up ComfyUI again after shutting down with the `ImportError` message does not result in any corruption of model weights or workflows.
    - User is still strongly recommended to save all open workflows before exiting the ComfyUI Web UI and shutting down the ComfyUI server.
- Clarify the following in this repository's documentation:
    - Some Hot Aisle VM instances, due to pre-installed kernel upgrades, will require manual confirmation from user to proceed during a standard `apt-get upgrade`.
    - On Azure Pro V710 VM instances, PyTorch (as of version 2.11.x) will throw a warning about experimental attention implementation support that can be enabled with appropriate environment variable; this repository intentionally does not enable that experimental feature out-of-the-box and leaves enabling it up to the end user.
    - Since CuPy must usually be built from source for support with latest ROCm version pre-installed in the cloud VM(s), as well as for architectures that are less commonly validated upstream like the Pro V710's `gfx1101`, this repository does NOT attempt to install CuPy from pre-built wheels to standardize environment setup.
        - However, this trade-off comes at a cost of not being able to use the `HSA_OVERRIDE_GFX_VERSION` environment variable to do tasks like checking for architecture-specific behaviors within a given architecture family (e.g. RDNA 3, CDNA 3, etc.)
        - Therefore, setting the environment variable `CUPY_BUILD_GFX11_FALLBACK=1` when running the environment setup main script will trigger the environment setup logic for CuPy to build for `gfx1100` as well, whenever the setup logic has detected that the native architecture being built for is either `gfx1101` or `gfx1102`.
            - From personal experience, `gfx1101` and `gfx1102` are the only confirmed architectures in the RDNA 3 family (not to be confused with RDNA *3.5*, such as `gfx1151`) which work out of the box directly with standard ROCm user-land and DKMS installations (as of ROCm 7.2.x)
            - Even though from personal experience, there are no cloud vendors hosting `gfx1102` GPUs, support for building CuPy for `gfx1100` simultaneously when building for `gfx1102` has been included because:
                - No additional patches/modifications/etc. to CuPy and/or ROCm itself are required for such support
                - Testing as of ROCm 7.x has revealed that on certain `gfx1102` cards like the 7600 XT, hipBLAS/rocBLAS will select very sub-optimal GEMM kernels for the native architecture when performing operations like `matmul` in CuPy.
                - To force more optimal kernel selection on such cards, not only `HSA_OVERRIDE_GFX_VERSION=11.0.0` must be set when running CuPy, but also CuPy must already be built for `gfx1100`; otherwise CuPy will segfault during runtime from personal experience.
        - Please note that when the native HIP architecture is `gfx1101` or `gfx1102`, AND building CuPy for `gfx1100` simultaneously during environment setup has been already requested, NONE of the proceeding automated validation logic attempts to check if the resulting CuPy binaries will support running with the `HSA_OVERRIDE_GFX_VERSION=11.0.0` environment variable setting.
            - This is intentional, because currently there is no known documented way to independently confirm what HIP architectures CuPy was built for in an automated way reliably from the resulting CuPy build itself.
            - (Also document here how user can sanity check for themselves using the 'cupy_numpy_smoke.py' script whether `HSA_OVERRIDE_GFX_VERSION=11.0.0` will crash CuPy during runtime.)
        - Please note that there are NO additional environment variables equivalent to `CUPY_BUILD_GFX11_FALLBACK` for non-RDNA 3 architecture families like CDNA 3 (e.g. `gfx942`) and RDNA 2 (e.g. `gfx1030`) that affects the environment setup logic for CuPy in this repository
            - There is only one valid HIP architecture target in the CDNA 3 family, i.e. `gfx942`, and building CuPy with HIP architectures during environment setup which don't share the same family as the GPU architectures of the target cloud environments of this repository is outside this repository's scope.
    - Since this repository does not assume that user will provide HuggingFace API token(s) when doing environment setup, warning about unauthenticated requests to the HF Hub is to be expected under such a 'non-assumption'.
        - User may register API tokens on cloud environment if user wishes to do so, but user MUST understand the security implications of such an action beforehand.
    - For VM instances like Azure Pro V710, where the user can specify to install `fastfetch` from official GitHub releases directly during the environment setup process, the proceeding environment validation script(s) do NOT automate the validation process of a successful custom `fastfetch` install, since `fastfetch` is NOT a utility that is required for the supported workloads advertised
        - Nonetheless, user may directly run the `fastfetch` command manually after fastfetch is installed and set-up to check that the installation and set-up was done correctly.

# LLM Assistance Usage Disclaimer

- All code and documentation in this repository were drafted with assistance from ChatGPT and Gemini models publicly available circa 2026, but all final code review, integration, validation, testing, etc. were done by me, a human.
