# Server

## Archivos

- main.rs: Es el punto de entrada del binario, bindea un socket tcp y queda en loop escuchando conexiones. Cuando un jugador se conecta se lo agrega a una cola, cuando la cola tiene 2 jugadores se inician 2 threads con un estado del juego compartido por un [Arc](https://doc.rust-lang.org/std/sync/struct.Arc.html)
- game_server.rs: Tiene la logica que maneja los mensajes ida y vuelta del servidor es un loop infinito que lee de la conexion tcp un mensaje de 5 bytes y dependiendo de que mensaje sea hace una de las siguientes acciones.
    - Mensaje: GetState -> Le pasa al cliente el estado entero del juego
    - Mensaje: Hit -> Intenta pegarle al tablero del oponente
    - Mensaje: PlaceBoat -> Intenta insertar un barco en el tablero del jugador
- board.rs: Maneja la logica del tablero de juego 

## main.rs

### Funciones

#### main

Bindea un socket tcp, luego hace un loop infinito encolando las conexiones entrantes hasta que llega a 2 en ese momento desencola 2 conexiones y spawnea 2 threads 1 por cada jugador los threads van a correr la funcion `handle_connection` de [game_server.rs](#game_serverrs).

## game_server.rs

### Structs/Enums

#### GameServer

```rust
pub struct GameServer {
    player_a: RwLock<Board>,
    player_b: RwLock<Board>,
    turn_player_a: AtomicBool,
    all_boats_placed_player_a: AtomicBool,
    all_boats_placed_player_b: AtomicBool,
}
```

El struct de GameServer tiene el estado entero del juego, todos los campos son [RwLock](https://doc.rust-lang.org/std/sync/struct.RwLock.html) o [AtomicBool](https://doc.rust-lang.org/std/sync/atomic/struct.AtomicBool.html) porque el estado debe ser mutado y leido concurrentemente por los 2 threads.

#### Player

```rust
pub enum Player {
    A,
    B,
}
```

El enum de Player distinge entre el jugador A y el jugador B para que el thread sepa a cual jugador esta atendiendo. Esto lo usamos para simplificar la logica del lado del cliente, siempre le pasamos en el mismo orden el estado del juego.

#### MessageType

```rust
#[repr(u8)]
enum MessageType {
    GetState = 0_u8,
    Hit,
    PlaceBoat,
}
```

El enum MessageType representa los 3 tipos posibles de mensajes el atributo `#[repr(u8)]` le dice al compilador de rust que cada variante del enum debe ocupar 1 byte, esto nos es util para que podamos manejar este campo como 1 byte en el mensaje que escribimos en el stream tcp desde godot.

#### ClientMessage

```rust
#[repr(C)]
struct ClientMessage {
    message_type: MessageType,
    x1: u8,
    y1: u8,
    x2: u8,
    y2: u8,
}
```

El struct ClientMessage representa un mensaje del cliente hacia el server. El atributo `#[repr(C)]` le indica al compilador que no puede reordenar los campos del struct, esto lo necesitamos ya que escribimos el mensaje en este orden especifico dentro del cliente en godot. Los campos x1,y1 son usados en mensajes de tipo `Hit` y `PlaceBoat` los campos x2,y2 solo en `PlaceBoat`. En mensajes de tipo `GetState` no usamos ningun campo extra.

### Funciones

#### handle_conection 

Es un loop infinito que lee a un buffer del tamaño de `ClientMessage` en el caso de que lea un mensaje correctamente se lo pasa a la funcion `handle_client_message` que le va a devovler un `bool` en caso de que la partida termine para poder terminar el loop y que se cierre el thread.

#### handle_client_message

La funcion se fija que tipo de mensaje recibio y para:
- `MessageType::PlaceBoat`: Intenta poner un barco llamando a la funcion `place_boat` del tablero del jugador correspondiente y despues actualiza el valor `all_boats_placed_player_n` llamando a la funcion `all_boats_placed` tambien sobre el tablero
- `MessageType::GetState`: Es la parte del codigo que escribe al stream tcp y lo que escribe es el estado entero de la partida que viene de llamar a la funcion `get_state` del server
- `MessageType::Hit`: Verifica que la partida no este en la fase de poner los barcos y despues intenta disparar al tablero del oponente llamando a la funcion `get_hit` del tablero.

#### get_state

Es la funcion encargada de encodear todo el estado del juego en un array de 202 bytes. La estructura del paquete es:

```
Byte 0: 0 si la partida esta en curso (ya se pusieron todos los barcos)
        1 si el jugador que esta atendiendo el thread ya puso todos los barcos pero el oponente todavia no
        2 si el jugador actual tiene que poner un barco de 2 de tamaño
        3 si el jugador actual tiene que poner un barco de 3 de tamaño
        4 si el jugador actual tiene que poner un barco de 4 de tamaño
        5 si el jugador actual tiene que poner un barco de 5 de tamaño
        254 si el jugador actual gano la partida
        255 si el jugador actual perdio la partida
Byte 1: 1 si es el turno del jugador
        0 si es el turno del oponente
Byte 2 al 101`: tablero del jugador actual donde cada byte tiene
               0 si la posicion esta vacia
               1 si la posicion contiene un barco
               2 si la posicion fue un HIT
               3 si la posicion fue un MISS
Byte 102 al 201: tablero del oponente actual donde cada byte tiene
               0 si la posicion esta vacia
               1 si la posicion contiene un barco <-- esto hay que arreglarlo porque el jugador puede leer esto y saber donde estan los barcos del otro jugador
               2 si la posicion fue un HIT
               3 si la posicion fue un MISS
```

## board.rs

### Structs/Enums

### Funciones

#### Board

```rust
pub struct Board {
    board: [[Slot; 10]; 10],
    boats_placed: HashMap<BoatLength, u8>,
    boats_to_place: Vec<BoatLength>,
    boat_idx: usize,
    hit_count: usize,
}
```

El struct de Board tiene el estado de un tablero de la batalla naval, 
- board es el tablero, 
- boats_placed lo usamos para tener un seguimiento de que barcos ya se pusieron en el tablero. 
- boats_to_place: tiene la secuencia de barcos que hay que poner
- boat_idx: te dice cual es es siguiente en la secuencia boats_to_place
- hit_count: cuenta las veces que le acertaron a un barco, cuando llega a 19 la partida termina y el jugador pierde

#### Slot 

```rust
#[repr(u8)]
pub enum Slot {
    #[default]
    Empty = 0,
    Boat = 1,
    Hit = 2,
    Missed = 3,
}
```

El enum Slot representa los 4 estados que puede tener una posicion en el tablero. Tiene el `#[repr(u8)]` porque se encodea como bytes en la funcion de `to_vec`

#### BoatLength

```rust
pub enum BoatLength {
    Five = 5,
    Four = 4,
    Three = 3,
    Two = 2,
}
```

Representa los 4 tamaños posibles de los barcos

### Funciones

#### default 

Crea el estado incial del tablero con:
- 1 barco de tamaño 5
- 1 barco de tamaño 4
- 2 barcos de tamaño 3
- 2 barcos de tamaño 2

#### get_hit

Tiene la logica para ser atacado, si la coordenada contiene un barco lo marcamos como `Slot::Hit`, si esta vacio lo marcamos como `Slot::Missed`.

#### lost

Devuelve si self.hit_count == 19, 19 es la suma de el tamaño de todos los barcos

#### place_boat

Tiene la logica para insertar un barco en el tablero, se fija si el barco esta horizontal o diagonal, verifica que el tamaño del barco que se esta queriendo insertar sea el esperado (el esperado sale de self.boats_to_place[self.boat_idx]) y verifica que el barco no choque con otro que ya exista si pasa las validaciones lo inserta en el tablero.

#### next_boat

Devuelve el proximo barco a insertar (self.boats_to_place[self.boat_idx])

#### to_vec

Encodea el estado del tablero a un vector de bytes para pasarle el estado del juego al cliente
