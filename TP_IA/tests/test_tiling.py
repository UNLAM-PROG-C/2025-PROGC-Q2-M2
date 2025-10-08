import numpy as np

from src.tiling import generate_tiles, tile_coverage_mask


def test_tiles_cover_image_with_core_regions():
    shape = (512, 512, 3)
    tiles = generate_tiles(shape, tile_size=128, halo=16)
    mask = tile_coverage_mask(shape, tiles)
    assert mask.shape == shape[:2]
    assert mask.min() == 1  # Every pixel covered by at least one core region


def test_halo_expands_beyond_core_boundaries():
    shape = (300, 300, 3)
    tiles = generate_tiles(shape, tile_size=128, halo=32)
    first = tiles[0]
    assert first.x_start == 0 and first.y_start == 0
    # Tile next to boundary should include halo but stay within image bounds
    last = tiles[-1]
    assert last.x_end == shape[1]
    assert last.y_end == shape[0]
    assert last.core_x_end <= last.x_end
    assert last.core_y_end <= last.y_end
