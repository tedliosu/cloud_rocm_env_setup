# Guarantees

- Target cloud environments:
    - Hot Aisle MI300X, single-GPU VM instances
    - (optional) Azure `Standard_NV24ads_V710_v5` instances
        - Assumed base image: **NVV5 V710 ROCm Linux Image**, **Gen2** variant as of mid-2026; independently verified to be built on Ubuntu 24.04 ([product page on Microsoft Marketplace](https://marketplace.microsoft.com/en-us/product/amdinc1746636494855.nvv5_v710_linux_rocm_image))
    - Exact kernel, ROCm, and `amdgpu` kernel module versions are intentionally recorded by probe scripts rather than hard-coded here.
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

- Refactor installation logic of CuPy into virtualenv once an updated version has been released with appropriate patches; make sure that CuPy version is parameterized with respect to function used to perform installation!

# LLM Assistance Usage Disclaimer

- All code and documentation in this repository were drafted with assistance from ChatGPT and Gemini models publicly available circa 2026, but all final code review, integration, validation, testing, etc. were done by me, a human.
