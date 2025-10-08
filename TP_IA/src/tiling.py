from __future__ import annotations

from dataclasses import dataclass
from typing import Iterable, List, Sequence

import numpy as np


@dataclass(frozen=True)
class TileRegion:
    tile_id: int
    x_start: int
    y_start: int
    x_end: int
    y_end: int
    core_x_start: int
    core_y_start: int
    core_x_end: int
    core_y_end: int

    @property
    def offset(self) -> tuple[int, int]:
        return self.x_start, self.y_start

    @property
    def shape(self) -> tuple[int, int]:
        return self.y_end - self.y_start, self.x_end - self.x_start

    @property
    def core_bounds(self) -> tuple[int, int, int, int]:
        return self.core_x_start, self.core_y_start, self.core_x_end, self.core_y_end


def generate_tiles(image_shape: Sequence[int], tile_size: int, halo: int) -> List[TileRegion]:
    height, width = int(image_shape[0]), int(image_shape[1])
    tiles: List[TileRegion] = []
    tile_id = 0
    for core_y_start in range(0, height, tile_size):
        core_y_end = min(core_y_start + tile_size, height)
        for core_x_start in range(0, width, tile_size):
            core_x_end = min(core_x_start + tile_size, width)
            x_start = max(0, core_x_start - halo)
            y_start = max(0, core_y_start - halo)
            x_end = min(width, core_x_end + halo)
            y_end = min(height, core_y_end + halo)
            tiles.append(
                TileRegion(
                    tile_id=tile_id,
                    x_start=x_start,
                    y_start=y_start,
                    x_end=x_end,
                    y_end=y_end,
                    core_x_start=core_x_start,
                    core_y_start=core_y_start,
                    core_x_end=core_x_end,
                    core_y_end=core_y_end,
                )
            )
            tile_id += 1
    return tiles


def extract_tile(image: np.ndarray, tile: TileRegion) -> np.ndarray:
    return image[tile.y_start : tile.y_end, tile.x_start : tile.x_end]


def tile_coverage_mask(image_shape: Sequence[int], tiles: Iterable[TileRegion]) -> np.ndarray:
    height, width = int(image_shape[0]), int(image_shape[1])
    mask = np.zeros((height, width), dtype=np.uint8)
    for tile in tiles:
        mask[tile.core_y_start : tile.core_y_end, tile.core_x_start : tile.core_x_end] = 1
    return mask
