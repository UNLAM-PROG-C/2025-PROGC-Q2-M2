use crate::board::Board;
use std::{
    io::{Read, Write},
    net::TcpStream,
    sync::{
        RwLock,
        atomic::{AtomicBool, Ordering},
    },
};

#[derive(Default)]

pub struct GameServer {
    player_a: RwLock<Board>,
    player_b: RwLock<Board>,
    turn_player_a: AtomicBool,
    all_boats_placed_player_a: AtomicBool,
    all_boats_placed_player_b: AtomicBool,
}

#[derive(Debug)]
pub enum Player {
    A,
    B,
}

#[expect(dead_code)]
#[derive(Debug)]
#[repr(u8)]
enum MessageType {
    GetState = 0_u8,
    Hit,
    PlaceBoat,
}

#[derive(Debug)]
#[repr(C)]
struct ClientMessage {
    message_type: MessageType,
    x1: u8,
    y1: u8,
    x2: u8,
    y2: u8,
}

impl GameServer {
    pub fn handle_connection(&self, mut connection: TcpStream, player: Player) {
        let mut buf = [0; size_of::<ClientMessage>()];
        loop {
            match connection.read_exact(&mut buf) {
                Ok(()) => {
                    let message: ClientMessage = unsafe { std::mem::transmute(buf) };
                    let should_continue =
                        self.handle_client_message(&mut connection, message, &player);
                    if !should_continue {
                        break;
                    }
                }
                Err(e) => {
                    eprintln!("Failed to read from tcp stream {e}");
                    break;
                }
            }
        }
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
                connection
                    .write_all(&state)
                    .expect("Failed to write state to socket");
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

        let player_a_lost = self.player_a.read().expect("Failed to read board").lost();
        let player_b_lost = self.player_b.read().expect("Failed to read board").lost();
        let placing_boats = !(self.all_boats_placed_player_a.load(Ordering::Relaxed)
            && self.all_boats_placed_player_b.load(Ordering::Relaxed));

        match player {
            Player::A => {
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
