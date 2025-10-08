from __future__ import annotations

import argparse
import csv
from collections import defaultdict
from pathlib import Path
from typing import List

from src import main as pipeline_main
from src import metrics as metrics_utils


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Benchmark sliding-window pipeline")
    parser.add_argument("--input", default="data/sample/city.png", help="Input image for benchmarks")
    parser.add_argument("--output-root", default="output/bench", help="Root directory for benchmark outputs")
    parser.add_argument("--workers", nargs="+", type=int, default=[1, 2, 4, 8], help="Worker counts to evaluate")
    parser.add_argument("--tile-size", nargs="+", type=int, default=[256, 512], help="Tile sizes to evaluate")
    parser.add_argument("--halo", type=int, default=32, help="Halo size")
    parser.add_argument("--repeats", type=int, default=1, help="Number of repeats per configuration")
    parser.add_argument("--detector", choices=["hough", "lsd"], default="hough", help="Detector for benchmarks")
    return parser.parse_args()


def build_arg_list(base: argparse.Namespace, output_dir: Path, workers: int, tile_size: int) -> List[str]:
    return [
        "--input",
        base.input,
        "--output-dir",
        str(output_dir),
        "--tile-size",
        str(tile_size),
        "--halo",
        str(base.halo),
        "--workers",
        str(workers),
        "--detector",
        base.detector,
        "--json-output",
        "segments.json",
        "--overlay-output",
        "overlay.png",
        "--metrics-output",
        "metrics.json",
    ]


def main() -> None:
    args = parse_args()
    output_root = Path(args.output_root)
    output_root.mkdir(parents=True, exist_ok=True)

    csv_rows = []
    time_by_config = defaultdict(list)

    for tile_size in args.tile_size:
        for workers in args.workers:
            for repeat in range(args.repeats):
                run_dir = output_root / f"tiles_{tile_size}" / f"workers_{workers}" / f"repeat_{repeat}"
                run_dir.mkdir(parents=True, exist_ok=True)
                arg_list = build_arg_list(args, run_dir, workers, tile_size)
                parsed = pipeline_main.parse_args(arg_list)
                result = pipeline_main.run_pipeline(parsed)
                total_time = float(result["total_time"])
                row = {
                    "input": args.input,
                    "tile_size": tile_size,
                    "halo": args.halo,
                    "workers": workers,
                    "repeat": repeat,
                    "total_time": total_time,
                    "num_segments": result["num_segments"],
                    "merge_overhead_percent": result["metrics"]["merge_overhead_percent"],
                }
                csv_rows.append(row)
                time_by_config[(tile_size, workers)].append(total_time)

    summary_rows = []
    for tile_size in args.tile_size:
        baseline_times = time_by_config.get((tile_size, 1))
        if not baseline_times:
            continue
        serial_time = sum(baseline_times) / len(baseline_times)
        for workers in args.workers:
            times = time_by_config.get((tile_size, workers))
            if not times:
                continue
            avg_time = sum(times) / len(times)
            speedup = metrics_utils.compute_speedup(serial_time, avg_time)
            efficiency = metrics_utils.compute_efficiency(speedup, workers)
            summary_rows.append({
                "input": args.input,
                "tile_size": tile_size,
                "workers": workers,
                "avg_time": avg_time,
                "speedup": speedup,
                "efficiency": efficiency,
            })

    csv_path = Path("bench/results.csv")
    with csv_path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(
            f,
            fieldnames=[
                "input",
                "tile_size",
                "halo",
                "workers",
                "repeat",
                "total_time",
                "num_segments",
                "merge_overhead_percent",
            ],
        )
        writer.writeheader()
        writer.writerows(csv_rows)

    summary_path = Path("bench/summary.csv")
    with summary_path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(
            f,
            fieldnames=["input", "tile_size", "workers", "avg_time", "speedup", "efficiency"],
        )
        writer.writeheader()
        writer.writerows(summary_rows)

    print(f"Wrote benchmark results to {csv_path} and {summary_path}")


if __name__ == "__main__":  # pragma: no cover
    main()
