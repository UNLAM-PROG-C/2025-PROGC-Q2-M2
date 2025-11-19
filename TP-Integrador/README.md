# Proyecto integrador

## Requisitos

- [Godot](https://godotengine.org/download/)
- [Rust](https://rust-lang.org/tools/install/)

## Como correrlo

### Server

Desde el root del repo:

```shell
cd TP-Integrador/server
```

```shell
cargo run --release
```

Deberia iniciar el server y mostrar:

```
Accepting connections at 127.0.0.1:1234
```

### Juego

Desde godot en la pestaña de `Debug -> Customize Run Instances` asegurarse que el checkbox de `Enable Multiple Instances` esta activado y la cantidad de instancias es 2 o mas.

Iniciar el juego con F5 o con el boton de play en la esquina superior derecha. Deberia abrir 2 instancias del juego.
