# Reporte Técnico

## Metodología

1. **Segmentación y halo**: la imagen se divide en tiles cuadrados (`tile-size`) con un `halo` configurable que garantiza la continuidad de bordes entre mosaicos adyacentes. Se utiliza memoria compartida (`multiprocessing.shared_memory`) para evitar copias al distribuir work-items a los procesos.
2. **Pipeline por tile**: cada worker aplica Canny → Hough probabilístico (o LSD si está disponible) y normaliza los segmentos a coordenadas globales. La configuración se inyecta vía CLI/benchmark.
3. **Fusión**: se construye un grafo de segmentos y se agrupan con Union-Find utilizando umbrales de ángulo y distancia de extremos. El segmento resultante preserva los IDs de tiles originales (`source_tiles`).
4. **Instrumentación**: se registran tiempos por etapa (`load_image`, `tiling`, `per_tile_compute`, `merge`, `total_time`) y uso de CPU/memoria del proceso principal y workers (`psutil`).
5. **Benchmarking**: `bench/bench.py` evalúa escalabilidad fuerte (imagen fija, `workers` ∈ {1,2,4,8}) y débil (variando `tile-size`). El resumen (`bench/summary.csv`) calcula speedup `S(p) = T1/Tp` y eficiencia `E(p) = S(p)/p`. Los gráficos (`bench/plots/*.png`) muestran speedup, tiempo y eficiencia.

## Resultados esperados

- **Overhead de fusión**: típicamente <15% para tiles ≥256 px con `halo=32`; aumenta en tiles pequeños por mayor proporción de halos.
- **Speedup**: en hardware de 8 núcleos, la etapa `per_tile_compute` escala casi lineal hasta 4 workers; a partir de allí la eficiencia cae según la Ley de Amdahl (porción secuencial ≈10–15%).
- **Consumo de memoria**: dominado por la imagen compartida; overhead adicional marginal al crear tiles.

## Observaciones

- El detector LSD sólo está disponible si OpenCV se compila con módulos contrib. En caso contrario, el pipeline registra `lsd_available = false` y utiliza Hough, lo que puede degradar la detección de líneas cortas.
- El pipeline actual prioriza claridad sobre micro-optimizaciones: la fusión podría acelerarse con estructuras espaciales (R-tree o cuadrículas), pero el algoritmo O(n²) resulta suficiente para los volúmenes de segmentos típicos.
- Para datasets sintéticos con ground-truth (`data/synthetic`), es posible calcular métricas de precisión (`precision/recall/F1`) comparando los segmentos detectados contra las líneas esperadas. Esta funcionalidad se deja como extensión futura.

## Próximos pasos sugeridos

1. Integrar un evaluador de calidad que consuma `ground_truth.json` y compute métricas de detección.
2. Agregar soporte opcional para `numpy.memmap` cuando las imágenes excedan la RAM disponible.
3. Experimentar con planificadores de tareas más avanzados (por ejemplo, `Ray` o `joblib`) para estudios de escalabilidad distribuida.
4. Añadir un modo de “visualización rápida” que genere miniaturas de los tiles y las líneas detectadas para depurar escenarios anómalos.

