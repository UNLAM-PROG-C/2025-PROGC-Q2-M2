# Instrucciones de como usarlo 
Primero, instalar todo si es necesario (Python, venv). Depende de tu OS
Segundo, Instalar el env, las dependencias y correr el programa
```
python3 -m venv env
source env/bin/activate
pip install -r requirements.txt 
python3 -m src.main --input data/sample/30-08-00\:44_44.png --tile-size 512 --halo 32 --workers 4 --detector hough
```