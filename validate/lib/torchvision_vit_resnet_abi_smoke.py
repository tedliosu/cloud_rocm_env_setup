# pylint: disable=too-many-arguments
# pylint: disable=too-many-positional-arguments
"""
Smoke test to catch obvious ABI-mismatch and ROCm GPU detection related issues with
    torch <-> torchvision
"""
import random
from typing import Optional, Union
import torch
from torch.utils.data import Dataset, Dataloader
from torchvision.transforms import v2
from PIL import Image
import numpy as np

_IMAGE_NET_IMG_SIZE: int = 224
_IMAGE_BASE_SIZE: int = 256
_IMGNET_NUM_CLASSES: int = 1000
_IMGNET_MEANS_LIST: list[float] = [0.485, 0.456, 0.406]
_IMGNET_STD_DEVS_LIST: list[float] = [0.229, 0.224, 0.225]



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


def make_zero_workers_dataloader(batch_size: int = 32,
                                 torch_gen_seed: int = 39221) -> Dataloader:
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

    return Dataloader(synth_dataset,
                      batch_size=batch_size,
                      shuffle=True,
                      generator=torch_gen_inst)
