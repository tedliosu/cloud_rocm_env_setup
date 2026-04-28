# About Usage of Third Party Components

This repository includes patch file(s) intended to be applied to third-party project(s).  The patch file(s) themselves are authored by Yensong Ted Li and are licensed under Apache-2.0.  Each patch file contain only the corresponding project's modification(s); the patch file(s) are NOT full copies of the upstream projects.  Please see [`LICENSES/`](./LICENSES/) for upstream license texts.

Each license text was copied verbatim from the corresponding upstream repository at the exact tag/branch-and-commit-combo specified for the corresponding patch, with the corresponding license file name renamed locally for clarity.

## Third Party Targets of Patches

### Triton
- Upstream GitHub repository: `triton-lang/triton`
- License: MIT
- Upstream license text: [`LICENSES/Triton-MIT.txt`](./LICENSES/Triton-MIT.txt)
- Patch: [`validate/lib/patches/triton-no-plot-headless.patch`](./validate/lib/patches/triton-no-plot-headless.patch)
- Upstream target info
    - File(s) patched:
        - `python/tutorials/03-matrix-multiplication.py`
    - Repository tag: `v3.6.0`
    - Patch purpose(s):
        - disable plotting in headless VM execution

### hipCollections
- (Planned for Azure Pro V710 VM instances only, will fill out this section once the patch is integrated into this repo.)