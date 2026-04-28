# Third-Party Notices

This repository includes patch files intended to be applied to third-party projects.

The patch files themselves are authored by Yensong Ted Li and are licensed under Apache-2.0. They contain only this repository's modifications and are **not** full copies of the corresponding upstream projects.

Upstream license texts are provided in [`LICENSES/`](./LICENSES/). Each license text was copied verbatim from the corresponding upstream repository at the exact tag, branch, or commit identified for the relevant patch, with the local filename renamed only for clarity.

## Patch Targets

### Triton

- Upstream GitHub repository: `triton-lang/triton`
- Upstream license: MIT
- Upstream license text: [`LICENSES/Triton-MIT.txt`](./LICENSES/Triton-MIT.txt)
- Patch file: [`validate/lib/patches/triton-no-plot-headless.patch`](./validate/lib/patches/triton-no-plot-headless.patch)

#### Upstream target details
- Patched file(s):
  - `python/tutorials/03-matrix-multiplication.py`
- Upstream tag: `v3.6.0`
- Patch purpose:
  - Disable plotting when the tutorial is run in a headless VM environment.

### hipCollections

- Planned for Azure Pro V710 VM instances only.
- This section will be completed once the corresponding patch is integrated into this repository.
