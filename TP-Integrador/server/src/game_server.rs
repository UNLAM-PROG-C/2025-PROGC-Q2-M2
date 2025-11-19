use crate::{
    board::{Board, BoatLength},
    logger,
};
use std::net::Shutdown;
use std::{
    io::{self, Read, Write},
    net::TcpStream,
    sync::{
        Mutex, RwLock,
        atomic::{AtomicBool, Ordering},
    },
};
const BOARD_SIZE: u8 = 10;
const CLIENT_HEADER_SIZE: usize = 3;
const SERVER_HEADER_SIZE: usize = 3;
const MAX_NAME_LENGTH: usize = 24;

#[derive(Default)]
pub struct GameServer {
    player_a: RwLock<Board>,
    player_b: RwLock<Board>,
    player_a_name: RwLock<Option<String>>,
    player_b_name: RwLock<Option<String>>,
    turn_player_a: AtomicBool,
    all_boats_placed_player_a: AtomicBool,
    all_boats_placed_player_b: AtomicBool,
    player_a_forfeited: AtomicBool,
    player_b_forfeited: AtomicBool,
    player_a_connection: Mutex<Option<TcpStream>>,
    player_b_connection: Mutex<Option<TcpStream>>,
}

pub struct PendingConnection {
    stream: TcpStream,
    prebuffer: Vec<u8>,
}

impl PendingConnection {
    pub fn new(stream: TcpStream) -> Self {
        Self {
            stream,
            prebuffer: Vec::new(),
        }
    }

    pub fn refresh(&mut self) -> bool {
        if let Err(err) = self.stream.set_nonblocking(true) {
            logger::log(&format!(
                "Failed to set non-blocking mode when checking connection: {err}"
            ));
            return false;
        }

        let mut temp = [0_u8; 512];
        let alive = loop {
            match self.stream.read(&mut temp) {
                Ok(0) => break false,
                Ok(n) => {
                    self.prebuffer.extend_from_slice(&temp[..n]);
                    continue;
                }
                Err(err)
                    if err.kind() == io::ErrorKind::WouldBlock
                        || err.kind() == io::ErrorKind::Interrupted =>
                {
                    break true;
                }
                Err(err) => {
                    logger::log(&format!(
                        "Failed to read from connection while waiting for opponent: {err}"
                    ));
                    break false;
                }
            }
        };

        if let Err(err) = self.stream.set_nonblocking(false) {
            logger::log(&format!(
                "Failed to restore blocking mode when checking connection: {err}"
            ));
        }

        alive
    }

    pub fn into_parts(self) -> (TcpStream, Vec<u8>) {
        (self.stream, self.prebuffer)
    }
}

#[derive(Debug, Clone, Copy)]
pub enum Player {
    A,
    B,
}

impl Player {
    fn opponent(self) -> Self {
        match self {
            Player::A => Player::B,
            Player::B => Player::A,
        }
    }
}

#[derive(Debug, Clone, Copy)]
#[repr(u8)]
enum ServerMessageType {
    StateUpdate = 0,
    NamesUpdate = 1,
}

#[derive(Debug, Clone)]
enum ClientMessage {
    GetState,
    Hit { x: u8, y: u8 },
    PlaceBoat { x1: u8, y1: u8, x2: u8, y2: u8 },
    SetName(String),
}

#[derive(Debug)]
enum ClientMessageParseError {
    UnknownMessageType(u8),
    InvalidLength { expected: usize, actual: usize },
    InvalidUtf8,
}

impl ClientMessage {
    fn from_parts(message_type_byte: u8, payload: &[u8]) -> Result<Self, ClientMessageParseError> {
        match message_type_byte {
            0 => {
                if !payload.is_empty() {
                    return Err(ClientMessageParseError::InvalidLength {
                        expected: 0,
                        actual: payload.len(),
                    });
                }
                Ok(Self::GetState)
            }
            1 => {
                if payload.len() != 2 {
                    return Err(ClientMessageParseError::InvalidLength {
                        expected: 2,
                        actual: payload.len(),
                    });
                }
                Ok(Self::Hit {
                    x: payload[0],
                    y: payload[1],
                })
            }
            2 => {
                if payload.len() != 4 {
                    return Err(ClientMessageParseError::InvalidLength {
                        expected: 4,
                        actual: payload.len(),
                    });
                }
                Ok(Self::PlaceBoat {
                    x1: payload[0],
                    y1: payload[1],
                    x2: payload[2],
                    y2: payload[3],
                })
            }
            3 => {
                let name = std::str::from_utf8(payload)
                    .map_err(|_| ClientMessageParseError::InvalidUtf8)?
                    .to_string();
                Ok(Self::SetName(name))
            }
            _ => Err(ClientMessageParseError::UnknownMessageType(
                message_type_byte,
            )),
        }
    }
}

struct SendResult {
    game_ended: bool,
}

impl GameServer {
    pub fn handle_connection(
        &self,
        mut connection: TcpStream,
        mut buffered: Vec<u8>,
        player: Player,
    ) {
        self.register_connection(player, &connection);
        if let Err(err) = self.send_state_update_to(player) {
            logger::log(&format!(
                "Failed to send initial state to {:?}: {err}",
                player
            ));
        }
        if let Err(err) = self.send_names_to(player) {
            logger::log(&format!(
                "Failed to send initial names to {:?}: {err}",
                player
            ));
        }

        let mut header = [0_u8; CLIENT_HEADER_SIZE];
        loop {
            match Self::read_exact_buffered(&mut buffered, &mut connection, &mut header) {
                Ok(()) => {
                    let message_type = header[0];
                    let payload_len = u16::from_le_bytes([header[1], header[2]]) as usize;

                    let mut payload = vec![0_u8; payload_len];
                    if payload_len > 0
                        && let Err(err) =
                            Self::read_exact_buffered(&mut buffered, &mut connection, &mut payload)
                    {
                        logger::log(&format!(
                            "Failed to read payload from tcp stream for {:?}: {err}",
                            player
                        ));
                        self.handle_disconnect(player);
                        break;
                    }

                    let message = match ClientMessage::from_parts(message_type, &payload) {
                        Ok(message) => message,
                        Err(ClientMessageParseError::UnknownMessageType(byte)) => {
                            logger::log(&format!("Received message with unknown type: {byte}"));
                            continue;
                        }
                        Err(ClientMessageParseError::InvalidLength { expected, actual }) => {
                            logger::log(&format!(
                                "Received message with invalid length. Expected {expected} got {actual}"
                            ));
                            continue;
                        }
                        Err(ClientMessageParseError::InvalidUtf8) => {
                            logger::log("Received name payload with invalid UTF-8 data");
                            continue;
                        }
                    };

                    if let Err(err) = Self::validate_message(&message) {
                        logger::log(&err);
                        continue;
                    }

                    let should_continue = self.handle_client_message(player, message);
                    if !should_continue {
                        break;
                    }
                }
                Err(err) => {
                    logger::log(&format!("Failed to read from tcp stream: {err}"));
                    self.handle_disconnect(player);
                    break;
                }
            }
        }

        self.unregister_connection(player);
    }

    fn read_buffer_bytes(buffer: &mut Vec<u8>, target: &mut [u8]) -> usize {
        if buffer.is_empty() {
            return 0;
        }
        let take = buffer.len().min(target.len());
        target[..take].copy_from_slice(&buffer[..take]);
        buffer.drain(..take);
        take
    }

    fn read_exact_buffered(
        buffer: &mut Vec<u8>,
        stream: &mut TcpStream,
        dst: &mut [u8],
    ) -> io::Result<()> {
        let copied = Self::read_buffer_bytes(buffer, dst);
        if copied < dst.len() {
            stream.read_exact(&mut dst[copied..])?;
        }
        Ok(())
    }

    fn validate_message(message: &ClientMessage) -> Result<(), String> {
        match message {
            ClientMessage::GetState => Ok(()),
            ClientMessage::Hit { x, y } => {
                if !Self::is_valid_cell(*x, *y) {
                    return Err(format!(
                        "Received hit message with out-of-bounds coordinates ({x}, {y})"
                    ));
                }
                Ok(())
            }
            ClientMessage::PlaceBoat { x1, y1, x2, y2 } => {
                if !Self::is_valid_cell(*x1, *y1) || !Self::is_valid_cell(*x2, *y2) {
                    return Err(format!(
                        "Received boat placement with out-of-bounds coordinates ({x1}, {y1}) -> ({x2}, {y2})"
                    ));
                }

                if x1 != x2 && y1 != y2 {
                    return Err(
                        "Received boat placement that is neither horizontal nor vertical"
                            .to_string(),
                    );
                }

                let length = if x1 == x2 {
                    y1.abs_diff(*y2) + 1
                } else {
                    x1.abs_diff(*x2) + 1
                };

                if BoatLength::from_length(length).is_none() {
                    return Err(format!(
                        "Received boat placement with invalid length {length}"
                    ));
                }

                Ok(())
            }
            ClientMessage::SetName(name) => {
                let trimmed = name.trim();
                if trimmed.is_empty() {
                    return Err("Received empty player name".to_string());
                }
                let char_count = trimmed.chars().count();
                if char_count > MAX_NAME_LENGTH {
                    return Err(format!(
                        "Received player name longer than {MAX_NAME_LENGTH} characters"
                    ));
                }
                Ok(())
            }
        }
    }

    fn is_valid_cell(x: u8, y: u8) -> bool {
        x < BOARD_SIZE && y < BOARD_SIZE
    }

    fn handle_client_message(&self, player: Player, message: ClientMessage) -> bool {
        let mut should_broadcast = false;
        let mut should_continue = true;

        match message {
            ClientMessage::PlaceBoat { x1, y1, x2, y2 } => {
                logger::log(&format!(
                    "{} -> PlaceBoat from ({x1}, {y1}) to ({x2}, {y2})",
                    self.player_label(player)
                ));
                match player {
                    Player::A => {
                        self.player_a
                            .write()
                            .expect("Couldn't place boat for player A")
                            .place_boat(x1, y1, x2, y2);
                        self.all_boats_placed_player_a.store(
                            self.player_a
                                .read()
                                .expect("Failed to read player A board")
                                .all_boats_placed(),
                            Ordering::Relaxed,
                        );
                    }
                    Player::B => {
                        self.player_b
                            .write()
                            .expect("Couldn't place boat for player B")
                            .place_boat(x1, y1, x2, y2);
                        self.all_boats_placed_player_b.store(
                            self.player_b
                                .read()
                                .expect("Failed to read player B board")
                                .all_boats_placed(),
                            Ordering::Relaxed,
                        );
                    }
                }
                should_broadcast = true;
            }
            ClientMessage::GetState => {
                logger::log(&format!("{} -> GetState", self.player_label(player)));
                match self.send_state_update_to(player) {
                    Ok(result) => {
                        if result.game_ended {
                            should_continue = false;
                        }
                    }
                    Err(err) => {
                        logger::log(&format!(
                            "Failed to send state update to {:?}: {err}",
                            player
                        ));
                        self.handle_disconnect(player);
                        return false;
                    }
                }
                if should_continue && let Err(err) = self.send_names_to(player) {
                    logger::log(&format!("Failed to send names to {:?}: {err}", player));
                }
            }
            ClientMessage::Hit { x, y } => {
                logger::log(&format!(
                    "{} -> Hit at ({x}, {y})",
                    self.player_label(player)
                ));
                if !self.all_boats_placed_player_a.load(Ordering::Relaxed)
                    && !self.all_boats_placed_player_b.load(Ordering::Relaxed)
                {
                    logger::log("Hit attempt received before all boats were placed");
                    return true;
                }

                let turn_player_a = self.turn_player_a.load(Ordering::Acquire);
                let mut hit_performed = false;

                match player {
                    Player::A => {
                        if turn_player_a {
                            self.player_b
                                .write()
                                .expect("Couldnt write to player b board")
                                .get_hit(x, y);
                            self.turn_player_a.store(false, Ordering::Release);
                            hit_performed = true;
                        }
                    }
                    Player::B => {
                        if !turn_player_a {
                            self.player_a
                                .write()
                                .expect("Couldnt write to player a board")
                                .get_hit(x, y);
                            self.turn_player_a.store(true, Ordering::Release);
                            hit_performed = true;
                        }
                    }
                }

                should_broadcast = hit_performed;
            }
            ClientMessage::SetName(name) => {
                let trimmed = name.trim();
                let previous_label = self.player_label(player);
                self.set_player_name(player, Some(trimmed.to_string()));
                logger::log(&format!("{} is now known as {trimmed}", previous_label));
                self.broadcast_names();
            }
        }

        if should_broadcast {
            let game_ended = self.broadcast_state_update();
            if game_ended {
                return false;
            }
        }

        should_continue
    }

    fn broadcast_state_update(&self) -> bool {
        let mut game_ended = false;
        for player in [Player::A, Player::B] {
            match self.send_state_update_to(player) {
                Ok(result) => {
                    game_ended |= result.game_ended;
                }
                Err(err) => {
                    logger::log(&format!(
                        "Failed to send state update to {:?}: {err}",
                        player
                    ));
                    self.handle_disconnect(player);
                }
            }
        }
        game_ended
    }

    fn send_state_update_to(&self, player: Player) -> io::Result<SendResult> {
        let (state, game_ended) = self.get_state(player);
        self.write_message(player, ServerMessageType::StateUpdate, &state)?;
        Ok(SendResult { game_ended })
    }

    fn register_connection(&self, player: Player, connection: &TcpStream) {
        let cloned = connection
            .try_clone()
            .expect("Failed to clone tcp stream for player");
        *self
            .connection_mutex(player)
            .lock()
            .expect("Mutex poisoned") = Some(cloned);
    }

    fn unregister_connection(&self, player: Player) {
        self.connection_mutex(player)
            .lock()
            .expect("Mutex poisoned")
            .take();
    }

    fn connection_mutex(&self, player: Player) -> &Mutex<Option<TcpStream>> {
        match player {
            Player::A => &self.player_a_connection,
            Player::B => &self.player_b_connection,
        }
    }

    fn player_name_lock(&self, player: Player) -> &RwLock<Option<String>> {
        match player {
            Player::A => &self.player_a_name,
            Player::B => &self.player_b_name,
        }
    }

    fn player_name(&self, player: Player) -> Option<String> {
        self.player_name_lock(player)
            .read()
            .expect("Failed to read player name")
            .clone()
            .filter(|name| !name.trim().is_empty())
    }

    fn set_player_name(&self, player: Player, name: Option<String>) {
        *self
            .player_name_lock(player)
            .write()
            .expect("Failed to write player name") = name;
    }

    fn player_label(&self, player: Player) -> String {
        self.player_name(player)
            .unwrap_or_else(|| format!("Player {:?}", player))
    }

    fn write_message(
        &self,
        player: Player,
        message_type: ServerMessageType,
        payload: &[u8],
    ) -> io::Result<()> {
        if payload.len() > u16::MAX as usize {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "Message payload larger than u16::MAX",
            ));
        }
        let mut header = [0_u8; SERVER_HEADER_SIZE];
        header[0] = message_type as u8;
        header[1..3].copy_from_slice(&(payload.len() as u16).to_le_bytes());

        let mut guard = self
            .connection_mutex(player)
            .lock()
            .expect("Mutex poisoned");
        if let Some(stream) = guard.as_mut() {
            stream.write_all(&header)?;
            if !payload.is_empty() {
                stream.write_all(payload)?;
            }
        }
        Ok(())
    }

    fn send_names_to(&self, player: Player) -> io::Result<()> {
        let self_name = self.player_name(player).unwrap_or_default();
        let opponent_name = self.player_name(player.opponent()).unwrap_or_default();
        let self_bytes = self_name.as_bytes();
        let opponent_bytes = opponent_name.as_bytes();
        let self_len = self_bytes.len().min(u8::MAX as usize);
        let opponent_len = opponent_bytes.len().min(u8::MAX as usize);

        let mut payload = Vec::with_capacity(2 + self_len + opponent_len);
        payload.push(self_len as u8);
        payload.extend_from_slice(&self_bytes[..self_len]);
        payload.push(opponent_len as u8);
        payload.extend_from_slice(&opponent_bytes[..opponent_len]);

        self.write_message(player, ServerMessageType::NamesUpdate, &payload)
    }

    fn broadcast_names(&self) {
        for player in [Player::A, Player::B] {
            if let Err(err) = self.send_names_to(player) {
                logger::log(&format!("Failed to send names to {:?}: {err}", player));
            }
        }
    }

    fn handle_disconnect(&self, player: Player) {
        // Marca forfeit para el jugador que se desconectó
        match player {
            Player::A => {
                self.player_a_forfeited.store(true, Ordering::Release);
            }
            Player::B => {
                self.player_b_forfeited.store(true, Ordering::Release);
            }
        }

        // Intentá cerrar/cortar la conexión del jugador desconectado (si existe)
        if let Some(stream) = self
            .connection_mutex(player)
            .lock()
            .expect("Mutex poisoned")
            .take()
        {
            // Intentar un shutdown (ignore error, solo intentamos limpiar)
            let _ = stream.shutdown(Shutdown::Both);
            // stream será dropeado al salir del scope
        }

        // Borramos el nombre del jugador desconectado
        self.set_player_name(player, None);

        // Calculamos el oponente
        let opponent = player.opponent();

        // Intentamos notificar inmediatamente al oponente con el nuevo estado.
        // Usamos send_state_update_to (que usa get_state y write_message).
        // Si falla, limpiamos la conexión del oponente también.
        match self.send_state_update_to(opponent) {
            Ok(_) => {
                // También actualizamos los nombres (avisar que el otro se fue)
                if let Err(err) = self.send_names_to(opponent) {
                    logger::log(&format!(
                        "Failed to send updated names to {:?}: {err}",
                        opponent
                    ));
                }
            }
            Err(err) => {
                logger::log(&format!(
                    "Failed to notify {:?} about opponent disconnect: {err}",
                    opponent
                ));
                // Si no podemos notificar al oponente, es probable que también esté desconectado:
                // limpiamos su conexión y su nombre.
                self.unregister_connection(opponent);
                self.set_player_name(opponent, None);
            }
        }
    }

    /// This function encodes the entire state of the game in a 202 byte array
    ///
    /// Byte 0: 0 if all the boats are placed for both players 1 if waiting for other player to finish placing boats
    ///         else its the length of the next boat to place. 255 if the player lost 254 if the player won
    ///
    /// Byte 1: 1 if its the player turn 0 if it isn't
    ///
    /// Bytes [2..101): State of the player's board
    ///
    /// Bytes [101..202): State of the opponent's board
    ///
    /// Returns the game state in a 202 byte array and a bool that marks the game as ended
    fn get_state(&self, player: Player) -> (Vec<u8>, bool) {
        let player_a_board = self
            .player_a
            .read()
            .expect("Failed to read player a board")
            .to_vec();
        let player_b_board = self
            .player_b
            .read()
            .expect("Failed to read player b board")
            .to_vec();

        let mut response = Vec::with_capacity(202);

        let player_a_forfeited = self.player_a_forfeited.load(Ordering::Acquire);
        let player_b_forfeited = self.player_b_forfeited.load(Ordering::Acquire);

        let player_a_lost = self.player_a.read().expect("Failed to read board").lost();
        let player_b_lost = self.player_b.read().expect("Failed to read board").lost();
        let placing_boats = !(self.all_boats_placed_player_a.load(Ordering::Relaxed)
            && self.all_boats_placed_player_b.load(Ordering::Relaxed));

        match player {
            Player::A => {
                if player_a_forfeited {
                    response.push(255_u8);
                    response.push(self.turn_player_a.load(Ordering::Relaxed) as u8);
                    response.extend_from_slice(&player_a_board);
                    response.extend_from_slice(&player_b_board);
                    return (response, true);
                } else if player_b_forfeited {
                    response.push(254_u8);
                    response.push(self.turn_player_a.load(Ordering::Relaxed) as u8);
                    response.extend_from_slice(&player_a_board);
                    response.extend_from_slice(&player_b_board);
                    return (response, true);
                }

                if let Some(next_boat_player_a) = self
                    .player_a
                    .read()
                    .expect("Failed to read board")
                    .next_boat()
                {
                    response.push(*next_boat_player_a as u8);
                } else if !placing_boats {
                    if player_a_lost {
                        response.push(255_u8);
                    } else if player_b_lost {
                        response.push(254_u8);
                    } else {
                        response.push(placing_boats as u8);
                    }
                } else {
                    response.push(placing_boats as u8);
                }

                response.push(self.turn_player_a.load(Ordering::Relaxed) as u8);
                response.extend_from_slice(&player_a_board);
                response.extend_from_slice(&player_b_board);
            }
            Player::B => {
                if player_b_forfeited {
                    response.push(255_u8);
                    response.push((!self.turn_player_a.load(Ordering::Relaxed)) as u8);
                    response.extend_from_slice(&player_b_board);
                    response.extend_from_slice(&player_a_board);
                    return (response, true);
                } else if player_a_forfeited {
                    response.push(254_u8);
                    response.push((!self.turn_player_a.load(Ordering::Relaxed)) as u8);
                    response.extend_from_slice(&player_b_board);
                    response.extend_from_slice(&player_a_board);
                    return (response, true);
                }

                if let Some(next_boat_player_b) = self
                    .player_b
                    .read()
                    .expect("Failed to read board")
                    .next_boat()
                {
                    response.push(*next_boat_player_b as u8);
                } else if !placing_boats {
                    if player_a_lost {
                        response.push(254_u8);
                    } else if player_b_lost {
                        response.push(255_u8);
                    } else {
                        response.push(placing_boats as u8);
                    }
                } else {
                    response.push(placing_boats as u8);
                }

                response.push(!self.turn_player_a.load(Ordering::Relaxed) as u8);
                response.extend_from_slice(&player_b_board);
                response.extend_from_slice(&player_a_board);
            }
        }
        debug_assert_eq!(response.len(), 202);
        (
            response,
            player_a_lost || player_b_lost || player_a_forfeited || player_b_forfeited,
        )
    }
}
