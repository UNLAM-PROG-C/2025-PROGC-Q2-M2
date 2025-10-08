from __future__ import annotations

import math
import time
from dataclasses import dataclass
from typing import Dict, List, Tuple

import cv2
import numpy as np

from .io_utils import SharedImageSpec, attach_shared_image
from .tiling import TileRegion, extract_tile


try:
    _LSD_DETECTOR = cv2.createLineSegmentDetector()
    LSD_AVAILABLE = True
except AttributeError:  # pragma: no cover - depends on OpenCV build
    _LSD_DETECTOR = None
    LSD_AVAILABLE = False


@dataclass(frozen=True)
class DetectionConfig:
    detector: str = "hough"
    canny_low: int = 50
    canny_high: int = 150
    hough_rho: float = 1.0
    hough_theta: float = math.pi / 180
    hough_threshold: int = 50
    hough_min_line_length: int = 50
    hough_max_line_gap: int = 10


def _to_gray(image: np.ndarray) -> np.ndarray:
    if len(image.shape) == 2:
        return image
    return cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)


def _segment_length(x1: float, y1: float, x2: float, y2: float) -> float:
    return float(math.hypot(x2 - x1, y2 - y1))


def _angles_degrees(x1: float, y1: float, x2: float, y2: float) -> float:
    return math.degrees(math.atan2(y2 - y1, x2 - x1)) % 180


def _segment_intersects_core(seg_global: Tuple[float, float, float, float], core: Tuple[int, int, int, int]) -> bool:
    x1, y1, x2, y2 = seg_global
    core_x1, core_y1, core_x2, core_y2 = core
    core_x2 = max(core_x2 - 1, core_x1)
    core_y2 = max(core_y2 - 1, core_y1)
    min_x = min(x1, x2)
    max_x = max(x1, x2)
    min_y = min(y1, y2)
    max_y = max(y1, y2)
    if max_x < core_x1 or min_x > core_x2:
        return False
    if max_y < core_y1 or min_y > core_y2:
        return False
    return True


def _make_segment_record(tile: TileRegion, seg_global: Tuple[float, float, float, float], score: float, detector: str) -> Dict[str, float]:
    x1, y1, x2, y2 = seg_global
    return {
        "tile_id": tile.tile_id,
        "x1": float(x1),
        "y1": float(y1),
        "x2": float(x2),
        "y2": float(y2),
        "score": float(score),
        "angle": _angles_degrees(x1, y1, x2, y2),
        "detector": detector,
    }


def detect_segments(tile: TileRegion, image: np.ndarray, config: DetectionConfig) -> List[Dict[str, float]]:
    gray = _to_gray(image)
    edges = cv2.Canny(gray, config.canny_low, config.canny_high)
    segments: List[Dict[str, float]] = []
    detector = config.detector

    if detector == "lsd" and LSD_AVAILABLE:
        lines = _run_lsd(gray)
        for (x1, y1, x2, y2), score in lines:
            gx1 = x1 + tile.x_start
            gy1 = y1 + tile.y_start
            gx2 = x2 + tile.x_start
            gy2 = y2 + tile.y_start
            if not _segment_intersects_core((gx1, gy1, gx2, gy2), tile.core_bounds):
                continue
            segments.append(_make_segment_record(tile, (gx1, gy1, gx2, gy2), score, "lsd"))
    else:
        lines = cv2.HoughLinesP(
            edges,
            rho=config.hough_rho,
            theta=config.hough_theta,
            threshold=config.hough_threshold,
            minLineLength=config.hough_min_line_length,
            maxLineGap=config.hough_max_line_gap,
        )
        if lines is not None:
            for entry in lines:
                x1, y1, x2, y2 = map(float, entry[0])
                gx1 = x1 + tile.x_start
                gy1 = y1 + tile.y_start
                gx2 = x2 + tile.x_start
                gy2 = y2 + tile.y_start
                if not _segment_intersects_core((gx1, gy1, gx2, gy2), tile.core_bounds):
                    continue
                length = _segment_length(gx1, gy1, gx2, gy2)
                segments.append(_make_segment_record(tile, (gx1, gy1, gx2, gy2), length, "hough"))

    return segments


def _run_lsd(gray: np.ndarray) -> List[Tuple[Tuple[float, float, float, float], float]]:
    if not LSD_AVAILABLE or _LSD_DETECTOR is None:
        return []
    lines, widths, _, scores = _LSD_DETECTOR.detect(gray)
    if lines is None:
        return []
    results: List[Tuple[Tuple[float, float, float, float], float]] = []
    for idx, entry in enumerate(lines):
        x1, y1, x2, y2 = map(float, entry[0])
        score = float(scores[idx][0]) if scores is not None else _segment_length(x1, y1, x2, y2)
        results.append(((x1, y1, x2, y2), score))
    return results


def process_tile(tile: TileRegion, spec: SharedImageSpec, config: DetectionConfig) -> tuple[int, List[Dict[str, float]], Dict[str, float]]:
    start = time.perf_counter()
    shm, image = attach_shared_image(spec)
    try:
        tile_view = extract_tile(image, tile)
        segments = detect_segments(tile, tile_view, config)
    finally:
        shm.close()
    elapsed = time.perf_counter() - start
    stats = {"tile_id": tile.tile_id, "segments": len(segments), "time_seconds": elapsed}
    return tile.tile_id, segments, stats
