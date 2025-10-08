from __future__ import annotations

import json
from dataclasses import dataclass
from multiprocessing import shared_memory
from pathlib import Path
from typing import Iterable, Tuple

import cv2
import numpy as np


@dataclass(frozen=True)
class SharedImageSpec:
    """Descriptor that workers use to attach to shared memory."""

    name: str
    shape: Tuple[int, ...]
    dtype: np.dtype


@dataclass
class SharedImageHandle:
    """Encapsulates shared memory backing the input image."""

    spec: SharedImageSpec
    shm: shared_memory.SharedMemory

    def close(self) -> None:
        self.shm.close()

    def unlink(self) -> None:
        self.shm.unlink()


def ensure_dir(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)


def load_image(path: Path) -> np.ndarray:
    image = cv2.imread(str(path), cv2.IMREAD_COLOR)
    if image is None:
        raise FileNotFoundError(f"Unable to load image: {path}")
    return image


def create_shared_image(image: np.ndarray) -> SharedImageHandle:
    contiguous = np.ascontiguousarray(image)
    shm = shared_memory.SharedMemory(create=True, size=contiguous.nbytes)
    buffer = np.ndarray(contiguous.shape, dtype=contiguous.dtype, buffer=shm.buf)
    buffer[:] = contiguous[:]
    spec = SharedImageSpec(name=shm.name, shape=contiguous.shape, dtype=contiguous.dtype)
    return SharedImageHandle(spec=spec, shm=shm)


def attach_shared_image(spec: SharedImageSpec) -> tuple[shared_memory.SharedMemory, np.ndarray]:
    shm = shared_memory.SharedMemory(name=spec.name)
    array = np.ndarray(spec.shape, dtype=spec.dtype, buffer=shm.buf)
    return shm, array


def save_segments_json(segments: Iterable[dict], path: Path) -> None:
    ensure_dir(path.parent)
    with path.open("w", encoding="utf-8") as f:
        json.dump(list(segments), f, indent=2)


def save_overlay(image: np.ndarray, segments: Iterable[dict], path: Path, *, color=(0, 255, 0), thickness: int = 2) -> None:
    ensure_dir(path.parent)
    overlay = image.copy()
    for seg in segments:
        x1, y1, x2, y2 = int(seg["x1"]), int(seg["y1"]), int(seg["x2"]), int(seg["y2"])
        cv2.line(overlay, (x1, y1), (x2, y2), color, thickness, lineType=cv2.LINE_AA)
    cv2.imwrite(str(path), overlay)


def dump_metrics(metrics: dict, path: Path) -> None:
    ensure_dir(path.parent)
    with path.open("w", encoding="utf-8") as f:
        json.dump(metrics, f, indent=2)
