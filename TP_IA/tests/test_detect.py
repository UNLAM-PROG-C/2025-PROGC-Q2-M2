import math

import cv2
import numpy as np

from src.detect import DetectionConfig, detect_segments
from src.tiling import TileRegion


def make_tile_region(width: int, height: int) -> TileRegion:
    return TileRegion(
        tile_id=0,
        x_start=0,
        y_start=0,
        x_end=width,
        y_end=height,
        core_x_start=0,
        core_y_start=0,
        core_x_end=width,
        core_y_end=height,
    )


def test_detection_finds_known_line():
    image = np.zeros((128, 128, 3), dtype=np.uint8)
    cv2.line(image, (10, 10), (118, 118), (255, 255, 255), 3)
    tile = make_tile_region(128, 128)
    config = DetectionConfig(canny_low=30, canny_high=100, hough_threshold=20, hough_min_line_length=30)
    segments = detect_segments(tile, image, config)
    assert segments, "Expected at least one segment"
    best = max(segments, key=lambda s: s["score"])
    angle = best["angle"]
    assert math.isclose(angle, 45.0, abs_tol=5.0)
    assert min(best["x1"], best["y1"]) < 15
    assert max(best["x2"], best["y2"]) > 110
