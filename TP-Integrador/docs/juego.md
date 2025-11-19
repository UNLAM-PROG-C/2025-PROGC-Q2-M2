# Juego

## Archivos

### Scripts

- network/connection.gd: Es el [singleton](https://docs.godotengine.org/en/stable/tutorials/scripting/singletons_autoload.html) que tiene el estado de la conexion TCP.
- scripts/board.gd: Tiene la logica que maneja la creacion de los tableros, el mensaje para atacar una posicion y el mensaje para poner un barco.
- scripts/connection_manager.gd: Tiene la logica que cada 50ms le pide al server el estado del juego y actualiza los tableros de juego con la respuesta
- scripts/main_menu.gd: Tiene la logica para manejar la pantalla principal que pide una ip y se conecta al server
- scripts/cell_button: Por ahora no se usa pero la idea era tener la logica de los botones que componen al tablero aca

### Scenes

- scenes/game/board.tscn: Es la pantalla principal de juego, tiene los dos tableros para el jugador y el oponente
- scenes/game/cell_button.tscn: por ahora no se usa misma razon que el script
- scenes/game/lost.tscn: una pantalla que te indica que perdiste
- scenes/game/won.tscn: una pantalla que te indica que ganaste

## network/connection.gd

### Globales

#### status: ConnectionStatus

#### tcp: StreamPeerTCP

### Enums

```python
enum ConnectionStatus {
	DISCONNECTED,
	CONNECTING,
	CONNECTED,
	FAILED
}
```

representa los posibles estados de la conexion tcp


## scripts/board.gd

### Globales

#### button_grid_player_1: array con los botones del jugador
#### button_grid_player_2: array con los botones del oponente
#### pre_start_mode := true -> true si estamos en la etapa de poner los barcos, else si la partida esta en curso
#### current_ship_size -> valor del barco a colocar
#### current_orientation := "horizontal" -> "horizontal" o "vertical" para la orientacion del barco a colocar
#### highlighted_cells -> los botones que ocuparia el barco si se coloca
#### last_hover_start -> boton sobre el que estamos parados para poner el barco
#### last_hover_end -> boton donde terminaria el barco que vamos a poner

### Funciones

#### _input

Maneja el evento "rotate" que se emite cuando el usuario aprieta la `r` para rotar el barco

#### _ready

Se ejecuta al iniciar el juego, crea todos los botones para el tablero y deshabilita los del oponente hasta que se empiece el juego.

#### _hit_boat

Manda el mensaje de tipo `hit` al server con la posicion del boton que se eligio

#### _on_cell_pressed

Manda al server el mensaje para poner el barco usando `last_hover_start` y `last_hover_end` para obtener las coordenadas

#### _on_cell_hover_enter

Se ejecuta cuando te paras encima de un boton de tu tablero y marca donde quedaria el barco

#### clear_highlight

limpia las marcas que agrega `_on_cell_hover_enter`

#### switch_to_start

Cambia el valor de `pre_start_mode`, habilita todos los botones del tablero del oponente para empezar el juego

#### switch_to_waiting_for_other_player

Se ejecuta cuando ya pusimos todos los barcos en nuestro tablero pero el otro jugador no, deshabilita todos los botones de nuestro tablero

## scripts/connection_manager

### Funciones

#### _ready

Corre al iniciar el juego y le asigna la funcion `_on_start_button_pressed` al boton de conectar

#### _on_start_button_pressed

Tiene la logica para que al apretar el boton de conectar se le diga intente conectarse al server y si la conexion sale bien inicia la partida

#### connect_to_host_and_check_success

Se conecta al socket tcp con una logica simple de reintentos para la conexion
