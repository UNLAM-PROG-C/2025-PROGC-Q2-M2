use crate::board::{Board, BoatLength};
use std::{
    io::{Read, Write},
    net::TcpStream,
    sync::{
        RwLock,
        atomic::{AtomicBool, Ordering},
    },
};

const BOARD_SIZE: u8 = 10;
const CLIENT_MESSAGE_SIZE: usize = 5;

#[derive(Default)]
pub struct GameServer {
    player_a: RwLock<Board>,
    player_b: RwLock<Board>,
    turn_player_a: AtomicBool,
    all_boats_placed_player_a: AtomicBool,
    all_boats_placed_player_b: AtomicBool,
    player_a_forfeited: AtomicBool,
    player_b_forfeited: AtomicBool,
}

#[derive(Debug)]
pub enum Player {
    A,
    B,
}

#[derive(Debug, Clone, Copy)]
#[repr(u8)]
enum MessageType {
    GetState = 0_u8,
    Hit,
    PlaceBoat,
}

impl MessageType {
    fn from_byte(byte: u8) -> Option<Self> {
        match byte {
            0 => Some(Self::GetState),
            1 => Some(Self::Hit),
            2 => Some(Self::PlaceBoat),
            _ => None,
        }
    }
}

#[derive(Debug, Clone, Copy)]
struct ClientMessage {
    message_type: MessageType,
    x1: u8,
    y1: u8,
    x2: u8,
    y2: u8,
}

#[derive(Debug)]
enum ClientMessageParseError {
    UnknownMessageType(u8),
}

impl ClientMessage {
    fn from_bytes(bytes: [u8; CLIENT_MESSAGE_SIZE]) -> Result<Self, ClientMessageParseError> {
        let Some(message_type) = MessageType::from_byte(bytes[0]) else {
            return Err(ClientMessageParseError::UnknownMessageType(bytes[0]));
        };

        Ok(Self {
            message_type,
            x1: bytes[1],
            y1: bytes[2],
            x2: bytes[3],
            y2: bytes[4],
        })
    }
}

impl GameServer {
    pub fn handle_connection(&self, mut connection: TcpStream, player: Player) {
        let mut buf = [0_u8; CLIENT_MESSAGE_SIZE];
        loop {
            match connection.read_exact(&mut buf) {
                Ok(()) => {
                    let message = match ClientMessage::from_bytes(buf) {
                        Ok(message) => message,
                        Err(ClientMessageParseError::UnknownMessageType(byte)) => {
                            eprintln!("Received message with unknown type: {byte}");
                            continue;
                        }
                    };

                    if let Err(err) = Self::validate_message(&message) {
                        eprintln!("{err}");
                        continue;
                    }

                    let should_continue =
                        self.handle_client_message(&mut connection, message, &player);
                    if !should_continue {
                        break;
                    }
                }
                Err(e) => {
                    eprintln!("Failed to read from tcp stream {e}");
                    self.handle_disconnect(&player);
                    break;
                }
            }
        }
    }

    fn validate_message(message: &ClientMessage) -> Result<(), String> {
        match message.message_type {
            MessageType::GetState => Ok(()),
            MessageType::Hit => {
                if !Self::is_valid_cell(message.x1, message.y1) {
                    return Err(format!(
                        "Received hit message with out-of-bounds coordinates ({}, {})",
                        message.x1, message.y1
                    ));
                }
                Ok(())
            }
            MessageType::PlaceBoat => {
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

    fn handle_client_message(
        &self,
        connection: &mut TcpStream,
        message: ClientMessage,
        player: &Player,
    ) -> bool {
        match message.message_type {
            MessageType::PlaceBoat => {
                match player {
                    Player::A => {
                        self.player_a
                            .write()
                            .expect("Couldn't place boat for player A")
                            .place_boat(message.x1, message.y1, message.x2, message.y2);
                        // Check if with this placement we finished placing boats
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
                        // Check if with this placement we finished placing boats
                        self.all_boats_placed_player_b.store(
                            self.player_b
                                .read()
                                .expect("Failed to read player B board")
                                .all_boats_placed(),
                            Ordering::Relaxed,
                        );
                    }
                }
            }
            MessageType::GetState => {
                let (state, game_ended) = self.get_state(player);
                if let Err(e) = connection.write_all(&state) {
                    eprintln!("Failed to write state to socket: {e}");
                    self.handle_disconnect(player);
                    return false;
                }
                if game_ended {
                    return false;
                }
            }
            MessageType::Hit => {
                // If we are still in the boat placing phase we don't do anything in hit messages
                if !self.all_boats_placed_player_a.load(Ordering::Relaxed)
                    && !self.all_boats_placed_player_b.load(Ordering::Relaxed)
                {
                    eprintln!("Tried to hit a boat while still placing boats");
                    return true;
                }
                let turn_player_a = self.turn_player_a.load(Ordering::Acquire);

                match player {
                    Player::A => {
                        if turn_player_a {
                            self.player_b
                                .write()
                                .expect("Couldnt write to player b board")
                                .get_hit(message.x1, message.y1);
                            self.turn_player_a.store(false, Ordering::Release);
                        }
                    }
                    Player::B => {
                        if !turn_player_a {
                            self.player_a
                                .write()
                                .expect("Couldnt write to player b board")
                                .get_hit(message.x1, message.y1);
                            self.turn_player_a.store(true, Ordering::Release);
                        }
                    }
                }
            }
        }
        true
    }

    fn handle_disconnect(&self, player: &Player) {
        match player {
            Player::A => {
                self.player_a_forfeited.store(true, Ordering::Release);
            }
            Player::B => {
                self.player_b_forfeited.store(true, Ordering::Release);
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
    /// Bytes [101..202): State of the oponent's board
    ///
    /// Returns the game state in a 202 byte array and a bool that marks the game as ended
    fn get_state(&self, player: &Player) -> (Vec<u8>, bool) {
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
                    response.extend(player_a_board);
                    response.extend(player_b_board);
                    return (response, true);
                } else if player_b_forfeited {
                    response.push(254_u8);
                    response.push(self.turn_player_a.load(Ordering::Relaxed) as u8);
                    response.extend(player_a_board);
                    response.extend(player_b_board);
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
                response.extend(player_a_board);
                response.extend(player_b_board);
            }
            Player::B => {
                if player_b_forfeited {
                    response.push(255_u8);
                    response.push((!self.turn_player_a.load(Ordering::Relaxed)) as u8);
                    response.extend(player_b_board.clone());
                    response.extend(player_a_board.clone());
                    return (response, true);
                } else if player_a_forfeited {
                    response.push(254_u8);
                    response.push((!self.turn_player_a.load(Ordering::Relaxed)) as u8);
                    response.extend(player_b_board.clone());
                    response.extend(player_a_board.clone());
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
                response.extend(player_b_board);
                response.extend(player_a_board);
            }
        }
        debug_assert_eq!(response.len(), 202);
        (response, player_a_lost || player_b_lost)
    }
}
