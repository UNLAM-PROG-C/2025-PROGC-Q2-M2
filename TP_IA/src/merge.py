from __future__ import annotations

import math
from collections import defaultdict
from typing import Dict, Iterable, List, Tuple

import numpy as np


def merge_segments(
    segments: Iterable[Dict[str, float]],
    *,
    distance_threshold: float = 10.0,
    angle_threshold: float = 10.0,
) -> List[Dict[str, float]]:
    segments_list = [dict(seg) for seg in segments]
    n = len(segments_list)
    if n == 0:
        return []

    parent = list(range(n))

    def find(i: int) -> int:
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    def union(i: int, j: int) -> None:
        ri, rj = find(i), find(j)
        if ri != rj:
            parent[rj] = ri

    for i in range(n):
        for j in range(i + 1, n):
            if _should_merge(segments_list[i], segments_list[j], distance_threshold, angle_threshold):
                union(i, j)

    groups: Dict[int, List[Dict[str, float]]] = defaultdict(list)
    for idx, seg in enumerate(segments_list):
        groups[find(idx)].append(seg)

    merged: List[Dict[str, float]] = []
    for group in groups.values():
        merged.append(_merge_group(group))
    return merged


def _should_merge(a: Dict[str, float], b: Dict[str, float], distance_thresh: float, angle_thresh: float) -> bool:
    angle_diff = _angle_difference(a.get("angle", 0.0), b.get("angle", 0.0))
    if angle_diff > angle_thresh:
        return False
    dist = _minimal_endpoint_distance(a, b)
    return dist <= distance_thresh


def _angle_difference(a: float, b: float) -> float:
    diff = abs(a - b) % 180
    return min(diff, 180 - diff)


def _minimal_endpoint_distance(a: Dict[str, float], b: Dict[str, float]) -> float:
    endpoints_a = [(a["x1"], a["y1"]), (a["x2"], a["y2"])]
    endpoints_b = [(b["x1"], b["y1"]), (b["x2"], b["y2"])]
    return min(
        math.hypot(ax - bx, ay - by)
        for ax, ay in endpoints_a
        for bx, by in endpoints_b
    )


def _merge_group(group: List[Dict[str, float]]) -> Dict[str, float]:
    points = []
    direction = np.zeros(2, dtype=np.float64)
    for seg in group:
        p1 = np.array([seg["x1"], seg["y1"]], dtype=np.float64)
        p2 = np.array([seg["x2"], seg["y2"]], dtype=np.float64)
        points.extend([p1, p2])
        vec = p2 - p1
        norm = np.linalg.norm(vec)
        if norm > 0:
            direction += vec / norm
    if np.linalg.norm(direction) < 1e-6:
        direction = points[-1] - points[0]
    norm = np.linalg.norm(direction)
    if norm == 0:
        direction = np.array([1.0, 0.0])
    else:
        direction /= norm

    origin = np.mean(points, axis=0)
    projections = [np.dot(p - origin, direction) for p in points]
    min_proj = min(projections)
    max_proj = max(projections)
    start = origin + min_proj * direction
    end = origin + max_proj * direction

    score = max(seg.get("score", 0.0) for seg in group)
    detector_counts = {}
    for seg in group:
        det = seg.get("detector", "hough")
        detector_counts[det] = detector_counts.get(det, 0) + 1
    detector = max(detector_counts, key=detector_counts.get)
    tile_ids = sorted({int(seg.get("tile_id", -1)) for seg in group})

    angle = math.degrees(math.atan2(end[1] - start[1], end[0] - start[0])) % 180
    merged = {
        "x1": float(start[0]),
        "y1": float(start[1]),
        "x2": float(end[0]),
        "y2": float(end[1]),
        "score": float(score),
        "angle": float(angle),
        "detector": detector,
        "tile_id": tile_ids[0] if tile_ids else -1,
        "source_tiles": tile_ids,
    }
    return merged
