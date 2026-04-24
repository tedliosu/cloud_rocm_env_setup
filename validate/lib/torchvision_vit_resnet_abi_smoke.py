# pylint: disable=too-many-arguments
# pylint: disable=too-many-positional-arguments
# pylint: disable=too-many-locals
"""
Smoke test to catch obvious ABI-mismatch and ROCm/CUDA GPU detection related issues with
    torch <-> torchvision
"""
import random
import warnings
import sys
from typing import Optional, Union, Any
from collections.abc import Iterable
from tempfile import TemporaryDirectory
from os import path
import torch
import torchvision
from torch import nn, optim, hub
from torch.utils.data import Dataset, DataLoader
from torchvision.transforms import v2
from torchvision.models import (
    resnet50,
    vit_b_16,
    ResNet50_Weights,
    ViT_B_16_Weights
)
from PIL import Image
import numpy as np

_CURR_FILE_ABS_LOC = path.abspath(__file__)
_SCRIPT_ROOT_DIR = path.dirname(_CURR_FILE_ABS_LOC)
_MODEL_CLS_IDX: int = 0
_MODEL_WEIGHTS_IDX: int = 1
_RAND_PY_SEED: int = 93281
_RAND_TORCH_GLOBAL_SEED: int = 22938
_RAND_CUDA_TORCH_GLOB_SEED: int = 39283
_IMAGE_NET_IMG_SIZE: int = 224
_IMAGE_BASE_SIZE: int = 256
_IMGNET_NUM_CLASSES: int = 1000
_IMGNET_MEANS_LIST: list[float] = [0.485, 0.456, 0.406]
_IMGNET_STD_DEVS_LIST: list[float] = [0.229, 0.224, 0.225]
_MODEL_NAME_TO_TUP_DICT: dict[str, tuple[nn.Module, Any]] = \
        {
            "ResNet50": (resnet50, ResNet50_Weights),
            "ViT-B-16": (vit_b_16, ViT_B_16_Weights)
        }


def _print_env_info(dev_str: str) -> None:

    python_ver_str = sys.version.replace("\n", " ")
    print("=== Relevant Environment Info of Versions ===")
    print(f"Python: {python_ver_str}")
    print(f"torch: {torch.__version__}")
    print(f"torchvision: {torchvision.__version__}")
    if "cuda" in dev_str:
        hip_or_cuda_ver = None
        if not torch.version.cuda:
            hip_or_cuda_ver = torch.version.hip
        else:
            hip_or_cuda_ver = torch.version.cuda
        print(f"torch HIP/CUDA version: {hip_or_cuda_ver}")
        print(f"torch HIP/CUDA device name: {torch.cuda.get_device_name()}")

class SyntheticPILDataset(Dataset):
    """
    A dataset where each sample pair is simply a random synthetic
        image and a random associated label.
    """
    def __init__(self, length: int, img_base_size: int,
                 num_classes: int, transform_pipeline: Optional[v2.Compose],
                 rng_seed: int = 64939) -> None:

        self._length = length
        self._img_base_size = img_base_size
        self._num_classes = num_classes
        self._transf_pipeline = transform_pipeline
        self.rng_inst_img = np.random.default_rng(rng_seed)
        self.rng_inst_lbl = random.Random(rng_seed + 3)

    def __len__(self) -> int:

        return self._length

    def __getitem__(self, idx: int) -> \
            tuple[Union[Image.Image, torch.Tensor], Union[int, torch.Tensor]]:

        np_tensor = (self.rng_inst_img
                       .integers(0, high=256,
                                 size=(self._img_base_size,
                                       self._img_base_size, 3),
                                                  dtype=np.uint8))
        img_inst = Image.fromarray(np_tensor, mode="RGB")
        label = self.rng_inst_lbl.randrange(self._num_classes)

        if self._transf_pipeline:
            img_inst = self._transf_pipeline(img_inst)
            label = torch.tensor(label)

        return img_inst, label


def _unfreeze_model_and_get_train_params(model: nn.Module,
                                              device: str) -> \
                                        tuple[nn.Module,
                                              Iterable[torch.Tensor]]:
    """
    Unfreeze `model` parameters, transfer model to `device`,
       and get model and list of trainable paramters on the
       device.
    """

    for param in model.parameters():
        param.requires_grad = True

    model_dev = model.to(device=device)

    trainable_params = [
                           param
                           for param in model_dev.parameters()
                           if param.requires_grad
                       ]

    return model_dev, trainable_params


def _make_zero_workers_dataloader(batch_size: int = 32,
                                 torch_gen_seed: int = 39221) -> DataLoader:
    """
    Makes a shuffled dataset dataloader based on the `SyntheticPILDataset` with
        zero workers and returns it

    Returns: custom dataloader with deterministic shuffling
    """
    transf_pipeline = v2.Compose([
            v2.CenterCrop(_IMAGE_NET_IMG_SIZE),
            v2.RandomRotation(degrees=15,
                              interpolation=v2.InterpolationMode.BILINEAR),
            v2.ToImage(),
            v2.ToDtype(torch.float32, scale=True),
            v2.Normalize(mean=_IMGNET_MEANS_LIST.copy(),
                         std=_IMGNET_STD_DEVS_LIST.copy())
        ])
    torch_gen_inst = torch.Generator()
    torch_gen_inst.manual_seed(torch_gen_seed)

    synth_dataset = SyntheticPILDataset(length=512,
                                        img_base_size=_IMAGE_BASE_SIZE,
                                        num_classes=_IMGNET_NUM_CLASSES,
                                        transform_pipeline=transf_pipeline)

    return DataLoader(synth_dataset,
                      batch_size=batch_size,
                      shuffle=True,
                      generator=torch_gen_inst)


def _one_opt_step_with_checks(model: nn.Module,
                             model_fine_tune_params: Iterable[torch.Tensor],
                             train_loader: DataLoader, device: str) -> None:
    """
    Sets the `model` to training mode, and does one forward + backward pass with
       the dataloader of `train_loader` on `device`, and checks to make sure that:
           1. The training loss is finite
           2. All logits are finite
           3. All gradients that are not None are finite
       while throwing a ValueError if at least one of the three above checks does
       not pass, with the ValueError specifying which check failed.
       If all checks pass, then success PASS status is printed.
    """

    loss_func = nn.CrossEntropyLoss()
    optim_inst = optim.SGD(model_fine_tune_params, lr=1e-3,
                                momentum=7e-1, nesterov=True)
    device_inst = torch.device(device)

    if "cuda" in device:
        torch.cuda.empty_cache()
    model.train()

    with torch.enable_grad():

        train_in_batch, train_labels_batch = next(iter(train_loader))
        train_in_dev = train_in_batch.to(device_inst, non_blocking=True)
        train_labels_dev = train_labels_batch.to(device_inst,
                                                 non_blocking=True)
        optim_inst.zero_grad(set_to_none=False)
        output_logits_dev = model(train_in_dev)

        if not torch.isfinite(output_logits_dev
                                       .detach()).all().item():
            raise ValueError("Non-finite logits encountered " + \
                                 "after one training forward pass!")

        loss_output_inst = loss_func(output_logits_dev,
                                         train_labels_dev)

        if not torch.isfinite(loss_output_inst.detach()).item():
            raise ValueError("Non-finite loss encountered " + \
                                 "after one training forward pass!")

        loss_output_inst.backward()

        num_params_with_grad = 0
        num_params_with_finite_grad = 0
        for param_inst in model_fine_tune_params:
            if param_inst.grad is None:
                continue
            num_params_with_grad += 1
            grad_inst_detached = param_inst.grad.detach()
            if torch.isfinite(grad_inst_detached).all().item():
                num_params_with_finite_grad += 1
        if num_params_with_grad != num_params_with_finite_grad:
            raise ValueError(f"Expected {num_params_with_grad} " + \
                              "parameters with finite gradients " + \
                             f"but got {num_params_with_finite_grad} " + \
                                                                 "instead!")

        optim_inst.step()

    print("PASSED check that one forward + backward of model " + \
          "resulted in:\n    1. Finite logits\n    2. Finite loss\n" + \
          "    3. Finite gradients")

if __name__ == "__main__":

    device_str = "cuda" if torch.cuda.is_available() else "cpu"

    if device_str == "cpu":
        warnings.warn("HIP/CUDA capable device NOT detected " + \
                      "by PyTorch; falling back to CPU!",
                                            category=RuntimeWarning)
    _print_env_info(device_str)

    random.seed(_RAND_PY_SEED)
    torch.manual_seed(_RAND_TORCH_GLOBAL_SEED)
    if device_str == "cuda":
        torch.backends.cudnn.benchmark = False
        torch.backends.cudnn.deterministic = True
        torch.cuda.manual_seed_all(_RAND_CUDA_TORCH_GLOB_SEED)

    with TemporaryDirectory(prefix="tmp_hub_store_",
                                  dir=_SCRIPT_ROOT_DIR) as tmp_hub_dir:

        hub.set_dir(tmp_hub_dir)

        for model_name, model_tuple_inst in _MODEL_NAME_TO_TUP_DICT.items():
            print("Testing default weights " +
                  f"with model type {model_name}...")
            model_cls = model_tuple_inst[_MODEL_CLS_IDX]
            # pylint: disable=invalid-name
            model_weights_spec = model_tuple_inst[_MODEL_WEIGHTS_IDX]
            model_inst = model_cls(weights=model_weights_spec.DEFAULT)
            train_data_loader = _make_zero_workers_dataloader()
            model_inst_dev, train_params = \
                    _unfreeze_model_and_get_train_params(model_inst, device_str)
            _one_opt_step_with_checks(model_inst_dev, train_params,
                                       train_data_loader, device_str)

    print("======= TORCH/VISION ABI CPU/GPU SANITY PASSED =======")
