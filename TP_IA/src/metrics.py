from __future__ import annotations

import time
from contextlib import contextmanager
from dataclasses import dataclass, field
from typing import Dict, Iterable, List, Optional

import psutil


@dataclass
class MetricsRecorder:
    timings: Dict[str, float] = field(default_factory=dict)

    @contextmanager
    def time_stage(self, name: str):
        start = time.perf_counter()
        try:
            yield
        finally:
            duration = time.perf_counter() - start
            self.timings[name] = self.timings.get(name, 0.0) + duration

    def record(self, name: str, value: float) -> None:
        self.timings[name] = value


@dataclass
class ProcessMetrics:
    cpu_seconds: float
    memory_rss: int
    cpu_percent: float


@dataclass
class ResourceSnapshot:
    main: ProcessMetrics
    workers: Dict[int, ProcessMetrics]


class ProcessMonitor:
    def __init__(self) -> None:
        self.process = psutil.Process()
        self.start_time = time.perf_counter()
        self.start_cpu = self._collect_cpu_seconds(self.process)
        self.start_children = self._collect_child_cpu()

    def _collect_cpu_seconds(self, proc: psutil.Process) -> float:
        try:
            times = proc.cpu_times()
            return float(times.user + times.system)
        except psutil.Error:  # pragma: no cover
            return 0.0

    def _memory_rss(self, proc: psutil.Process) -> int:
        try:
            return int(proc.memory_info().rss)
        except psutil.Error:  # pragma: no cover
            return 0

    def _collect_child_cpu(self) -> Dict[int, float]:
        result: Dict[int, float] = {}
        for child in self.process.children(recursive=True):
            result[child.pid] = self._collect_cpu_seconds(child)
        return result

    def snapshot(self) -> ResourceSnapshot:
        elapsed = max(time.perf_counter() - self.start_time, 1e-6)
        main_cpu = max(self._collect_cpu_seconds(self.process) - self.start_cpu, 0.0)
        workers_metrics: Dict[int, ProcessMetrics] = {}
        for child in self.process.children(recursive=True):
            cpu_seconds = max(self._collect_cpu_seconds(child) - self.start_children.get(child.pid, 0.0), 0.0)
            workers_metrics[child.pid] = ProcessMetrics(
                cpu_seconds=cpu_seconds,
                memory_rss=self._memory_rss(child),
                cpu_percent=(cpu_seconds / elapsed) * 100.0,
            )
        main_metrics = ProcessMetrics(
            cpu_seconds=main_cpu,
            memory_rss=self._memory_rss(self.process),
            cpu_percent=(main_cpu / elapsed) * 100.0,
        )
        return ResourceSnapshot(main=main_metrics, workers=workers_metrics)


def compute_speedup(serial_time: float, parallel_time: float) -> float:
    if parallel_time <= 0:
        return 0.0
    return float(serial_time / parallel_time)


def compute_efficiency(speedup: float, workers: int) -> float:
    if workers <= 0:
        return 0.0
    return float(speedup / workers)


def summarize_speedup(results: Iterable[Dict[str, float]]) -> List[Dict[str, float]]:
    results_list = list(results)
    if not results_list:
        return []
    serial_time = min(res["total_time"] for res in results_list if res.get("workers", 0) == 1)
    summary: List[Dict[str, float]] = []
    for res in results_list:
        workers = int(res.get("workers", 1))
        total_time = float(res["total_time"])
        speedup = compute_speedup(serial_time, total_time)
        efficiency = compute_efficiency(speedup, workers)
        summary.append({
            "workers": workers,
            "total_time": total_time,
            "speedup": speedup,
            "efficiency": efficiency,
        })
    return summary
