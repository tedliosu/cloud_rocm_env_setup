"""Compare cuCIM and scikit-image Canny on one owned fixture."""

import argparse
from importlib import metadata
import os
from pathlib import Path

# CUDA cuFile otherwise creates cufile.log in the current directory even when
# this smoke's explicit debug-output option is absent. Preserve caller policy.
os.environ.setdefault("CUFILE_LOGFILE_PATH", os.devnull)

import cupy as cpy
import cucim
import numpy as npy
from cucim.skimage import color as cucim_color
from cucim.skimage import feature as cucim_feature
from cucim.skimage import util as cucim_util
from skimage import color as skimage_color
from skimage import feature as skimage_feature
from skimage import io as skimage_io
from skimage import util as skimage_util


_SIGMA = 1.5
_LOW_THRESHOLD = 15.0 / 255.0
_HIGH_THRESHOLD = 35.0 / 255.0
_MODE = "nearest"


def _make_fixture() -> npy.ndarray:
    """Return a deterministic synthetic RGB uint8 image with varied edges."""

    row_grid, col_grid = npy.indices((128, 160), dtype=npy.int32)
    fixture = npy.empty((128, 160, 3), dtype=npy.uint8)
    fixture[..., 0] = npy.clip(24 + col_grid, 0, 255).astype(npy.uint8)
    fixture[..., 1] = npy.clip(18 + 2 * row_grid, 0, 255).astype(npy.uint8)
    fixture[..., 2] = npy.clip(210 - row_grid, 0, 255).astype(npy.uint8)

    fixture[18:62, 20:72] = npy.array([232, 48, 36], dtype=npy.uint8)
    fixture[70:112, 88:146] = npy.array([26, 220, 172], dtype=npy.uint8)
    circle_mask = (row_grid - 74) ** 2 + (col_grid - 48) ** 2 <= 22**2
    fixture[circle_mask] = npy.array([245, 236, 42], dtype=npy.uint8)
    diagonal_mask = npy.abs(3 * row_grid - 2 * col_grid - 20) <= 2
    fixture[diagonal_mask] = npy.array([12, 16, 240], dtype=npy.uint8)

    noise = npy.random.default_rng(32928).integers(
        low=-5, high=6, size=fixture.shape, dtype=npy.int16
    )
    return npy.clip(fixture.astype(npy.int16) + noise, 0, 255).astype(npy.uint8)


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Measure cuCIM/scikit-image Canny pixel disagreement."
    )
    parser.add_argument(
        "--max-disagreement-percent",
        type=float,
        help="Fail when disagreement exceeds this accepted percentage.",
    )
    parser.add_argument(
        "--debug-image-dir",
        type=Path,
        help="Write the fixture, both edge maps, and disagreement map here.",
    )
    args = parser.parse_args()
    if args.max_disagreement_percent is not None and not (
        0.0 <= args.max_disagreement_percent <= 100.0
    ):
        parser.error("--max-disagreement-percent must be between 0 and 100")
    return args


def _distribution_versions(import_name: str) -> str:
    """Describe installed distributions that provide one import package."""

    distribution_names = metadata.packages_distributions().get(import_name, [])
    if not distribution_names:
        return "[distribution metadata unavailable]"
    return ", ".join(
        f"{name}=={metadata.version(name)}" for name in sorted(distribution_names)
    )


def _write_debug_images(
    output_dir: Path,
    fixture: npy.ndarray,
    reference_edges: npy.ndarray,
    cucim_edges: npy.ndarray,
) -> None:
    """Write opt-in visual diagnostics without changing comparison inputs."""

    output_dir.mkdir(parents=True, exist_ok=True)
    disagreement = reference_edges != cucim_edges
    images = {
        "fixture_rgb.png": fixture,
        "canny_cpu_reference.png": reference_edges.astype(npy.uint8) * 255,
        "canny_gpu_cucim.png": cucim_edges.astype(npy.uint8) * 255,
        "canny_disagreement.png": disagreement.astype(npy.uint8) * 255,
    }
    for filename, image in images.items():
        output_path = output_dir / filename
        skimage_io.imsave(output_path, image, check_contrast=False)
        print(f"Debug image: {output_path}")


def main() -> None:
    """Run both Canny implementations and report their direct disagreement."""

    args = _parse_args()
    fixture_cpu = _make_fixture()
    fixture_gpu = cpy.asarray(fixture_cpu)

    reference_gray = skimage_color.rgb2gray(
        skimage_util.img_as_float32(fixture_cpu)
    )
    hipcim_gray = cucim_color.rgb2gray(cucim_util.img_as_float32(fixture_gpu))
    reference_edges = skimage_feature.canny(
        reference_gray,
        sigma=_SIGMA,
        low_threshold=_LOW_THRESHOLD,
        high_threshold=_HIGH_THRESHOLD,
        mode=_MODE,
    )
    hipcim_edges = cpy.asnumpy(
        cucim_feature.canny(
            hipcim_gray,
            sigma=_SIGMA,
            low_threshold=_LOW_THRESHOLD,
            high_threshold=_HIGH_THRESHOLD,
            mode=_MODE,
        )
    )

    disagreeing_pixels = int(npy.count_nonzero(reference_edges != hipcim_edges))
    total_pixels = int(reference_edges.size)
    disagreement_percent = 100.0 * disagreeing_pixels / total_pixels

    print("=== cuCIM Canny comparison ===")
    print(f"cuCIM module: {cucim.__version__}")
    print(f"cuCIM distribution: {_distribution_versions('cucim')}")
    print(f"CuPy module: {cpy.__version__}")
    print(f"CuPy distribution: {_distribution_versions('cupy')}")
    print(f"scikit-image: {metadata.version('scikit-image')}")
    current_device = cpy.cuda.runtime.getDevice()
    device_name = cpy.cuda.runtime.getDeviceProperties(current_device)["name"]
    if isinstance(device_name, bytes):
        device_name = device_name.decode("utf-8")
    print(f"GPU device: {device_name}")
    print(f"Fixture pixels: {total_pixels}")
    print(f"Disagreeing pixels: {disagreeing_pixels}")
    print(f"Pixel disagreement: {disagreement_percent:.8f}%")

    if args.debug_image_dir is not None:
        _write_debug_images(
            args.debug_image_dir, fixture_cpu, reference_edges, hipcim_edges
        )

    if args.max_disagreement_percent is None:
        print("MEASUREMENT ONLY: no acceptance tolerance was supplied.")
        return
    if disagreement_percent > args.max_disagreement_percent:
        raise AssertionError(
            f"Canny disagreement {disagreement_percent:.8f}% exceeds accepted "
            f"maximum {args.max_disagreement_percent:.8f}%"
        )
    print("PASSED cuCIM Canny correctness smoke test!")


if __name__ == "__main__":
    main()
