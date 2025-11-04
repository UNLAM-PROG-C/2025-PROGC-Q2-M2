use crate::board::{Board, BoatLength};
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

#[derive(Default)]
pub struct GameServer {
    player_a: RwLock<Board>,
    player_b: RwLock<Board>,
    turn_player_a: AtomicBool,
    all_boats_placed_player_a: AtomicBool,
    all_boats_placed_player_b: AtomicBool,
    player_a_forfeited: AtomicBool,
    player_b_forfeited: AtomicBool,
    player_a_connection: Mutex<Option<TcpStream>>,
    player_b_connection: Mutex<Option<TcpStream>>,
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
enum ClientMessageType {
    GetState = 0,
    Hit = 1,
    PlaceBoat = 2,
}

impl ClientMessageType {
    fn from_byte(value: u8) -> Option<Self> {
        match value {
            0 => Some(Self::GetState),
            1 => Some(Self::Hit),
            2 => Some(Self::PlaceBoat),
            _ => None,
        }
    }
}

#[derive(Debug, Clone, Copy)]
#[repr(u8)]
enum ServerMessageType {
    StateUpdate = 0,
}

#[derive(Debug, Clone, Copy)]
struct ClientMessage {
    message_type: ClientMessageType,
    x1: u8,
    y1: u8,
    x2: u8,
    y2: u8,
}

#[derive(Debug)]
enum ClientMessageParseError {
    UnknownMessageType(u8),
    InvalidLength { expected: usize, actual: usize },
}

impl ClientMessage {
    fn from_parts(message_type_byte: u8, payload: &[u8]) -> Result<Self, ClientMessageParseError> {
        let Some(message_type) = ClientMessageType::from_byte(message_type_byte) else {
            return Err(ClientMessageParseError::UnknownMessageType(
                message_type_byte,
            ));
        };

        match message_type {
            ClientMessageType::GetState => {
                if !payload.is_empty() {
                    return Err(ClientMessageParseError::InvalidLength {
                        expected: 0,
                        actual: payload.len(),
                    });
                }
                Ok(Self {
                    message_type,
                    x1: 0,
                    y1: 0,
                    x2: 0,
                    y2: 0,
                })
            }
            ClientMessageType::Hit => {
                if payload.len() != 2 {
                    return Err(ClientMessageParseError::InvalidLength {
                        expected: 2,
                        actual: payload.len(),
                    });
                }
                Ok(Self {
                    message_type,
                    x1: payload[0],
                    y1: payload[1],
                    x2: 0,
                    y2: 0,
                })
            }
            ClientMessageType::PlaceBoat => {
                if payload.len() != 4 {
                    return Err(ClientMessageParseError::InvalidLength {
                        expected: 4,
                        actual: payload.len(),
                    });
                }
                Ok(Self {
                    message_type,
                    x1: payload[0],
                    y1: payload[1],
                    x2: payload[2],
                    y2: payload[3],
                })
            }
        }
    }
}

struct SendResult {
    game_ended: bool,
}

impl GameServer {
    pub fn handle_connection(&self, mut connection: TcpStream, player: Player) {
        self.register_connection(player, &connection);
        if let Err(err) = self.send_state_update_to(player) {
            eprintln!("Failed to send initial state to {:?}: {err}", player);
        }

        let mut header = [0_u8; CLIENT_HEADER_SIZE];
        loop {
            match connection.read_exact(&mut header) {
                Ok(()) => {
                    let message_type = header[0];
                    let payload_len = u16::from_le_bytes([header[1], header[2]]) as usize;

                    let mut payload = vec![0_u8; payload_len];
                    if payload_len > 0 {
                        if let Err(err) = connection.read_exact(&mut payload) {
                            eprintln!(
                                "Failed to read payload from tcp stream for {:?}: {err}",
                                player
                            );
                            self.handle_disconnect(player);
                            break;
                        }
                    }

                    let message = match ClientMessage::from_parts(message_type, &payload) {
                        Ok(message) => message,
                        Err(ClientMessageParseError::UnknownMessageType(byte)) => {
                            eprintln!("Received message with unknown type: {byte}");
                            continue;
                        }
                        Err(ClientMessageParseError::InvalidLength { expected, actual }) => {
                            eprintln!(
                                "Received message with invalid length. Expected {expected} got {actual}"
                            );
                            continue;
                        }
                    };

                    if let Err(err) = Self::validate_message(&message) {
                        eprintln!("{err}");
                        continue;
                    }

                    let should_continue = self.handle_client_message(player, message);
                    if !should_continue {
                        break;
                    }
                }
                Err(err) => {
                    eprintln!("Failed to read from tcp stream: {err}");
                    self.handle_disconnect(player);
                    break;
                }
            }
        }

        self.unregister_connection(player);
    }

    fn validate_message(message: &ClientMessage) -> Result<(), String> {
        match message.message_type {
            ClientMessageType::GetState => Ok(()),
            ClientMessageType::Hit => {
                if !Self::is_valid_cell(message.x1, message.y1) {
                    return Err(format!(
                        "Received hit message with out-of-bounds coordinates ({}, {})",
                        message.x1, message.y1
                    ));
                }
                Ok(())
            }
            ClientMessageType::PlaceBoat => {
                if !Self::is_valid_cell(message.x1, message.y1)
                    || !Self::is_valid_cell(message.x2, message.y2)
                {
                    return Err(format!(
                        "Received boat placement with out-of-bounds coordinates ({}, {}) -> ({}, {})",
                        message.x1, message.y1, message.x2, message.y2
                    ));
                }

                if message.x1 != message.x2 && message.y1 != message.y2 {
                    return Err(
                        "Received boat placement that is neither horizontal nor vertical"
                            .to_string(),
                    );
                }

                let length = if message.x1 == message.x2 {
                    message.y1.abs_diff(message.y2) + 1
                } else {
                    message.x1.abs_diff(message.x2) + 1
                };

                if BoatLength::from_length(length).is_none() {
                    return Err(format!(
                        "Received boat placement with invalid length {length}"
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

        match message.message_type {
            ClientMessageType::PlaceBoat => {
                match player {
                    Player::A => {
                        self.player_a
                            .write()
                            .expect("Couldn't place boat for player A")
                            .place_boat(message.x1, message.y1, message.x2, message.y2);
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
                            .place_boat(message.x1, message.y1, message.x2, message.y2);
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
            ClientMessageType::GetState => match self.send_state_update_to(player) {
                Ok(result) => {
                    if result.game_ended {
                        return false;
                    }
                }
                Err(err) => {
                    eprintln!("Failed to send state update to {:?}: {err}", player);
                    self.handle_disconnect(player);
                    return false;
                }
            },
            ClientMessageType::Hit => {
                if !self.all_boats_placed_player_a.load(Ordering::Relaxed)
                    && !self.all_boats_placed_player_b.load(Ordering::Relaxed)
                {
                    eprintln!("Tried to hit a boat while still placing boats");
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
                                .get_hit(message.x1, message.y1);
                            self.turn_player_a.store(false, Ordering::Release);
                            hit_performed = true;
                        }
                    }
                    Player::B => {
                        if !turn_player_a {
                            self.player_a
                                .write()
                                .expect("Couldnt write to player a board")
                                .get_hit(message.x1, message.y1);
                            self.turn_player_a.store(true, Ordering::Release);
                            hit_performed = true;
                        }
                    }
                }

                should_broadcast = hit_performed;
            }
        }

        if should_broadcast {
            let game_ended = self.broadcast_state_update();
            if game_ended {
                return false;
            }
        }

        true
    }

    fn broadcast_state_update(&self) -> bool {
        let mut game_ended = false;
        for player in [Player::A, Player::B] {
            match self.send_state_update_to(player) {
                Ok(result) => {
                    game_ended |= result.game_ended;
                }
                Err(err) => {
                    eprintln!("Failed to send state update to {:?}: {err}", player);
                    self.handle_disconnect(player);
                }
            }
        }
        game_ended
    }

    fn send_state_update_to(&self, player: Player) -> io::Result<SendResult> {
        let (state, game_ended) = self.get_state(player);
        if state.len() > u16::MAX as usize {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "State payload larger than u16::MAX",
            ));
        }
        let mut header = [0_u8; SERVER_HEADER_SIZE];
        header[0] = ServerMessageType::StateUpdate as u8;
        header[1..3].copy_from_slice(&(state.len() as u16).to_le_bytes());

        let mut guard = self
            .connection_mutex(player)
            .lock()
            .expect("Mutex poisoned");
        if let Some(stream) = guard.as_mut() {
            stream.write_all(&header)?;
            if !state.is_empty() {
                stream.write_all(&state)?;
            }
        }

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

    fn handle_disconnect(&self, player: Player) {
        match player {
            Player::A => {
                self.player_a_forfeited.store(true, Ordering::Release);
            }
            Player::B => {
                self.player_b_forfeited.store(true, Ordering::Release);
            }
        }
        self.unregister_connection(player);

        let opponent = player.opponent();
        if let Err(err) = self.send_state_update_to(opponent) {
            eprintln!(
                "Failed to notify {:?} about opponent disconnect: {err}",
                opponent
            );
            self.unregister_connection(opponent);
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
