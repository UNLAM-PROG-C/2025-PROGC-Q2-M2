# VibeCode Sliding Windows

Herramienta para detección de líneas a gran escala mediante ventanas móviles con halos, procesamiento concurrente y reporte automático de métricas.

## Requisitos

- Python 3.9 o superior
- Dependencias Python (ver `pyproject.toml`): `numpy`, `opencv-python`, `psutil`, `matplotlib`, `pytest`
- Opcional para LSD/FLD: `opencv-contrib-python`

## Instalación

```bash
python -m venv .venv
source .venv/bin/activate  # En Windows: .venv\Scripts\activate
pip install -e .
```

> Nota: si sólo querés instalar dependencias sin modo editable, ejecutá `pip install -r requirements.txt` luego de generarlo (ver sección siguiente).

## Datos de ejemplo

- `data/sample`: tres imágenes sintéticas listas para validar el pipeline.
- `data/synthetic`: generadas por `python data/synthetic/generate.py`, con `ground_truth.json` para evaluar calidad y reproducibilidad.

## Uso básico

```bash
python3 -m src.main --input data/sample/city.png --tile-size 512 --halo 32 --workers 4 --detector hough
```

Parámetros clave:

- `--tile-size`: tamaño del mosaico en píxeles (default `512`).
- `--halo`: solapamiento entre tiles (default `32`).
- `--workers`: cantidad de procesos (`min(núcleos, 8)` por defecto).
- `--detector`: `hough` (default) o `lsd` (requiere OpenCV contrib; fallback a Hough si no está disponible).
- `--distance-threshold` / `--angle-threshold`: controlan la fusión de segmentos entre tiles.
- `--no-overlay`: evita generar el PNG con líneas superpuestas.

Outputs principales:

- JSON con segmentos en coordenadas globales y metadatos de tile.
- PNG con overlay de líneas (opcional).
- JSON con métricas de tiempo por etapa, overhead de merge y uso de CPU/memoria.

## Benchmarks

```bash
python -m bench.bench --input data/sample/city.png --workers 1 2 4 8 --tile-size 256 512 --repeats 3
python -m bench.plots --summary bench/summary.csv --output-dir bench/plots
```

Se generan:

- `bench/results.csv`: tiempos por repetición.
- `bench/summary.csv`: promedio, speedup y eficiencia.
- `bench/plots/*.png`: gráficos de speedup, tiempo y eficiencia por tamaño de tile.

## Pruebas

```bash
pytest -q
```

## Notas sobre LSD

En entornos sin `opencv-contrib-python`, el modo `--detector lsd` emite una advertencia y utiliza Hough probabilístico. Esta limitación está documentada en `docs/REPORT.md`.

## Scripts auxiliares

- `data/synthetic/generate.py`: regenera dataset sintético y ground-truth con semilla fija.
- `bench/bench.py`: barridos automáticos de parámetros y concurrencia.
- `bench/plots.py`: visualización de resultados de benchmark.

