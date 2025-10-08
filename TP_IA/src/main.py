from __future__ import annotations

import argparse
import json
import math
import os
import time
from concurrent.futures import ProcessPoolExecutor, as_completed
from pathlib import Path
from typing import List

from . import detect, merge, metrics, tiling
from .io_utils import (
    SharedImageHandle,
    create_shared_image,
    dump_metrics,
    ensure_dir,
    load_image,
    save_overlay,
    save_segments_json,
)


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Sliding-window line detection pipeline")
    parser.add_argument("--input", required=True, help="Input image path")
    parser.add_argument("--output-dir", default="output", help="Directory for outputs")
    parser.add_argument("--tile-size", type=int, default=512, help="Tile size in pixels")
    parser.add_argument("--halo", type=int, default=32, help="Halo size in pixels")
    parser.add_argument("--workers", type=int, default=min(os.cpu_count() or 1, 8), help="Number of worker processes")
    parser.add_argument("--detector", choices=["hough", "lsd"], default="hough", help="Line detector")
    parser.add_argument("--canny-low", type=int, default=50, help="Canny low threshold")
    parser.add_argument("--canny-high", type=int, default=150, help="Canny high threshold")
    parser.add_argument("--hough-rho", type=float, default=1.0, help="Hough rho resolution")
    parser.add_argument("--hough-theta", type=float, default=math.pi / 180, help="Hough theta resolution")
    parser.add_argument("--hough-threshold", type=int, default=50, help="Hough accumulation threshold")
    parser.add_argument("--hough-min-line-length", type=int, default=50, help="Minimum line length for Hough")
    parser.add_argument("--hough-max-line-gap", type=int, default=10, help="Maximum line gap for Hough")
    parser.add_argument("--distance-threshold", type=float, default=10.0, help="Distance threshold for merging")
    parser.add_argument("--angle-threshold", type=float, default=10.0, help="Angular threshold (degrees) for merging")
    parser.add_argument("--json-output", default="segments.json", help="Filename for segments JSON")
    parser.add_argument("--overlay-output", default="overlay.png", help="Filename for overlay PNG")
    parser.add_argument("--metrics-output", default="metrics.json", help="Filename for metrics JSON")
    parser.add_argument("--no-overlay", action="store_true", help="Skip overlay image generation")
    return parser.parse_args(argv)


def _build_detection_config(args: argparse.Namespace) -> detect.DetectionConfig:
    return detect.DetectionConfig(
        detector=args.detector,
        canny_low=args.canny_low,
        canny_high=args.canny_high,
        hough_rho=args.hough_rho,
        hough_theta=args.hough_theta,
        hough_threshold=args.hough_threshold,
        hough_min_line_length=args.hough_min_line_length,
        hough_max_line_gap=args.hough_max_line_gap,
    )


def _process_tiles(
    tiles: List[tiling.TileRegion],
    shared: SharedImageHandle,
    config: detect.DetectionConfig,
    workers: int,
) -> tuple[List[dict], List[dict]]:
    segments: List[dict] = []
    tile_stats: List[dict] = []
    with ProcessPoolExecutor(max_workers=workers) as executor:
        futures = [executor.submit(detect.process_tile, tile, shared.spec, config) for tile in tiles]
        for future in as_completed(futures):
            _, tile_segments, stats = future.result()
            segments.extend(tile_segments)
            tile_stats.append(stats)
    return segments, tile_stats


def run_pipeline(args: argparse.Namespace) -> dict:
    image_path = Path(args.input)
    if not image_path.exists():
        raise FileNotFoundError(f"Input image not found: {image_path}")

    output_dir = Path(args.output_dir)
    ensure_dir(output_dir)

    metrics_recorder = metrics.MetricsRecorder()
    monitor = metrics.ProcessMonitor()
    pipeline_start = time.perf_counter()

    with metrics_recorder.time_stage("load_image"):
        image = load_image(image_path)

    with metrics_recorder.time_stage("tiling"):
        tiles = tiling.generate_tiles(image.shape, args.tile_size, args.halo)

    detection_config = _build_detection_config(args)

    with metrics_recorder.time_stage("shared_memory_setup"):
        shared_handle = create_shared_image(image)

    try:
        with metrics_recorder.time_stage("per_tile_compute"):
            segments, tile_stats = _process_tiles(tiles, shared_handle, detection_config, args.workers)
    finally:
        shared_handle.close()
        shared_handle.unlink()

    with metrics_recorder.time_stage("merge"):
        merged_segments = merge.merge_segments(
            segments,
            distance_threshold=args.distance_threshold,
            angle_threshold=args.angle_threshold,
        )

    total_time = time.perf_counter() - pipeline_start
    metrics_recorder.record("total_time", total_time)
    resource_snapshot = monitor.snapshot()

    segments_sorted = sorted(merged_segments, key=lambda s: s.get("score", 0.0), reverse=True)

    json_path = output_dir / args.json_output
    save_segments_json(segments_sorted, json_path)

    overlay_path = None
    if not args.no_overlay:
        overlay_path = output_dir / args.overlay_output
        save_overlay(image, segments_sorted, overlay_path)

    metrics_payload = {
        "input": str(image_path),
        "workers": args.workers,
        "tile_size": args.tile_size,
        "halo": args.halo,
        "detector": args.detector,
        "lsd_available": detect.LSD_AVAILABLE,
        "num_tiles": len(tiles),
        "num_segments_raw": len(segments),
        "num_segments_merged": len(segments_sorted),
        "tile_stats": tile_stats,
        "timings": metrics_recorder.timings,
        "merge_overhead_percent": (metrics_recorder.timings.get("merge", 0.0) / total_time) * 100.0 if total_time else 0.0,
        "resource": {
            "main": {
                "cpu_seconds": resource_snapshot.main.cpu_seconds,
                "cpu_percent": resource_snapshot.main.cpu_percent,
                "memory_rss": resource_snapshot.main.memory_rss,
            },
            "workers": {
                str(pid): {
                    "cpu_seconds": proc.cpu_seconds,
                    "cpu_percent": proc.cpu_percent,
                    "memory_rss": proc.memory_rss,
                }
                for pid, proc in resource_snapshot.workers.items()
            },
        },
    }

    metrics_path = output_dir / args.metrics_output
    dump_metrics(metrics_payload, metrics_path)

    return {
        "segments_json": str(json_path),
        "overlay_png": str(overlay_path) if overlay_path else None,
        "metrics_json": str(metrics_path),
        "total_time": total_time,
        "num_segments": len(segments_sorted),
        "metrics": metrics_payload,
    }


def main() -> None:
    args = parse_args()
    result = run_pipeline(args)
    print(json.dumps(result, indent=2))


if __name__ == "__main__":  # pragma: no cover
    main()
