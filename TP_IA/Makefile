.PHONY: install test bench bench-plots synthetic

install:
	python3 -m pip install -e .

test:
	pytest -q

bench:
	python3 -m bench.bench --input data/sample/city.png --workers 1 2 4 8 --tile-size 256 512 --repeats 1

bench-plots:
	python3 -m bench.plots --summary bench/summary.csv --output-dir bench/plots

synthetic:
	python3 data/synthetic/generate.py
