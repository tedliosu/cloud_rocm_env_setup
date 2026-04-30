# Third-Party Notices

This repository includes a small number of third-party-derived artifacts used for environment bootstrap validation.  These artifacts fall into two categories:

1. patch files intended to be applied to third-party projects; and
2. vendored data/configuration files derived from third-party repositories.

Upstream license texts are provided in [`LICENSES/`](./LICENSES/).  Unless otherwise noted, each upstream license text was copied verbatim from the corresponding upstream repository at the tag, branch, or commit identified below, with the local filename renamed only for clarity.

## Patches

This repository includes patch files intended to be applied to third-party projects.

The patch files themselves are authored by Yensong Ted Li and are licensed under Apache-2.0.  They contain only this repository's modifications and are **not** full copies of the corresponding upstream projects.

## Patch Targets

### Triton

- Upstream GitHub repository: `triton-lang/triton`
- Upstream license: MIT
- Upstream license text: [`LICENSES/Triton-MIT.txt`](./LICENSES/Triton-MIT.txt)
- Patch file: [`validate/lib/patches/triton-no-plot-headless.patch`](./validate/lib/patches/triton-no-plot-headless.patch)

**Upstream target details**

- Patched file(s):
    - `python/tutorials/03-matrix-multiplication.py`
- Upstream tag: `v3.6.0`

**Patch purpose**

- Disable plotting when the tutorial is run in a headless VM environment.

### hipCollections

- Planned for Azure Pro V710 VM instances only.
- This section will be completed once the corresponding patch is integrated into this repository.

---

## Data Files

This repository includes data/configuration files, such as ComfyUI workflow JSON files, derived from third-party repositories.  These files are intended to validate environment setup after the initial bootstrap script has been run.

These vendored data files are derived from upstream artifacts and include minor formatting and content modifications by Yensong Ted Li.  Each vendored data file retains the associated upstream licensing noted below.  The vendored files contain only the specific workflow/configuration content needed by this repository and are **not** full copies of the corresponding upstream projects.

## Data File Attributions

### ComfyUI Examples

- Upstream GitHub repository: `comfyanonymous/ComfyUI_examples`
- Upstream license: ComfyUI Examples License
- Upstream license text: [`LICENSES/ComfyUI-Examples-LICENSE.txt`](./LICENSES/ComfyUI-Examples-LICENSE.txt)
- Vendored data file: [`validate/etc/flux_dev_checkpoint_example_tiled_vae_mod.json`](./validate/etc/flux_dev_checkpoint_example_tiled_vae_mod.json)

**Upstream source details**

- Original upstream source file(s):
    - `flux/flux_dev_checkpoint_example.png`
- Upstream commit: `f9431bb000ce792094ff345446e22cac1ea6cef3`

**Local derivation and modification process**

1. The FP8 weights checkpoint referenced by the workflow JSON embedded in the source PNG was downloaded locally into `/path/to/local/ComfyUI/repo/root/models/checkpoints`, so that subsequent workflow-loading steps would not fail in the ComfyUI Web UI.
2. The upstream PNG was drag-and-dropped into the ComfyUI Web UI to load the editable workflow graph from the PNG's embedded workflow metadata.
3. The default VAE decode node in the loaded workflow graph was replaced with the default tiled VAE decode node variant available in ComfyUI version `0.19.0`, using default tiled VAE settings.
4. The modified workflow was saved under the name `flux_dev_checkpoint_example_tiled_vae_mod`.
5. The generated JSON file was reformatted with `jq` and `sponge` for readability only.

**Purpose and notes**

- This file is intended to facilitate environment validation for ComfyUI-based inference using FLUX.1/FLUX.x [dev]-class models.
- The workflow references FP8 model weights and uses tiled VAE decode for compatibility with both Hot Aisle MI300X instances and 24 GiB VRAM Azure Pro V710 instances.
    - This is intentional: FP16 or higher-precision FLUX.1/FLUX.x [dev]-class inference is likely to exceed the usable VRAM budget on 24 GiB Azure Pro V710 instances.
    - xFormers-based memory savings are not assumed for RDNA targets.  During testing, non-tiled non-xFormers VAE decoding for FLUX.1/FLUX.x [dev]-class workflows was not reliable within a <=24 GiB single-GPU VRAM budget, so this validation workflow uses tiled VAE decoding instead.
    - As of April 2026, end-to-end xFormers builds on RDNA ROCm stacks remain too fragile to assume for portable validation.
- The first queued run in the workflow uses the seed stored in the workflow JSON as a deterministic baseline.  Subsequent runs may use randomized seeds as a lightweight manual fuzz/soak check for throughput and obvious image corruption.
- This workflow is intended for environment validation, not maximum-quality or maximum-throughput FLUX-class benchmarking.
- This repository does **not** redistribute the model weights, checkpoints, VAEs, text encoders, or other model artifacts referenced by the workflow.  Those artifacts have their own licenses and access terms.