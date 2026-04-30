
export TRITON_REPO_LOCAL_DIRNAME="local_triton_repo"
export HIPCO_REPO_LOCAL_DIRNAME="local_hipco_repo"
export LIB_DIR_RELPATH="../lib"
_PATCHES_DIR_RELPATH="${LIB_DIR_RELPATH}/patches"
_VALD_ETC_DIR_RELPATH="../etc"
export TRITON_EXAMPLE_PATCH_RELPATH="${_PATCHES_DIR_RELPATH}/triton-no-plot-headless.patch"
export FLUX_1_DEV_WORKFLOW_RELPATH="${_VALD_ETC_DIR_RELPATH}/flux_dev_checkpoint_example_tiled_vae_mod.json"

export TRITON_REPO_UPSTREAM_TAG="v3.6.0"
export HIPCO_REPO_UPSTREAM_COMMIT="77f2e84e4b6f9d667d8733967301dbdad4e795de"
export COMFYUI_VALD_MODEL_REPO_TYPE="model"
export COMFYUI_VALD_MODEL_REPO_RELPATH="Comfy-Org/flux1-dev"
export COMFYUI_VALD_MODEL_REPO_COMMIT="ca7d619b1bcd7156ca897f55efb2370eba3d9e20"

export COMFYUI_WORKFLOW_MODLNAME_FILTER='.nodes[] | select(.type == "CheckpointLoaderSimple").widgets_values[0]'
