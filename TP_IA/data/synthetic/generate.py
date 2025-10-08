#!/usr/bin/env python3
"""Generate synthetic line datasets with known ground truth."""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Tuple

import struct
import zlib

OUTPUT_DIR = Path(__file__).resolve().parent
GROUND_TRUTH_FILE = OUTPUT_DIR / "ground_truth.json"


@dataclass
class SyntheticSpec:
    filename: str
    size: Tuple[int, int]
    lines: Iterable[Tuple[Tuple[int, int], Tuple[int, int]]]


BACKGROUND = (5, 5, 5)
LINE_COLOR = (240, 240, 240)
LINE_THICKNESS = 4


def draw_line(buffer: bytearray, width: int, height: int, start: Tuple[int, int], end: Tuple[int, int]) -> None:
    x1, y1 = start
    x2, y2 = end
    dx = abs(x2 - x1)
    dy = -abs(y2 - y1)
    sx = 1 if x1 < x2 else -1
    sy = 1 if y1 < y2 else -1
    err = dx + dy
    x, y = x1, y1
    while True:
        for ox in range(-(LINE_THICKNESS // 2), LINE_THICKNESS // 2 + 1):
            for oy in range(-(LINE_THICKNESS // 2), LINE_THICKNESS // 2 + 1):
                xx = min(max(x + ox, 0), width - 1)
                yy = min(max(y + oy, 0), height - 1)
                idx = (yy * width + xx) * 3
                buffer[idx : idx + 3] = bytes(LINE_COLOR)
        if x == x2 and y == y2:
            break
        e2 = 2 * err
        if e2 >= dy:
            err += dy
            x += sx
        if e2 <= dx:
            err += dx
            y += sy


def write_png(path: Path, width: int, height: int, buffer: bytearray) -> None:
    row_stride = width * 3
    raw = b"".join(b"\x00" + buffer[y * row_stride : (y + 1) * row_stride] for y in range(height))
    compressed = zlib.compress(raw, level=9)

    def chunk(tag: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    ihdr = struct.pack(">I", width) + struct.pack(">I", height) + b"\x08\x02\x00\x00\x00"
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", compressed) + chunk(b"IEND", b"")
    path.write_bytes(png)


def generate_images() -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    specs = [
        SyntheticSpec(
            filename="cross_lines.png",
            size=(512, 512),
            lines=[((40, 40), (470, 470)), ((470, 40), (40, 470)), ((256, 20), (256, 492))],
        ),
        SyntheticSpec(
            filename="parallel_lines.png",
            size=(512, 512),
            lines=[
                ((20, 50), (492, 50)),
                ((20, 150), (492, 150)),
                ((20, 250), (492, 250)),
                ((20, 350), (492, 350)),
            ],
        ),
    ]

    ground_truth = {}
    for spec in specs:
        width, height = spec.size
        buffer = bytearray(width * height * 3)
        bg = bytes(BACKGROUND)
        for idx in range(0, len(buffer), 3):
            buffer[idx : idx + 3] = bg
        for start, end in spec.lines:
            draw_line(buffer, width, height, start, end)
        path = OUTPUT_DIR / spec.filename
        write_png(path, width, height, buffer)
        ground_truth[spec.filename] = {
            "lines": [
                {"x1": float(start[0]), "y1": float(start[1]), "x2": float(end[0]), "y2": float(end[1])}
                for start, end in spec.lines
            ]
        }

    with GROUND_TRUTH_FILE.open("w", encoding="utf-8") as f:
        json.dump(ground_truth, f, indent=2)


if __name__ == "__main__":  # pragma: no cover
    generate_images()
