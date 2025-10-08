from __future__ import annotations

import argparse
import csv
from collections import defaultdict
from pathlib import Path

import matplotlib.pyplot as plt


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Generate benchmark plots")
    parser.add_argument("--summary", default="bench/summary.csv", help="Summary CSV path")
    parser.add_argument("--output-dir", default="bench/plots", help="Directory for plots")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    groups = defaultdict(list)
    with Path(args.summary).open("r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            tile_size = int(row["tile_size"])
            workers = int(row["workers"])
            avg_time = float(row["avg_time"])
            speedup = float(row["speedup"])
            efficiency = float(row["efficiency"])
            groups[tile_size].append({
                "workers": workers,
                "avg_time": avg_time,
                "speedup": speedup,
                "efficiency": efficiency,
            })

    for tile_size, rows in groups.items():
        rows.sort(key=lambda r: r["workers"])
        workers = [r["workers"] for r in rows]
        times = [r["avg_time"] for r in rows]
        speedups = [r["speedup"] for r in rows]
        efficiencies = [r["efficiency"] for r in rows]

        plt.figure()
        plt.plot(workers, speedups, marker="o")
        plt.xlabel("Workers")
        plt.ylabel("Speedup")
        plt.title(f"Speedup vs Workers (tile={tile_size})")
        plt.grid(True)
        plt.savefig(output_dir / f"speedup_tile_{tile_size}.png", dpi=150, bbox_inches="tight")
        plt.close()

        plt.figure()
        plt.plot(workers, times, marker="s")
        plt.xlabel("Workers")
        plt.ylabel("Average Time (s)")
        plt.title(f"Average Time vs Workers (tile={tile_size})")
        plt.grid(True)
        plt.savefig(output_dir / f"time_tile_{tile_size}.png", dpi=150, bbox_inches="tight")
        plt.close()

        plt.figure()
        plt.plot(workers, efficiencies, marker="^")
        plt.xlabel("Workers")
        plt.ylabel("Efficiency")
        plt.title(f"Efficiency vs Workers (tile={tile_size})")
        plt.grid(True)
        plt.savefig(output_dir / f"efficiency_tile_{tile_size}.png", dpi=150, bbox_inches="tight")
        plt.close()

    print(f"Saved plots to {output_dir}")


if __name__ == "__main__":  # pragma: no cover
    main()
